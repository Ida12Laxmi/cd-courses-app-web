from django.db import models
from django.utils import timezone


class Teacher(models.Model):
  tid = models.AutoField(primary_key=True, db_column='tid')
  username = models.CharField(max_length=100, db_column='aname',default='')
  email = models.EmailField(unique=True, db_column='aemail',default='')
  address = models.CharField(max_length=255, db_column='address',default='')
  subject = models.CharField(max_length=100, db_column='subject',default='')
  gender = models.CharField(max_length=10, blank=True, null=True,default='')
  phone = models.CharField(max_length=20, db_column='phone',default='')
  password = models.CharField(max_length=100, db_column='password',default='')
  is_verified = models.BooleanField(default=False)
  otp = models.CharField(max_length=6, null=True, blank=True)
  otp_created_at = models.DateTimeField(null=True, blank=True)

  class Meta:
        db_table = 'teacher'

  def __str__(self):
        return self.username
  
class Student(models.Model):
  LEVEL_CHOICES=[
      ('Basic','Basic'),
      ('Intermediate','Intermediate'),
      ('Advance','Advance'),
  ]
  sid = models.AutoField(primary_key=True, db_column='sid')
  username = models.CharField(max_length=100, db_column='sname',default='')
  email = models.EmailField(unique=True, db_column='semail',default='')
  address = models.CharField(max_length=255, db_column='address',default='')
  subject = models.CharField(max_length=100, db_column='subject',default='')
  phone = models.CharField(max_length=20, db_column='phone',default='')
  level = models.CharField(max_length=20, choices=LEVEL_CHOICES, default='Basic')
  password = models.CharField(max_length=100, db_column='password',default='')
  teacher = models.ForeignKey(
        Teacher,
        on_delete=models.CASCADE,
        db_column='tid',
        related_name='students',
        null=True,
        blank=True
    )
  is_verified = models.BooleanField(default=False)
  otp = models.CharField(max_length=6, null=True, blank=True)
  otp_created_at = models.DateTimeField(null=True, blank=True)
  added_at = models.DateTimeField(default=timezone.now)

  class Meta:
        db_table = 'student'

  def __str__(self):
        return self.username

class CourseContent(models.Model):
     CONTENT_TYPES=(
          ('syllabus','Syllabus'),
          ('notes','Notes'),
          ('video','Video'),
          ('assignment','Assignment'),
          ('quiz','Quiz'),
          ('project','Project'),
          ('announcement','Announcement'),
          ('result','Result'),
          ('certificate','Certificate'),
          ('reference','Reference'),
          ('attendance','Attendance'),
          ('leave and delays', 'Leave and Delays'),
          ('messages','Messages'),
          ('time table','Time Table'),
          ('student councelling','Student Councelling'),
          ('billing','Billing'),
          
     )
     cid=models.AutoField(primary_key=True, db_column='cid')
     teacher = models.ForeignKey(
        Teacher,
        on_delete=models.CASCADE,
        db_column='tid',
        related_name='contents',
        null=True,
        blank=True
    ) 
     content_type=models.CharField(max_length=20,choices=CONTENT_TYPES)
     title=models.CharField(max_length=200)
     file=models.FileField(upload_to='course_content/', null=True, blank=True)
     video_link=models.URLField(max_length=500,null=True, blank=True)
     description=models.TextField(blank=True, default='')
     created_at=models.DateTimeField(auto_now_add=True)

     class Meta:
          db_table='course_content'
      
     def __str__(self):
        return f"{self.content_type} - {self.title}"  
     
class Quiz(models.Model):
     quid=models.AutoField(primary_key=True)
     teacher= models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='quizzes')
     title = models.CharField(max_length=200)
     description = models.TextField(blank=True)
     created_at = models.DateTimeField(auto_now_add=True)

     def __str__(self):
        return self.title
     
class Question(models.Model):
    OPTION_CHOICES=[('A','A'),('B','B'),('C','C'),('D','D')]

    qsid=models.AutoField(primary_key=True)
    quiz=models.ForeignKey(Quiz,on_delete=models.CASCADE, related_name='questions')
    question_text=models.TextField()
    option_a = models.CharField(max_length=255)
    option_b = models.CharField(max_length=255)
    option_c = models.CharField(max_length=255)
    option_d = models.CharField(max_length=255)
    correct_option = models.CharField(max_length=1, choices=OPTION_CHOICES)

    def __str__(self):
        return self.question_text[:50]
    
class QuizResult(models.Model):
    rid=models.AutoField(primary_key=True)
    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='results')
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='quiz_results')
    score = models.IntegerField()
    total_questions = models.IntegerField()
    submitted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('quiz', 'student') 

class StudentAnswer(models.Model):
    result = models.ForeignKey(QuizResult, on_delete=models.CASCADE, related_name='answers')
    question = models.ForeignKey(Question, on_delete=models.CASCADE)
    selected_option = models.CharField(max_length=1)
    is_correct = models.BooleanField()

class AssignmentSubmission(models.Model):
    asid = models.AutoField(primary_key=True)
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='assignment_submissions')
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='assignment_submissions')
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    file = models.FileField(upload_to='assignment_submissions/', null=True, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    teacher_feedback = models.TextField(null=True, blank=True) 

class ProjectSubmission(models.Model):
    psid = models.AutoField(primary_key=True)
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='project_submissions')
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='project_submissions')
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    file = models.FileField(upload_to='project_submissions/', null=True, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)

class Conversation(models.Model):
    convid=models.AutoField(primary_key=True)
    teacher=models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='conversations')
    student=models.ForeignKey(Student, on_delete=models.CASCADE, related_name='conversations')
    topic=models.CharField(max_length=250, default='messages')
    created_at=models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together=('teacher','student','topic')

class Message(models.Model):
    message_id=models.AutoField(primary_key=True)
    conversation=models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='messages')
    sender_type=models.CharField(max_length=10, choices=[('teacher', 'Teacher'), ('student', 'Student')])
    text=models.TextField(blank=True)
    attachment=models.FileField(upload_to='chat_attachments/', null=True, blank=True)
    created_at=models.DateTimeField(auto_now_add=True)

class MessageReaction(models.Model):
    reaction_id=models.AutoField(primary_key=True)
    message=models.ForeignKey(Message, on_delete=models.CASCADE, related_name='reactions')
    user_type=models.CharField(max_length=10, choices=[('teacher', 'Teacher'), ('student', 'Student')])
    emoji = models.CharField(max_length=10)

    class Meta:
        unique_together = ('message', 'user_type')

class Attendance(models.Model):
    STATUS_CHOICES = [('present', 'Present'), ('absent', 'Absent'), ('late', 'Late')]

    aid = models.AutoField(primary_key=True)
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='attendance_records')
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='attendance_records')
    date = models.DateField()
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='present')
    remarks = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('student', 'date')
