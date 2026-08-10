from json import load
from django.shortcuts import render
from django.db.models import Count, Q
from django.http import FileResponse, HttpResponse, Http404
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.response import Response
from rest_framework import status, viewsets, permissions
from django.contrib.auth.hashers import make_password,check_password
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework.permissions import AllowAny, IsAuthenticated
from dotenv import load_dotenv
from .serializers import StudentSerializer, TeacherSerializer, ContentSerializer, QuizSerializer, QuestionSerializer, QuizPublicSerializer, QuizResultSerializer, AssignmentSubmissionSerializer, ProjectSubmissionSerializer, ConversationSerializer,MessageSerializer,ReactionSerializer, AttendanceSerializer, BillSerializer,TeacherPaymentQrSerializer,BillWithStudentSerializer,NotificationSerializer
from .models import Student, Teacher,CourseContent, Quiz, Question, QuizResult, StudentAnswer, AssignmentSubmission, ProjectSubmission, Conversation, Message, MessageReaction, Attendance, Bill, TeacherPaymentQr, Notification
from django.conf import settings
from django.core.files.storage import default_storage
from rest_framework.parsers import MultiPartParser, FormParser
import random, hashlib,hmac,base64,uuid,os
from datetime import timedelta
from django.utils import timezone
from django.core.mail import send_mail

load_dotenv()

def generate_otp():
    return str(random.randint(100000, 999999))

@api_view(['POST'])
def register_teacher(request):
    email = request.data.get('email', '')

    if not email.lower().strip().endswith('@gmail.com'):
        return Response(
            {"error": "Only Gmail addresses (@gmail.com) are allowed for registration."},
            status=status.HTTP_400_BAD_REQUEST
        )

    serializer = TeacherSerializer(data=request.data)

    if serializer.is_valid():
        hashed_pwd = make_password(request.data.get('password'))
        otp = generate_otp()
        teacher = serializer.save(
            password=hashed_pwd,
            is_verified=False,
            otp=otp,
            otp_created_at=timezone.now(),
        )

        email_sent = True
        try:
            send_mail(
                subject='Verify your Click-digitals account',
                message=f'Your verification code is: {otp}\nThis code expires in 10 minutes.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[teacher.email],
                fail_silently=False,
            )
        except Exception as e:
            email_sent = False
            print(f'Failed to send verification email: {e}')

        return Response(
            {
                "message": (
                    "Account created. Please check your email for the verification code."
                    if email_sent else
                    "Account created, but we couldn't send the verification email right now. "
                    "Use the Resend Code option once the issue is fixed."
                ),
                "email": teacher.email,
                "email_sent": email_sent,
            },
            status=status.HTTP_201_CREATED
        )

    print(serializer.errors)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([AllowAny])
