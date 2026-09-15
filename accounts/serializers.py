from rest_framework import serializers
from .models import Teacher,Student,CourseContent,Quiz, Question, QuizResult,StudentAnswer, AssignmentSubmission, ProjectSubmission, Conversation, Message, MessageReaction, Attendance, Bill, TeacherPaymentQr, Notification,AdminSide

class TeacherSerializer(serializers.ModelSerializer):
    class Meta:
        model=Teacher
        fields=['tid','username','email','address','subject','gender','phone','password']

    extra_kwargs={
        'password':{
            'write-only':True
        }
    }

class StudentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Student
        fields = ['sid', 'username', 'email', 'address', 'subject', 'phone', 'level',
                  'password', 'teacher', 'is_verified', 'otp', 'otp_created_at', 'added_at']
    
class ContentSerializer(serializers.ModelSerializer):

    class Meta:
        model=CourseContent
        fields=['cid','teacher','content_type','title','file','video_link','level','description','created_at']

class QuestionSerializer(serializers.ModelSerializer):
    class Meta:
        model=Question
        fields=['qsid', 'quiz', 'question_text', 'option_a', 'option_b', 'option_c', 'option_d', 'correct_option']

class QuestionPublicSerializer(serializers.ModelSerializer):
    class Meta:
        model=Question
        fields = ['qsid', 'question_text', 'option_a', 'option_b', 'option_c', 'option_d']

class QuizSerializer(serializers.ModelSerializer):
    questions = QuestionSerializer(many=True, read_only=True)

    class Meta:
        model=Quiz
        fields = ['quid', 'teacher', 'title', 'level', 'description', 'created_at', 'questions']

class QuizPublicSerializer(serializers.ModelSerializer):
    questions = QuestionPublicSerializer(many=True, read_only=True)

    class Meta:
        model=Quiz
        fields = ['quid', 'title', 'description', 'questions']

class StudentAnswerSerializer(serializers.ModelSerializer):
    class Meta:
        model = StudentAnswer
        fields = ['question', 'selected_option', 'is_correct']

class QuizResultSerializer(serializers.ModelSerializer):
    answers = StudentAnswerSerializer(many=True, read_only=True)
    student_name = serializers.SerializerMethodField()
    class Meta:
        model=QuizResult
        fields = ['rid', 'quiz', 'student', 'student_name', 'score', 'total_questions', 'submitted_at', 'answers']
    def get_student_name(self, obj):
        return obj.student.username

class AssignmentSubmissionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AssignmentSubmission
        fields = ['asid', 'student', 'teacher', 'title', 'description', 'file', 'submitted_at', 'teacher_feedback']


class ProjectSubmissionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProjectSubmission
        fields = ['psid', 'student', 'teacher', 'title', 'description', 'file', 'submitted_at','teacher_feedback']

class ConversationSerializer(serializers.ModelSerializer):
    class Meta:
        model=Conversation
        fields=['convid','teacher','student','topic','created_at']

class ReactionSerializer(serializers.ModelSerializer):
    class Meta:
        model=MessageReaction
        fields = ['reaction_id', 'user_type', 'emoji']

class MessageSerializer(serializers.ModelSerializer):
    reactions = ReactionSerializer(many=True, read_only=True)

    class Meta:
        model=Message
        fields = ['message_id', 'conversation', 'sender_type', 'text', 'attachment', 'created_at', 'reactions']

class AttendanceSerializer(serializers.ModelSerializer):
    class Meta:
        model=Attendance
        fields = ['aid', 'student', 'teacher', 'date', 'status', 'remarks', 'created_at']

class BillWithStudentSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.username', read_only=True)
    class Meta:
        model=Bill
        fields=['bid','student','teacher','title','amount','due_date','status','paid_date','payment_method','payment_screenshot','transaction_uuid','transaction_code','remarks','created_at']

class BillSerializer(serializers.ModelSerializer):
    class Meta:
        model=Bill
        fields=['bid','student','teacher','title','amount','due_date','status','paid_date','payment_method','payment_screenshot','transaction_uuid','transaction_code','remarks','created_at']

class TeacherPaymentQrSerializer(serializers.ModelSerializer):
    class Meta:
        model = TeacherPaymentQr
        fields = '__all__'

class NotificationSerializer(serializers.ModelSerializer):
    student_name=serializers.CharField(source='student.username', read_only=True)

    class Meta:
        model=Notification
        fields=['nid', 'teacher', 'student', 'recipient', 'notif_type', 'title', 'message', 'related_id', 'is_read', 'created_at', 'student_name']
        #fields = '__all__'

class AdminSideSerializer(serializers.ModelSerializer):
    #admin_name=serializers.CharField(source='admin.fullname', read_only=True)

    class Meta:
        model=AdminSide
        fields=['aid','fullname','email','phone','address','gender','password']