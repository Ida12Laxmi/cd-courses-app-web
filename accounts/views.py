from json import load
from django.shortcuts import render
from django.db.models import Count, Q, Sum
import re
from calendar import month_abbr
from django.db.models.functions import TruncMonth
from django.http import FileResponse, HttpResponse, Http404
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.response import Response
from rest_framework import status, viewsets, permissions
from django.contrib.auth.hashers import make_password,check_password
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework.permissions import AllowAny, IsAuthenticated
from dotenv import load_dotenv
from .serializers import StudentSerializer, TeacherSerializer, ContentSerializer, QuizSerializer, QuestionSerializer, QuizPublicSerializer, QuizResultSerializer, AssignmentSubmissionSerializer, ProjectSubmissionSerializer, ConversationSerializer,MessageSerializer,ReactionSerializer, AttendanceSerializer, BillSerializer,TeacherPaymentQrSerializer,BillWithStudentSerializer,NotificationSerializer,AdminSideSerializer
from .models import DeviceToken, Student, Teacher,CourseContent, Quiz, Question, QuizResult, StudentAnswer, AssignmentSubmission, ProjectSubmission, Conversation, Message, MessageReaction, Attendance, Bill, TeacherPaymentQr, Notification,DeviceToken,AdminSide
from .firebase_utils import send_push_to_user, notify_student, notify_teacher
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
        Notification.objects.create(
            teacher=None,
            student=student,
            recipient='admin',
            notif_type='student_registered',
            title='New student registered',
            message=f'{student.username} ({student.email}) just registered.',
            related_id=student.sid,

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
        return Response({"error": "Email not verified. Please verify your email first.", "needs_verification": True}, status=status.HTTP_403_FORBIDDEN)

    #Fixed manual jwt token generation
    refresh=RefreshToken()
    refresh['user_id']=student.sid

    return Response({
        "message": "Login successful!",
        "tokens":{
            "refresh":str(refresh),
            "access":str(refresh.access_token),
        },
        "student": {
            "sid": student.sid,
            "username": student.username,
            "email": student.email,
            "tid": student.teacher_id,
            "level": student.level,
            "subject": student.subject,   
        }
    }, status=status.HTTP_200_OK)

    
@api_view(['GET'])
@permission_classes([AllowAny])
def list_students(request,teacher_id):
    students=Student.objects.filter(teacher_id=teacher_id)
    serializer=StudentSerializer(students,many=True)
    return Response(serializer.data)

@api_view(['PUT', 'PATCH'])
@permission_classes([AllowAny])
def update_students(request, student_id):
    try:
        student = Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    data = request.data.copy()
    data.pop('password', None)  # password changes are not handled through this endpoint

    serializer = StudentSerializer(student, data=data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(StudentSerializer(student).data, status=status.HTTP_200_OK)
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
        content=serializer.save()
        students = Student.objects.filter(teacher_id=content.teacher_id,level=content.level)
        print(f'CONTENT LEVEL: {content.level!r} | Notifying {students.count()} students: {list(students.values_list("sid", "level"))}')
        for student in students:
            notify_student(
                student=student,
                notify_type='content_uploaded',
                title='New Content Available',
               message=(
            f'Your teacher uploaded new {content.content_type} '
            f'"{content.title}" for {content.level} level'
            f'{" - " + content.subject if content.subject else ""}.'
        ),
                related_id=content.cid
            )
        ADMIN_NOTIFY_TYPES = {
            'certificate': ('certificate_uploaded', 'New certificate uploaded'),
            'time table': ('timetable_uploaded', 'New timetable uploaded'),
            'announcement': ('announcement_published', 'New announcement published'),
        }
        if content.content_type in ADMIN_NOTIFY_TYPES:
            notif_type, title = ADMIN_NOTIFY_TYPES[content.content_type]
            teacher_name = content.teacher.username if content.teacher else 'A teacher'
            Notification.objects.create(
                teacher=content.teacher,
                recipient='admin',
                notif_type=notif_type,
                title=title,
                message=f'{teacher_name} uploaded "{content.title}".',
                related_id=content.cid,
            )
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
        quiz=serializer.save()
        students = Student.objects.filter(teacher_id=quiz.teacher_id,level=quiz.level,subject__iexact=quiz.subject)
        print(f'QUIZ LEVEL: {quiz.level!r} | Notifying {students.count()} students: {list(students.values_list("sid", "level"))}')

        for student in students:
            notify_student(
                student=student,
                notify_type='quiz_created',
                title='New Quiz Available',
                              message=(
                    f'A new quiz "{quiz.title}" for {quiz.level} level'
                    f'{" - " + quiz.subject if quiz.subject else ""} '
                    f'has been created by your teacher.'
                ),

                related_id=quiz.quid
            )
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
def student_list_quizzes(request, student_id):
    try:
        student = Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    quizzes = Quiz.objects.filter(
        teacher_id=student.teacher_id,
        level=student.level,
        subject__iexact=student.subject,
    ).order_by('-created_at')
    serializer = QuizPublicSerializer(quizzes, many=True)
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
    conv_id = request.data.get('convid')
    sender_type = request.data.get('sender_type')
    text = request.data.get('text', '')
    attachment = request.FILES.get('attachment', None)
    message = Message.objects.create(
        conversation_id=conv_id,
        sender_type=sender_type,
        text=text,
        attachment=attachment
    )

    try:
        conversation = Conversation.objects.get(convid=conv_id)
    except Conversation.DoesNotExist:
        conversation = None

    if conversation:
        if sender_type == 'teacher':
            try:
                student = Student.objects.get(sid=conversation.student_id)
                notify_student(
                    student=student,
                    notify_type='new_message',
                    title='New Message from Teacher',
                    message='You have a new message from your teacher.',
                    related_id=message.message_id
                )
            except Student.DoesNotExist:
                pass

        elif sender_type == 'student':
            try:
                teacher = Teacher.objects.get(tid=conversation.teacher_id)
                student = Student.objects.get(sid=conversation.student_id)
                student_name = getattr(student, 'name', None) or 'A student'
                notify_teacher(
                    teacher=teacher,
                    notify_type='new_message',
                    title='New Message from Student',
                    message=f'{student_name} sent you a new message.',
                    related_id=message.message_id
                )
            except (Teacher.DoesNotExist, Student.DoesNotExist):
                pass

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
def get_attendance_for_date(request, teacher_id):
    date_str = request.GET.get('date')
    if not date_str:
        return Response({"error": "date query param is required (YYYY-MM-DD)"}, status=status.HTTP_400_BAD_REQUEST)

    students = Student.objects.filter(teacher_id=teacher_id)
    existing = {a.student_id: a for a in Attendance.objects.filter(teacher_id=teacher_id, date=date_str)}

    data = []
    for s in students:
        record = existing.get(s.sid)
        data.append({
            'sid': s.sid,
            'username': s.username,
            'subject': s.subject or '',
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
        try:
            student = Student.objects.get(sid=r['student'])
            notify_student(
                student=student,
                notify_type='attendance_marked',
                title='Attendance Update',
                message=f'Your attendance for {date_str} has been marked as {r.get("status", "present")}.',
                related_id=None
            )
        except Student.DoesNotExist:
            pass  # Skip notification if student does not exist

        try:
            teacher_obj=Teacher.objects.get(tid=teacher_id)
            teacher_name=teacher_obj.username
        except Teacher.DoesNotExist:
            pass
        Notification.objects.create(
        teacher=teacher_obj,
        recipient='admin',
        notif_type='attendance_marked',
        title='Attendance marked',
        message=f'{teacher_name} marked attendance for {date_str} ({len(records)} student(s)).',
        related_id=None,
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
        bill=serializer.save()
        notify_student(
            student=bill.student,
            notify_type='new_bill',
            title=f'"{bill.title}" — Rs. {bill.amount}',
            message='A new bill has been created for you. Please check your account for details.',
            related_id=bill.bid
        )
        Notification.objects.create(
            teacher=bill.teacher,
            recipient='admin',
            notif_type='bill_generated',
            title='New bill generated',
            message=f'{bill.teacher.username} billed {bill.student.username} — Rs. {bill.amount} for "{bill.title}".',
            related_id=bill.bid,
        )
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

    try:
        student = Student.objects.get(sid=bill.student_id)
        notify_student(
            student=student,
            notify_type='payment_verified',
            title='Payment Recorded',
            message=f'Your teacher marked "{bill.title}" as paid (cash).',
            related_id=bill.bid,
        )
    except Student.DoesNotExist:
        pass
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

    try:
        teacher = Teacher.objects.get(tid=bill.teacher_id)
        student = Student.objects.get(sid=bill.student_id)
        student_name = getattr(student, 'name', None) or 'A student'
        notify_teacher(
            teacher=teacher,
            notify_type='payment_submitted',
            title='Payment Proof Submitted',
            message=f'{student_name} submitted payment proof for {bill.title}.',
            related_id=bill.bid,
        )
    except (Teacher.DoesNotExist, Student.DoesNotExist):
        pass
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

    try:
        student = Student.objects.get(sid=bill.student_id)
        if new_status == 'paid':
            notify_student(
                student=student,
                notify_type='payment_verified',
                title='Payment Verified',
                message=f'Your payment for "{bill.title}" has been confirmed.',
                related_id=bill.bid,
            )
        else:
            notify_student(
                student=student,
                notify_type='payment_rejected',
                title='Payment Rejected',
                message=f'Your payment proof for "{bill.title}" was rejected. Please resubmit.',
                related_id=bill.bid,
            )
    except Student.DoesNotExist:
        pass
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
    notifications=Notification.objects.filter(teacher_id=teacher_id, recipient='teacher').order_by('-created_at')
    serializer=NotificationSerializer(notifications, many=True)
    return Response(serializer.data)

@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_notification_as_read(request, notification_id):
    try:
        notification=Notification.objects.get(nid=notification_id)
    except Notification.DoesNotExist:
        return Response({"error": "Notification not found"}, status=status.HTTP_404_NOT_FOUND)

    notification.is_read=True
    notification.save()
    return Response(NotificationSerializer(notification).data)

@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_all_read(request, teacher_id):
    Notification.objects.filter(teacher_id=teacher_id, is_read=False).update(is_read=True)
    return Response({'status': 'all marked read'})

@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_all_read_student(request, student_id):
    Notification.objects.filter(student_id=student_id, is_read=False).update(is_read=True)
    return Response({'status': 'all marked read'})

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_notification(request, notif_id):
    try:
        notification = Notification.objects.get(nid=notif_id)
    except Notification.DoesNotExist:
        return Response({"error": "Notification not found"}, status=status.HTTP_404_NOT_FOUND)
    notification.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)

@api_view(['GET'])
@permission_classes([AllowAny])
def student_list_content(request, student_id, content_type):
    try:
        student= Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    items = CourseContent.objects.filter(
    teacher_id=student.teacher_id,
    content_type=content_type,
    level=student.level,
    subject__iexact=student.subject,
).order_by('-created_at')
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




@api_view(['POST'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def submit_assignment(request, student_id):
    try:
        student = Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    data = request.data.copy()
    data['student'] = student.sid
    data['teacher'] = student.teacher_id
    serializer = AssignmentSubmissionSerializer(data=data)
    if serializer.is_valid():
        submission =serializer.save()
        Notification.objects.create(
            teacher_id=student.teacher_id,
            student=student,
            notif_type='assignment_submitted',
            title='New assignment submitted',
            message=f'{student.username} submitted "{submission.title}"',
            related_id=submission.asid,
        )
        send_push_to_user(
            role='teacher',
            user_id=student.teacher_id,
            title='New assignment submitted',
            body=f'{student.username} submitted "{submission.title}"',
        )
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def submit_project(request, student_id):
    try:
        student = Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    data = request.data.copy()
    data['student'] = student.sid
    data['teacher'] = student.teacher_id
    serializer = ProjectSubmissionSerializer(data=data)
    if serializer.is_valid():
        submission = serializer.save()
        Notification.objects.create(
            teacher_id=student.teacher_id,
            student=student,
            notif_type='project_submitted',
            title='New project submitted',
            message=f'{student.username} submitted "{submission.title}"',
            related_id=submission.psid,
        )
        send_push_to_user(
            role='teacher',
            user_id=student.teacher_id,
            title='New project submitted',
            body=f'{student.username} submitted "{submission.title}"',
        )
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([AllowAny])
def register_device_token(request):
    role = request.data.get('role')
    user_id = request.data.get('user_id')
    token = request.data.get('token')

    if not role or not user_id or not token:
        return Response({"error": "role, user_id, and token are required"}, status=status.HTTP_400_BAD_REQUEST)

    DeviceToken.objects.update_or_create(
        device_token=token,
        defaults={'role': role, 'user_id': user_id}
    )

    return Response({"message": "Device token registered successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def student_notifications(request, student_id):
    notifications = Notification.objects.filter(student_id=student_id, recipient='student').order_by('-created_at')
    serializer = NotificationSerializer(notifications, many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def student_search_content(request, student_id):
    query=request.GET.get('q','').strip()
    content_type_filter=request.GET.get('type','').strip()
    try:
        student=Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error":"Student does not exist"}, status=status.HTTP_404_NOT_FOUND)

    searchable_types=['syllabus','notes','video','result','certificate','reference','time table']

    if content_type_filter:
        if content_type_filter not in searchable_types:
             return Response({"error": "Invalid content type"}, status=status.HTTP_400_BAD_REQUEST)
        types_to_use=[content_type_filter]
    else:
        types_to_use=searchable_types


    items = CourseContent.objects.filter(
    teacher_id=student.teacher_id,
    level=student.level,
    subject__iexact=student.subject,
    content_type__in=types_to_use,
)
    if query:
        escaped=re.escape(query)
        items=items.filter(Q(title__iregex=rf'(^|\s){escaped}'))
    items=items.order_by('title')
    serializer=ContentSerializer(items,many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def teacher_search_content(request, teacher_id):
    query=request.GET.get('q','').strip()
    content_type_filter=request.GET.get('type','').strip()
    try:
        teacher=Teacher.objects.get(tid=teacher_id)
    except Teacher.DoesNotExist:
        return Response({"error":"Teacher does not exist"}, status=status.HTTP_404_NOT_FOUND)

    searchable_types=['syllabus','notes','video','result','certificate','reference','time table','assignment','project','announcement','result','certificate']

    if content_type_filter:
        if content_type_filter not in searchable_types:
             return Response({"error": "Invalid content type"}, status=status.HTTP_400_BAD_REQUEST)
        types_to_use=[content_type_filter]
    else:
        types_to_use=searchable_types


    items=CourseContent.objects.filter(
        teacher_id=teacher.tid,
        content_type__in=types_to_use,
        
    )
    if query:
        escaped=re.escape(query)
        items=items.filter(Q(title__iregex=rf'(^|\s){escaped}'))
    items=items.order_by('title')
    serializer=ContentSerializer(items,many=True)
    return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def student_search_submissions(request,student_id,content_type):
    query=request.GET.get('q','').strip()
    if content_type not in ('assignment','project'):
         return Response({"error": "content_type must be 'assignment' or 'project'"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student=Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    escaped=re.escape(query) if query else None

    given = CourseContent.objects.filter(
        teacher_id=student.teacher_id,
        level=student.level,
        subject__iexact=student.subject,
        content_type=content_type,
    )

    if escaped:
        given=given.filter(Q(title__iregex=rf'(^|\s){escaped}'))
    given_data = ContentSerializer(given.order_by('title'), many=True).data

    if content_type=='assignment':
        submissions=AssignmentSubmission.objects.filter(student_id=student_id)
        if escaped:
            submissions= submissions.filter(Q(title__iregex=rf'(^|\s){escaped}'))
        sub_data=AssignmentSubmissionSerializer(submissions.order_by('title'),many=True).data
    else:
        submissions = ProjectSubmission.objects.filter(student_id=student_id)
        if escaped:
            submissions=submissions.filter(Q(title__iregex=rf'(^|\s){escaped}'))
        sub_data=ProjectSubmissionSerializer(submissions.order_by('title'),many=True).data

    return Response({
        "given": given_data,
        "submissions": sub_data,
    })

# --- Assignment feedback / update / delete ---

@api_view(['PATCH'])
@permission_classes([AllowAny])
def assignment_feedback(request, asid):
    try:
        submission = AssignmentSubmission.objects.get(asid=asid)
    except AssignmentSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    submission.teacher_feedback = request.data.get('teacher_feedback', submission.teacher_feedback)
    submission.save()

    notify_student(
        student=submission.student,
        notify_type='assignment_feedback',
        title='Feedback on your assignment',
        message=f'Your teacher left feedback on "{submission.title}".',
        related_id=submission.asid
    )

    return Response(AssignmentSubmissionSerializer(submission).data, status=status.HTTP_200_OK)


@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_assignment(request, asid):
    try:
        submission = AssignmentSubmission.objects.get(asid=asid)
    except AssignmentSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)
    if submission.file:
        submission.file.delete(save=False)
    submission.delete()
    return Response({"message": "Submission deleted successfully"}, status=status.HTTP_200_OK)


# --- Project feedback / update / delete (mirrors assignment) ---

@api_view(['PATCH'])
@permission_classes([AllowAny])
def project_feedback(request, psid):
    try:
        submission = ProjectSubmission.objects.get(psid=psid)
    except ProjectSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    submission.teacher_feedback = request.data.get('teacher_feedback', submission.teacher_feedback)
    submission.save()

    notify_student(
        student=submission.student,
        notify_type='project_feedback',
        title='Feedback on your project',
        message=f'Your teacher left feedback on "{submission.title}".',
        related_id=submission.psid
    )

    return Response(ProjectSubmissionSerializer(submission).data, status=status.HTTP_200_OK)


@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_project(request, psid):
    try:
        submission = ProjectSubmission.objects.get(psid=psid)
    except ProjectSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)
    if submission.file:
        submission.file.delete(save=False)
    submission.delete()
    return Response({"message": "Submission deleted successfully"}, status=status.HTTP_200_OK)


# --- Student-side: edit/delete own assignment (ownership-checked) ---

@api_view(['PUT', 'PATCH'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def student_update_assignment(request, asid):
    student_id = request.data.get('student_id')
    if not student_id:
        return Response({"error": "student_id is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        submission = AssignmentSubmission.objects.get(asid=asid)
    except AssignmentSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    if str(submission.student_id) != str(student_id):
        return Response({"error": "You can only edit your own submission"}, status=status.HTTP_403_FORBIDDEN)

    if 'file' in request.data and submission.file:
        submission.file.delete(save=False)

    serializer = AssignmentSubmissionSerializer(submission, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_200_OK)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['DELETE'])
@permission_classes([AllowAny])
def student_delete_assignment(request, asid):
    student_id = request.GET.get('student_id')
    if not student_id:
        return Response({"error": "student_id is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        submission = AssignmentSubmission.objects.get(asid=asid)
    except AssignmentSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    if str(submission.student_id) != str(student_id):
        return Response({"error": "You can only delete your own submission"}, status=status.HTTP_403_FORBIDDEN)

    if submission.file:
        submission.file.delete(save=False)
    submission.delete()
    return Response({"message": "Submission deleted successfully"}, status=status.HTTP_200_OK)


# --- Student-side: edit/delete own project (ownership-checked) ---

@api_view(['PUT', 'PATCH'])
@permission_classes([AllowAny])
@parser_classes([MultiPartParser, FormParser])
def student_update_project(request, psid):
    student_id = request.data.get('student_id')
    if not student_id:
        return Response({"error": "student_id is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        submission = ProjectSubmission.objects.get(psid=psid)
    except ProjectSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    if str(submission.student_id) != str(student_id):
        return Response({"error": "You can only edit your own submission"}, status=status.HTTP_403_FORBIDDEN)

    if 'file' in request.data and submission.file:
        submission.file.delete(save=False)

    serializer = ProjectSubmissionSerializer(submission, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_200_OK)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['DELETE'])
@permission_classes([AllowAny])
def student_delete_project(request, psid):
    student_id = request.GET.get('student_id')
    if not student_id:
        return Response({"error": "student_id is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        submission = ProjectSubmission.objects.get(psid=psid)
    except ProjectSubmission.DoesNotExist:
        return Response({"error": "Submission not found"}, status=status.HTTP_404_NOT_FOUND)

    if str(submission.student_id) != str(student_id):
        return Response({"error": "You can only delete your own submission"}, status=status.HTTP_403_FORBIDDEN)

    if submission.file:
        submission.file.delete(save=False)
    submission.delete()
    return Response({"message": "Submission deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def change_student_password(request, student_id):
    old_password = request.data.get('old_password')
    new_password = request.data.get('new_password')

    if not old_password or not new_password:
        return Response({"error": "Both current and new password are required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student = Student.objects.get(sid=student_id)
    except Student.DoesNotExist:
        return Response({"error": "Student not found"}, status=status.HTTP_404_NOT_FOUND)

    if not check_password(old_password, student.password):
        return Response({"error": "Current password is incorrect"}, status=status.HTTP_401_UNAUTHORIZED)

    if len(new_password) < 6:
        return Response({"error": "New password must be at least 6 characters"}, status=status.HTTP_400_BAD_REQUEST)

    student.password = make_password(new_password)
    student.save()
    return Response({"message": "Password changed successfully"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def forgot_password_teacher(request):
    email=request.data.get('email','').strip()
    if not email:
        return Response({"error": "Email is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher=Teacher.objects.get(email__iexact=email)
    except Teacher.DoesNotExist:
        return Response({"message": "If that email is registered, a reset code has been sent."}, status=status.HTTP_200_OK)

    otp=generate_otp()
    teacher.otp=otp
    teacher.otp_created_at=timezone.now()
    teacher.save()

    send_mail(
        subject='Reset your Click-digitals password',
        message=f'Your password reset code is: {otp}\nThis code expires in 10 minutes.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[teacher.email],
        fail_silently=False,
    )
    return Response({"message": "If that email is registered, a reset code has been sent."}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def reset_password_teacher(request):
    email=request.data.get('email','').strip()
    otp=request.data.get('otp')
    new_password=request.data.get('new_password')

    if not email or not otp or not new_password:
        return Response({"error": "Email, code, and new password are required"}, status=status.HTTP_400_BAD_REQUEST)

    if len(new_password)<6:
        return Response({"error": "New password must be at least 6 characters"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        teacher=Teacher.objects.get(email__iexact=email)
    except Teacher.DoesNotExist:
        return Response({"error": "Invalid code"}, status=status.HTTP_400_BAD_REQUEST)

    if not teacher.otp or teacher.otp !=otp:
        return Response({"error": "Invalid code"}, status=status.HTTP_400_BAD_REQUEST)
    if teacher.otp_created_at and timezone.now() > teacher.otp_created_at + timedelta(minutes=10):
        return Response({"error": "Code expired, please request a new one"}, status=status.HTTP_400_BAD_REQUEST)

    teacher.password=make_password(new_password)
    teacher.otp=None
    teacher.otp_created_at=None
    teacher.save()
    return Response({"message": "Password reset successfully!"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def forgot_password_student(request):
    email=request.data.get('email','').strip()
    if not email:
        return Response({"error": "Email is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student=Student.objects.get(email__iexact=email)
    except Student.DoesNotExist:
        return Response({"message": "If that email is registered, a reset code has been sent."}, status=status.HTTP_200_OK)

    otp=generate_otp()
    student.otp=otp
    student.otp_created_at=timezone.now()
    student.save()

    send_mail(
        subject='Reset your Click-digitals password',
        message=f'Your password reset code is: {otp}\nThis code expires in 10 minutes.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[student.email],
        fail_silently=False,
    )
    return Response({"message": "If that email is registered, a reset code has been sent."}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def reset_password_student(request):
    email=request.data.get('email','').strip()
    otp=request.data.get('otp')
    new_password=request.data.get('new_password')

    if not email or not otp or not new_password:
        return Response({"error": "Email, code, and new password are required"}, status=status.HTTP_400_BAD_REQUEST)

    if len(new_password)<6:
        return Response({"error": "New password must be at least 6 characters"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        student=Student.objects.get(email__iexact=email)
    except Student.DoesNotExist:
        return Response({"error": "Invalid code"}, status=status.HTTP_400_BAD_REQUEST)

    if not student.otp or student.otp !=otp:
        return Response({"error": "Invalid code"}, status=status.HTTP_400_BAD_REQUEST)
    if student.otp_created_at and timezone.now() > student.otp_created_at + timedelta(minutes=10):
        return Response({"error": "Code expired, please request a new one"}, status=status.HTTP_400_BAD_REQUEST)

    student.password=make_password(new_password)
    student.otp=None
    student.otp_created_at=None
    student.save()
    return Response({"message": "Password reset successfully!"}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def register_admin(request):
    serializer=AdminSideSerializer(data=request.data)

    if serializer.is_valid():
        hashed_pwd=make_password(request.data.get('password'))
        serializer.save(password=hashed_pwd)

        return Response(
            {"message":"User created successfully"},status=status.HTTP_201_CREATED
        )
    print(serializer.errors)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
def login_adminside(request):
    email = request.data.get('email')
    password = request.data.get('password')

    if not email or not password:
        return Response(
            {"error": "Email and password are required."}, 
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        admin = AdminSide.objects.get(email__iexact=email)
        
        if check_password(password, admin.password):
            # Manually instantiate RefreshToken to bypass default `id` check
            refresh = RefreshToken()
            
            # Embed primary key 'aid' and 'email' directly into token payload
            refresh['user_id'] = admin.aid
            refresh['email'] = admin.email

            return Response({
                "message": "Login successful!",
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
                "admin": {
                    "aid": admin.aid,
                    "fullname": admin.fullname,
                    "email": admin.email,
                }
            }, status=status.HTTP_200_OK)
        
        return Response({"error": "Invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)

    except AdminSide.DoesNotExist:
        return Response({"error": "Invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)

@api_view(['GET'])
@permission_classes([AllowAny])
def dashboard_stats(request):
    teacher_count=Teacher.objects.count()
    student_count=Student.objects.count()

    raw_subjects=Teacher.objects.exclude(subject__isnull=True).exclude(subject__exact='').values_list('subject',flat=True)
    normalized={s.strip().lower() for s in raw_subjects if s.strip()}
    course_count=len(normalized)

    return Response({
        "teacher_count":teacher_count,
        "student_count":student_count,
        "course_count":course_count
    },status=status.HTTP_200_OK)

def _last_n_months(n=6):
    today=timezone.now().date()
    year,month=today.year, today.month
    months=[]
    for _ in range(n):
        months.append((year, month))
        month-=1
        if month == 0:
            month=12
            year-= 1
    return list(reversed(months))

@api_view(['GET'])
@permission_classes([AllowAny])
def dashboard_charts(request):
    months=_last_n_months(6)

    #--Student enrollment trend--
    enrollment_qs=(
        Student.objects.annotate(month=TruncMonth('added_at')).values('month').annotate(count=Count('sid'))
        )
    enrollment_map={(m['month'].year,m['month'].month):m['count'] for m in enrollment_qs if m['month']}
    enrollment=[
        {'label':month_abbr[mo], "count":enrollment_map.get((yr,mo),0)} for yr,mo in months
    ]
    revenue_qs = (
        Bill.objects.filter(status='paid', paid_date__isnull=False)
        .annotate(month=TruncMonth('paid_date'))
        .values('month')
        .annotate(total=Sum('amount'))
    )
    revenue_map={(m['month'].year,m['month'].month):float(m['total']) for m in revenue_qs if m['month']}
    revenue = [
        {"label": month_abbr[mo], "count": revenue_map.get((yr, mo), 0)}
        for yr, mo in months
    ]
    attendance_by_month={}
    for a in Attendance.objects.all():
        key=(a.date.year, a.date.month)
        stats=attendance_by_month.setdefault(key,{'present': 0, 'total': 0})
        stats['total']+=1
        if a.status == 'present':
            stats['present']+= 1
    attendance=[]
    for yr,mo in months:
        stats = attendance_by_month.get((yr, mo))
        pct = round(stats['present'] / stats['total'] * 100, 1) if stats and stats['total'] else 0
        attendance.append({"label": month_abbr[mo], "count": pct})
        raw_subjects = Student.objects.exclude(subject__isnull=True).exclude(subject__exact='') \
                                   .values_list('subject', flat=True)
    counts = {}
    for s in raw_subjects:
        key = s.strip().lower()
        if key:
            counts[key] = counts.get(key, 0) + 1

    course_enrollment = [
        {"label": key.title(), "count": val}
        for key, val in sorted(counts.items(), key=lambda x: -x[1])
    ][:8]

    return Response({
        "enrollment": enrollment,
        "revenue": revenue,
        "attendance": attendance,
        "course_enrollment": course_enrollment,
    }, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def dashboard_activity(request):
    activities = []

    for s in Student.objects.order_by('-added_at')[:5]:
        activities.append({
            "id": f"student-{s.sid}",
            "color": "green",
            "text": f"New student registered — {s.username}",
            "timestamp": s.added_at.isoformat(),
        })

    for c in CourseContent.objects.exclude(content_type='announcement').order_by('-created_at')[:5]:
        teacher_name = c.teacher.username if c.teacher else "A teacher"
        activities.append({
            "id": f"content-{c.cid}",
            "color": "green",
            "text": f'{teacher_name} uploaded {c.content_type}: "{c.title}"',
            "timestamp": c.created_at.isoformat(),
        })

    for r in QuizResult.objects.select_related('quiz', 'student').order_by('-submitted_at')[:5]:
        activities.append({
            "id": f"quiz-{r.rid}",
            "color": "yellow",
            "text": f'{r.student.username} completed "{r.quiz.title}" ({r.score}/{r.total_questions})',
            "timestamp": r.submitted_at.isoformat(),
        })

    for a in CourseContent.objects.filter(content_type='announcement').order_by('-created_at')[:5]:
        activities.append({
            "id": f"announcement-{a.cid}",
            "color": "blue",
            "text": f'New announcement published: "{a.title}"',
            "timestamp": a.created_at.isoformat(),
        })

    activities.sort(key=lambda x: x['timestamp'], reverse=True)
    return Response(activities[:10], status=status.HTTP_200_OK)
     
@api_view(['GET'])       
@permission_classes([AllowAny])
def list_teachers(request):
    teachers=Teacher.objects.all().order_by('username').values('tid','username','email','address','subject','gender','phone', 'is_verified')
    return Response(list(teachers),status=status.HTTP_200_OK)

@api_view(['PUT','PATCH'])
@permission_classes([AllowAny])
def update_teacher(request,teacher_id):
    try:
        teacher=Teacher.objects.get(tid=teacher_id)
    except Teacher.DoesNotExist:
        return Response({"error": "Teacher not found"}, status=status.HTTP_404_NOT_FOUND)

    data=request.data.copy()
    data.pop('password',None)

    serializer=TeacherSerializer(teacher,data=data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(TeacherSerializer(teacher).data, status=status.HTTP_200_OK)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@permission_classes([AllowAny])
def delete_teacher(request,teacher_id):
    try:
        teacher=Teacher.objects.get(tid=teacher_id)
    except Teacher.DoesNotExist:
        return Response({"error": "Teacher not found"}, status=status.HTTP_404_NOT_FOUND)

    teacher.delete()
    return Response({"message": "Teacher deleted successfully"}, status=status.HTTP_200_OK)

@api_view(['GET'])       
@permission_classes([AllowAny])
def list_students_all(request):
    student=Student.objects.select_related('teacher').all().order_by('username').values(
        'sid', 'username', 'email', 'address', 'subject', 'phone',
        'level', 'is_verified', 'teacher__tid', 'teacher__username'
    )
    return Response(list(student),status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_attendance(request):
    teacher_name=request.query_params.get('teacher','').strip()

    records=Attendance.objects.select_related('student','teacher').all()
    if teacher_name:
        records = records.filter(teacher__username__icontains=teacher_name)
        
    records = records.order_by('-date').values(
        'aid', 'date', 'status', 'remarks',
        'student__sid', 'student__username',
        'teacher__tid', 'teacher__username',
    )
    return Response(list(records), status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_bills(request):
    status_filter = request.query_params.get('status', '').strip()
    bills = Bill.objects.select_related('student', 'teacher').all()

    if status_filter:
        bills = bills.filter(status=status_filter)

    bills = bills.order_by('-created_at').values(
        'bid', 'title', 'amount', 'due_date', 'remarks', 'status',
        'payment_method', 'transaction_code', 'transaction_uuid',
        'payment_screenshot', 'paid_date', 'created_at',
        'student__sid', 'student__username',
        'teacher__tid', 'teacher__username',
    )

    bills_list = list(bills)
    for b in bills_list:
        if b['payment_screenshot']:
            b['payment_screenshot'] = request.build_absolute_uri(
                settings.MEDIA_URL + str(b['payment_screenshot'])
            )
    return Response(bills_list, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_timetables(request):
    teacher_name = request.query_params.get('teacher', '').strip()

    contents = CourseContent.objects.select_related('teacher').filter(content_type='time table')

    if teacher_name:
        contents = contents.filter(teacher__username__icontains=teacher_name)

    contents = contents.order_by('-created_at').values(
        'cid', 'title', 'file', 'video_link', 'level',
        'description', 'created_at',
        'teacher__tid', 'teacher__username',
    )

    contents_list = list(contents)
    for c in contents_list:
        if c['file']:
            c['file'] = request.build_absolute_uri(
                settings.MEDIA_URL + str(c['file'])
            )
    return Response(contents_list, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_certificate(request):
    teacher_name=request.query_params.get('teacher','').strip()

    contents=CourseContent.objects.select_related('teacher').filter(content_type='certificate')

    if teacher_name:
        contents=contents.order_by('-created_at').values('cid', 'title', 'file', 'video_link', 'level',
        'description', 'created_at',
        'teacher__tid', 'teacher__username',
        )
    contents_list=list(contents)
    for c in contents_list:
        if c['file']:
            c['file']=request.build_absolute_uri(
                settings.MEDIA_URL + str(c['file'])
            )
    return Response(contents_list, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def list_announcement(request):
    teacher_name=request.query_params.get('teacher','').strip()

    contents=CourseContent.objects.select_related('teacher').filter(content_type='anouncement')

    if teacher_name:
        contents=contents.order_by('-created_at').values('cid', 'title', 'file', 'video_link', 'level',
        'description', 'created_at',
        'teacher__tid', 'teacher__username',
        )
    contents_list=list(contents)
    for c in contents_list:
        if c['file']:
            c['file']=request.build_absolute_uri(
                settings.MEDIA_URL + str(c['file'])
            )
    return Response(contents_list, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def admin_notifications(request):
    notifications = Notification.objects.filter(recipient='admin').order_by('-created_at')[:50]
    serializer = NotificationSerializer(notifications, many=True)
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(['PATCH'])
@permission_classes([AllowAny])
def mark_all_read_admin(request):
    Notification.objects.filter(recipient='admin', is_read=False).update(is_read=True)
    return Response({'status': 'all marked read'}, status=status.HTTP_200_OK)

