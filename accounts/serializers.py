from rest_framework import serializers
from .models import Teacher,Student,CourseContent,Quiz, Question, QuizResult,StudentAnswer, AssignmentSubmission, ProjectSubmission, Conversation, Message, MessageReaction, Attendance

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
        fields=['cid','teacher','content_type','title','file','video_link','description','created_at']

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
        fields = ['quid', 'teacher', 'title', 'description', 'created_at', 'questions']

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
    class Meta:
        model=QuizResult
        fields = ['rid', 'quiz', 'student', 'score', 'total_questions', 'submitted_at', 'answers']

class AssignmentSubmissionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AssignmentSubmission
        fields = ['asid', 'student', 'teacher', 'title', 'description', 'file', 'submitted_at', 'teacher_feedback']


class ProjectSubmissionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProjectSubmission
        fields = ['psid', 'student', 'teacher', 'title', 'description', 'file', 'submitted_at']

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