def verify_otp(request):
    email = request.data.get('email')
    otp = request.data.get('otp')

    if not email or not otp:
        return Response({"error": "Email and OTP are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher = Teacher.objects.get(email__iexact=email)
    except Teacher.DoesNotExist:
        return Response({"error": "No account found with this email"}, status=status.HTTP_404_NOT_FOUND)

    if teacher.is_verified:
        return Response({"message": "Email already verified"}, status=status.HTTP_200_OK)

    if teacher.otp != otp:
        return Response({"error": "Invalid OTP"}, status=status.HTTP_400_BAD_REQUEST)

    if teacher.otp_created_at and timezone.now() > teacher.otp_created_at + timedelta(minutes=10):
        return Response({"error": "OTP expired, please request a new one"}, status=status.HTTP_400_BAD_REQUEST)

    teacher.is_verified = True
    teacher.otp = None
    teacher.otp_created_at = None
    teacher.save()

    return Response({"message": "Email verified successfully!"}, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([AllowAny])
def resend_otp(request):
    email = request.data.get('email')
    if not email:
        return Response({"error": "Email is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher = Teacher.objects.get(email__iexact=email)
    except Teacher.DoesNotExist:
        return Response({"error": "No account found with this email"}, status=status.HTTP_404_NOT_FOUND)

    if teacher.is_verified:
        return Response({"message": "Email already verified"}, status=status.HTTP_200_OK)

    otp = generate_otp()
    teacher.otp = otp
    teacher.otp_created_at = timezone.now()
    teacher.save()

    send_mail(
        subject='Your new verification code',
        message=f'Your verification code is: {otp}\nThis code expires in 10 minutes.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[teacher.email],
        fail_silently=False,
    )

    return Response({"message": "A new OTP has been sent to your email."}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def login_admin(request):
    email = request.data.get('email')
    password = request.data.get('password')

    if not email or not password:
        return Response({"error": "Email and password are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher = Teacher.objects.get(email__iexact=email)
        
        if check_password(password, teacher.password):
            
            # --- FIXED: Manual JWT Token Generation ---
            refresh = RefreshToken()
            # Manually embed your custom primary key 'tid' into the token payload
            refresh['user_id'] = teacher.tid 
            
            return Response({
                "message": "Login successful!",
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
                "admin": {
                    "tid": teacher.tid,
                    "username": teacher.username,
                    "email": teacher.email,
                }
            }, status=status.HTTP_200_OK)
                             
        else:
            return Response({"error": "Invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)
            
    except Teacher.DoesNotExist:
        return Response({"error": "Invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)
    
@api_view(['POST'])
@permission_classes([AllowAny])
def register_student(request):
    email = request.data.get('email', '')

    if not email.lower().strip().endswith('@gmail.com'):
        return Response(
            {"error": "Only Gmail addresses (@gmail.com) are allowed for registration."},
            status=status.HTTP_400_BAD_REQUEST
        )

    serializer = StudentSerializer(data=request.data)

    if serializer.is_valid():
        hashed_pwd = make_password(request.data.get('password'))
        otp = generate_otp()
        student = serializer.save(
            password=hashed_pwd,
            is_verified=False,
            otp=otp,
            otp_created_at=timezone.now(),
        )

        email_sent = True
        try:
            send_mail(
                subject='Verify your Click-digitals account',
                message=f'Your verification code is: {otp}\nThis code expires in 10 minutes.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[student.email],
                fail_silently=False,
            )
        except Exception as e:
            email_sent = False
            print(f'Failed to send verification email: {e}')

        return Response(
            {
                "message": (
                    "Account created. Please check your email for the verification code."
                    if email_sent else
                    "Account created, but we couldn't send the verification email right now. "
                    "Use the Resend Code option once the issue is fixed."
                ),
                "email": student.email,
                "email_sent": email_sent,
            },
            status=status.HTTP_201_CREATED
        )

    print(serializer.errors)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([AllowAny])
def verify_student_otp(request):
    email = request.data.get('email')
    otp = request.data.get('otp')

    if not email or not otp:
        return Response({"error": "Email and OTP are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student = Student.objects.get(email__iexact=email)
    except Student.DoesNotExist:
        return Response({"error": "No account found with this email"}, status=status.HTTP_404_NOT_FOUND)

    if student.is_verified:
        return Response({"message": "Email already verified"}, status=status.HTTP_200_OK)

    if student.otp != otp:
        return Response({"error": "Invalid OTP"}, status=status.HTTP_400_BAD_REQUEST)

    if student.otp_created_at and timezone.now() > student.otp_created_at + timedelta(minutes=10):
        return Response({"error": "OTP expired, please request a new one"}, status=status.HTTP_400_BAD_REQUEST)

    student.is_verified = True
    student.otp = None
    student.otp_created_at = None
    student.save()

    return Response({"message": "Email verified successfully!"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def resend_student_otp(request):
    email = request.data.get('email')
    if not email:
        return Response({"error": "Email is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student = Student.objects.get(email__iexact=email)
    except Student.DoesNotExist:
        return Response({"error": "No account found with this email"}, status=status.HTTP_404_NOT_FOUND)

    if student.is_verified:
        return Response({"message": "Email already verified"}, status=status.HTTP_200_OK)

    otp = generate_otp()
    student.otp = otp
    student.otp_created_at = timezone.now()
    student.save()

    send_mail(
        subject='Your new verification code',
        message=f'Your verification code is: {otp}\nThis code expires in 10 minutes.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[student.email],
        fail_silently=False,
    )

    return Response({"message": "A new OTP has been sent to your email."}, status=status.HTTP_200_OK)



@api_view(['POST'])
@permission_classes([AllowAny])
def login_student(request):
    email = request.data.get('email', '').strip()
    password = request.data.get('password')

    if not email or not password:
        return Response({"error": "Email and password are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student = Student.objects.get(email__iexact=email)
    except Student.DoesNotExist:
        return Response({"error": "Invalid email or password"}, status=status.HTTP_401_UNAUTHORIZED)

    if not check_password(password, student.password):
        return Response({"error": "Invalid email or password"}, status=status.HTTP_401_UNAUTHORIZED)

    if not student.is_verified:
        return Response({"error": "Email not verified. Please verify your email first."}, status=status.HTTP_403_FORBIDDEN)

    return Response({
        "message": "Login successful!",
        "student": {
            "sid": student.sid,
            "username": student.username,
            "email": student.email,
            "tid": student.teacher_id,
        }
    }, status=status.HTTP_200_OK)

    
@api_view(['GET'])
@permission_classes([AllowAny])
def list_students(request,teacher_id):
    students=Student.objects.filter(teacher_id=teacher_id)
    serializer=StudentSerializer(students,many=True)
    return Response(serializer.data)

@api_view(['PUT','PATCH'])
@permission_classes([AllowAny])
def update_students(request,student_id):
    try:
        student=Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)
    serializer=StudentSerializer(student, data=request.data, partial=True)
    if serializer.is_valid():
            hashed_pwd = make_password(request.data.get('password'))
            otp = generate_otp()
            student = serializer.save(
                password=hashed_pwd,
                is_verified=False,
                otp=otp,
                otp_created_at=timezone.now(),
            )
    
            email_sent = True
            try:
                send_mail(
                    subject='Verify your Click-digitals account',
                    message=f'Your verification code is: {otp}\nThis code expires in 10 minutes.',
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[student.email],
                    fail_silently=False,
                )
            except Exception as e:
                email_sent = False
                print(f'Failed to send verification email: {e}')
    
            return Response(
                {
                    "message": (
                        "Account created. Please check your email for the verification code."
                        if email_sent else
                        "Account created, but we couldn't send the verification email right now. "
                        "Use the Resend Code option once the issue is fixed."
                    ),
                    "email": student.email,
                    "email_sent": email_sent,
                },
                status=status.HTTP_201_CREATED
            )
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_student(request,student_id):
    try:
        student=Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)
    student.delete()
    return Response({"message": "Student deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser,FormParser])
def upload_content(request):
    serializer=ContentSerializer(data=request.data)
    if serializer.is_valid():
        serializer.save()
        return Response({"message":"content upload successfully"}, status=status.HTTP_201_CREATED)
    print(serializer.errors)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)



@api_view(['GET'])
@permission_classes([AllowAny])
def list_content(request,teacher_id,content_type):
    items=CourseContent.objects.filter(teacher_id=teacher_id, content_type=content_type)
    serializer=ContentSerializer(items,many=True)
    return Response(serializer.data)

@api_view(['PUT','PATCH'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser,FormParser])
def update_content(request, pk):
    try:
        content=CourseContent.objects.get(pk=pk)

    except CourseContent.DoesNotExist:
        return Response({"error": "Content not found"}, status=status.HTTP_404_NOT_FOUND)
    
    if 'file' in request.data and content.file:
        content.file.delete(save=False)
    
    serializer=ContentSerializer(content, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save();
        return Response({"message": "Content updated successfully"}, status=status.HTTP_200_OK)
    
    print(serializer.errors);
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_content(request, pk):
    try:
        content=CourseContent.objects.get(pk=pk)

    except CourseContent.DoesNotExist:
        return Response({"error": "Content not found"}, status=status.HTTP_404_NOT_FOUND)
    
    if content.file:
        content.file.delete(save=False)
    content.delete()
    return Response({"message": "Content deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def create_quiz(request):
    serializer=QuizSerializer(data=request.data)
    if(serializer.is_valid()):
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([AllowAny])
def add_question(request, quiz_id):
    try:
        quiz=Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)
    
    data=request.data.copy()
    data['quiz'] = quiz.quid
    serializer=QuestionSerializer(data=data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_teacher_quizzes(request, teacher_id):
    quizzes = Quiz.objects.filter(teacher_id=teacher_id)
    serializer = QuizSerializer(quizzes, many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def quiz_results(request, quiz_id):
    results = QuizResult.objects.filter(quiz_id=quiz_id)
    serializer = QuizResultSerializer(results, many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_quiz_for_student(request, quiz_id):
    try:
        quiz = Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)

    serializer = QuizPublicSerializer(quiz)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_quiz_detail(request, quiz_id):
    try:
        quiz = Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)
    serializer = QuizSerializer(quiz)
    return Response(serializer.data)

@api_view(['POST'])
@permission_classes([AllowAny])
def submit_quiz(request, quiz_id):
    """
    Expected body:
    {
        "student_id": 3,
        "answers": [
            {"question_id": 1, "selected_option": "A"},
            {"question_id": 2, "selected_option": "C"}
        ]
    }
    """
    student_id = request.data.get('student_id')
    answers = request.data.get('answers', [])

    if not student_id or not answers:
        return Response({"error": "student_id and answers are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        quiz = Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)

    if QuizResult.objects.filter(quiz=quiz, student_id=student_id).exists():
        return Response({"error": "You have already attempted this quiz"}, status=status.HTTP_400_BAD_REQUEST)

    total = len(answers)
    score = 0
    graded_answers = []

    for ans in answers:
        try:
            question = Question.objects.get(qsid=ans['question_id'], quiz=quiz)
        except Question.DoesNotExist:
            continue

        selected = ans.get('selected_option', '').upper()
        is_correct = selected == question.correct_option
        if is_correct:
            score += 1

        graded_answers.append((question, selected, is_correct))

    result = QuizResult.objects.create(
        quiz=quiz, student_id=student_id, score=score, total_questions=total
    )

    for question, selected, is_correct in graded_answers:
        StudentAnswer.objects.create(
            result=result, question=question, selected_option=selected, is_correct=is_correct
        )

    serializer = QuizResultSerializer(result)
    return Response(serializer.data, status=status.HTTP_201_CREATED)

@api_view(['PUT','PATCH'])
@permission_classes([AllowAny])
def update_quiz(request,quiz_id):
    try:
        quiz = Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)

    serializer = QuizSerializer(quiz, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_200_OK)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_quiz(request, quiz_id):
    try:
        quiz = Quiz.objects.get(quid=quiz_id)
    except Quiz.DoesNotExist:
        return Response({"error": "Quiz not found"}, status=status.HTTP_404_NOT_FOUND)

    quiz.delete()  # cascades to its questions and results
    return Response({"message": "Quiz deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['PUT','PATCH'])
@permission_classes([AllowAny])
def update_question(request,question_id):
    try:
        question=Question.objects.get(qsid=question_id)
    except Question.DoesNotExist:
        return Response({"error": "Question not found"}, status=status.HTTP_404_NOT_FOUND)
    
    serializer=QuestionSerializer(question, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save();
        return Response(serializer.data, status=status.HTTP_200_OK)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_question(request,question_id):
    try:
        question = Question.objects.get(qsid=question_id)
    except Question.DoesNotExist:
        return Response({"error": "Question not found"}, status=status.HTTP_404_NOT_FOUND)

    question.delete()
    return Response({"message": "Question deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_assignment_student(request, student_id):
    submissions = AssignmentSubmission.objects.filter(student_id=student_id)
    serializer = AssignmentSubmissionSerializer(submissions, many=True)
    return Response(serializer.data)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_project_student(request, student_id):
    submissions = ProjectSubmission.objects.filter(student_id=student_id)
    serializer = ProjectSubmissionSerializer(submissions, many=True)
    return Response(serializer.data)

@api_view(['POST'])
@permission_classes([AllowAny])
def get_or_create_conversation(request):
    teacher_id = request.data.get('teacher')
    student_id = request.data.get('student')
    topic = request.data.get('topic', 'messages')

    conversation, _ = Conversation.objects.get_or_create(
        teacher_id=teacher_id, 
        student_id=student_id, 
        topic=topic
    )
    
    # Return conversation details along with previous messages
    messages = conversation.messages.all().order_by('created_at')
    
    return Response({
        "conversation": ConversationSerializer(conversation).data,
        "messages": MessageSerializer(messages, many=True).data
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def send_message(request):
    conv_id=request.data.get('convid')
    sender_type=request.data.get('sender_type')
    text=request.data.get('text','')
    attachment = request.FILES.get('attachment', None)
    message = Message.objects.create(
        conversation_id=conv_id,
        sender_type=sender_type,
        text=text,
        attachment=attachment
    )
    return Response(MessageSerializer(message).data, status=status.HTTP_201_CREATED)

@api_view(['POST'])
@permission_classes([AllowAny])
def toggle_reaction(request):
    message_id=request.data.get('message_id')
    user_type=request.data.get('user_type')
    emoji=request.data.get('emoji')

    # Querying using message_id (matching the explicit FK field name)
    reaction, created = MessageReaction.objects.get_or_create(
        message_id=message_id, 
        user_type=user_type,
        defaults={'emoji': emoji}
    )

    if not created:
        if reaction.emoji==emoji:
            reaction.delete()
        else:
            reaction.emoji=emoji
            reaction.save()

    updated_reactions = MessageReaction.objects.filter(message_id=message_id)
    return Response({
        'status': 'success',
        'reactions': ReactionSerializer(updated_reactions, many=True).data,
    }, status=status.HTTP_200_OK)

@api_view(['PATCH'])
@permission_classes([AllowAny])
def edit_message(request, message_id):
    try:
        message = Message.objects.get(message_id=message_id)
    except Message.DoesNotExist:
        return Response({"error": "Message not found"}, status=status.HTTP_404_NOT_FOUND)

    message.text = request.data.get('text', message.text)
    message.save()
    return Response(MessageSerializer(message).data, status=status.HTTP_200_OK)


@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_message(request, message_id):
    try:
        message = Message.objects.get(message_id=message_id)
    except Message.DoesNotExist:
        return Response({"error": "Message not found"}, status=status.HTTP_404_NOT_FOUND)

    message.delete()
    return Response({"message": "Message deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_attendance_for_date(request,teacher_id):
    date_str=request.GET.get('date')
    if not date_str:
        return Response({"error": "date query param is required (YYYY-MM-DD)"}, status=status.HTTP_400_BAD_REQUEST)

    students=Student.objects.filter(teacher_id=teacher_id)
    existing={a.student_id: a for a in Attendance.objects.filter(teacher_id=teacher_id, date=date_str)}

    data=[]
    for s in students:
        record=existing.get(s.sid)
        data.append({
            'sid': s.sid,
            'username': s.username,
            'status': record.status if record else None,
            'remarks': record.remarks if record else '',
        })
    return Response(data, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def save_attendance(request):
    teacher_id=request.data.get('teacher')
    date_str=request.data.get('date')
    records = request.data.get('records', [])
    if not teacher_id or not date_str:
        return Response({"error": "teacher and date are required"}, status=status.HTTP_400_BAD_REQUEST)

    for r in records:
        Attendance.objects.update_or_create(
            student_id=r['student'],
            date=date_str,
            defaults={
                'teacher_id': teacher_id,
                'status': r.get('status', 'present'),
                'remarks': r.get('remarks', ''),
            }
        )
    return Response({"message": "Attendance saved successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_student_attendance_history(request, student_id):
    records = Attendance.objects.filter(student_id=student_id).order_by('-date')
    serializer = AttendanceSerializer(records, many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_attendance_dates(request,teacher_id):
    records=Attendance.objects.filter(teacher_id=teacher_id).order_by('-date')
    summary={}
    for r in records:
        d=str(r.date)
        if d not in summary:
            summary[d]={'date': d, 'present': 0, 'absent': 0, 'late': 0}
        summary[d][r.status] += 1

    data=list(summary.values())
    data.sort(key=lambda x: x['date'], reverse=True)

    return Response(data, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_teacher_students_report(request, teacher_id):
    """Calculates attendance percentage for all students under a teacher."""
    students = Student.objects.filter(teacher_id=teacher_id).annotate(
        total=Count('attendance_records'),
        present=Count('attendance_records', filter=Q(attendance_records__status='present')),
        late=Count('attendance_records', filter=Q(attendance_records__status='late')),
        absent=Count('attendance_records', filter=Q(attendance_records__status='absent')),
    )

    report = []
    for student in students:
        total = student.total
        present = student.present
        late = student.late
        absent = student.absent

        perpre = round((present / total * 100), 1) if total > 0 else 0.0
        prelate = round((late / total * 100), 1) if total > 0 else 0.0
        preabs = round((absent / total * 100), 1) if total > 0 else 0.0

        report.append({
            'sid': student.sid,
            'username': student.username,
            'total_days': total,
            'present_days': present,
            'late_days': late,
            'percentage_of_present': perpre,
            'percentage_of_late': prelate,
            'percentage_of_absent': preabs
        })

    return Response(report, status=status.HTTP_200_OK)


@api_view(['GET'])
def bills_by_student(request, student_id):
    bills = Bill.objects.filter(student_id=student_id).order_by('-created_at')
    serializer = BillSerializer(bills, many=True)
    return Response(serializer.data)


@api_view(['POST'])
def create_bill(request):
    serializer = BillSerializer(data=request.data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['PATCH'])
def mark_cash_paid(request, bill_id):
    try:
        bill = Bill.objects.get(bid=bill_id)
    except Bill.DoesNotExist:
        return Response({'error': 'Bill not found'}, status=404)

    from django.utils import timezone
    bill.status = 'paid'
    bill.payment_method = 'cash'
    bill.paid_date = timezone.now().date()
    bill.save()
    return Response(BillSerializer(bill).data)


@api_view(['PATCH'])
@parser_classes([MultiPartParser, FormParser])
def submit_payment_proof(request, bill_id):
    try:
        bill = Bill.objects.get(bid=bill_id)
    except Bill.DoesNotExist:
        return Response({'error': 'Bill not found'}, status=404)

    bill.transaction_code = request.data.get('transaction_code', '')
    bill.payment_method = request.data.get('payment_method', 'esewa')
    if 'payment_screenshot' in request.FILES:
        bill.payment_screenshot = request.FILES['payment_screenshot']
    bill.status = 'pending'  # awaiting teacher verification
    bill.save()
    return Response(BillSerializer(bill).data)


@api_view(['PATCH'])
def verify_payment(request, bill_id):
    """Teacher approves or rejects a pending bill."""
    try:
        bill = Bill.objects.get(bid=bill_id)
    except Bill.DoesNotExist:
        return Response({'error': 'Bill not found'}, status=404)

    new_status = request.data.get('status')  # 'paid' or 'rejected'
    if new_status not in ('paid', 'rejected'):
        return Response({'error': 'status must be paid or rejected'}, status=400)

    from django.utils import timezone
    bill.status = new_status
    if new_status == 'paid':
        bill.paid_date = timezone.now().date()
    bill.save()
    return Response(BillSerializer(bill).data)


@api_view(['DELETE'])
def delete_bill(request, bill_id):
    try:
        bill = Bill.objects.get(bid=bill_id)
    except Bill.DoesNotExist:
        return Response({'error': 'Bill not found'}, status=404)
    bill.delete()
    return Response(status=204)


@api_view(['GET'])
def get_teacher_qr(request, teacher_id):
    try:
        qr = TeacherPaymentQr.objects.get(teacher_id=teacher_id)
    except TeacherPaymentQr.DoesNotExist:
        return Response({'error': 'No QR uploaded'}, status=404)
    return Response(TeacherPaymentQrSerializer(qr).data)


@api_view(['POST'])
@parser_classes([MultiPartParser, FormParser])
def upload_teacher_qr(request, teacher_id):
    if 'payment_qr_file' not in request.FILES:
        return Response({'error': 'payment_qr_file is required'}, status=400)

    qr, _created = TeacherPaymentQr.objects.update_or_create(
        teacher_id=teacher_id,
        defaults={'payment_qr_file': request.FILES['payment_qr_file']}
    )
    return Response(TeacherPaymentQrSerializer(qr).data, status=200)
     
@api_view(['GET'])
def bills_by_teacher(request, teacher_id):
    bills = Bill.objects.filter(teacher_id=teacher_id).order_by('-created_at')
    serializer = BillWithStudentSerializer(bills, many=True)  # this one needs student_name
    return Response(serializer.data)

@api_view(['PATCH'])
def update_bill(request, bill_id):
    try:
        bill = Bill.objects.get(bid=bill_id)
    except Bill.DoesNotExist:
        return Response({'error': 'Bill not found'}, status=404)

    serializer = BillSerializer(bill, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data)
    return Response(serializer.errors, status=400)

@api_view(['POST'])
@permission_classes([AllowAny])
def change_teacher_password(request, teacher_id):
    old_password = request.data.get('old_password')
    new_password = request.data.get('new_password')

    if not old_password or not new_password:
        return Response({"error": "Both current and new password are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher = Teacher.objects.get(tid=teacher_id)
    except Teacher.DoesNotExist:
        return Response({"error": "Teacher not found"}, status=status.HTTP_404_NOT_FOUND)

    if not check_password(old_password, teacher.password):
        return Response({"error": "Current password is incorrect"}, status=status.HTTP_401_UNAUTHORIZED)

    if len(new_password) < 6:
        return Response({"error": "New password must be at least 6 characters"}, status=status.HTTP_400_BAD_REQUEST)

    teacher.password = make_password(new_password)
    teacher.save()
    return Response({"message": "Password changed successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def teacher_notifications(request, teacher_id):
    notifications=Notification.objects.filter(teacher_id=teacher_id).order_by('-created_at')
    serializer=NotificationSerializer(notifications, many=True)
    return Response(serializer.data)

@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_notification_as_read(request, notification_id):
    try:
        notification=Notification.objects.get(nid=notification_id)
    except Notification.DoesNotExist:
        return Response({"error": "Notification not found"}, status=status.HTTP_404_NOT_FOUND)

    notification.status='read'
    notification.save()
    return Response(NotificationSerializer(notification).data)

@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_all_read(request, teacher_id):
    Notification.objects.filter(teacher_id=teacher_id, is_read=False).update(is_read=True)
    return Response({'status': 'all marked read'})

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_notifications(request, teacher_id):
    try:
        notifications=Notification.objects.filter(teacher_id=teacher_id)
    except Notification.DoesNotExist:
        return Response({"error": "No notifications found for this teacher"}, status=status.HTTP_404_NOT_FOUND)
    notifications.delete()
    return Response({"message": "All notifications deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def student_list_content(request, student_id, content_type):
    try:
        student= Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    items=CourseContent.objects.filter(teacher_id=student.teacher_id, content_type=content_type,level=student.level).order_by('-created_at')
    serializer=ContentSerializer(items,many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def stream_content(request, cid):
    try:
        content = CourseContent.objects.get(cid=cid)
    except CourseContent.DoesNotExist:
        return Response({"error": "Content not found"}, status=status.HTTP_404_NOT_FOUND)
    if not content.file:
        return Response({"error": "No file attached to this content"}, status=status.HTTP_404_NOT_FOUND)
    return FileResponse(content.file.open('rb'), content_type='application/octet-stream')

@api_view(['GET'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def submit_assignment(request, assignment_id):
    try:
        student = Student.objects.get(pid=assignment_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    data=request.data.copy()
    data['student'] = student.sid
    data['teacher'] = student.teacher_id
    serializer=AssignmentSubmissionSerializer(data=data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['GET'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def submit_project(request, project_id):
    try:
        student = Student.objects.get(pid=project_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    data=request.data.copy()
    data['student'] = student.sid
    data['teacher'] = student.teacher_id
    serializer=ProjectSubmissionSerializer(data=data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

