from django.urls import path 
from . import views

urlpatterns = [
    path('teachers/',views.register_teacher, name='register_teacher'),
    path('verify-otp/', views.verify_otp, name='verify_otp'),
    path('resend-otp/', views.resend_otp, name='resend_otp'),
    path('login/',views.login_admin,name='login_teacher'),
    #students
    path('students/', views.register_student, name='add_student'),
    path('students/teacher/<int:teacher_id>/', views.list_students, name='list_students'),
    path('students/update/<int:student_id>/', views.update_students, name='update_student'),
    path('students/delete/<int:student_id>/', views.delete_student, name='delete_student'),
    path('verify-student-otp/', views.verify_student_otp, name='verify-student-otp'),
    path('resend-student-otp/', views.resend_student_otp, name='resned-student-otp' ),
    path('students/<int:student_id>/assignments/',views.get_assignment_student, name='get_assignment_student'),
    path('students/<int:student_id>/projects/',views.get_project_student, name='get_project_student'),
    
    #content
    path('content/upload/', views.upload_content, name='upload_content'),
    path('content/<int:teacher_id>/<str:content_type>/', views.list_content, name='list_content'),
    path('content/update/<int:pk>/', views.update_content, name='update_content'),
    path('content/delete/<int:pk>/', views.delete_content, name='delete_content'),
    #quiz
    path('quiz/create/', views.create_quiz, name='create_quiz'),
    path('quiz/<int:quiz_id>/add-question/', views.add_question, name='add_question'),
    path('quiz/teacher/<int:teacher_id>/', views.list_teacher_quizzes, name='list_teacher_quizzes'),
    path('quiz/<int:quiz_id>/results/', views.quiz_results, name='quiz_results'),
    path('quiz/<int:quiz_id>/take/', views.get_quiz_for_student, name='get_quiz_for_student'),
    path('quiz/<int:quiz_id>/submit/', views.submit_quiz, name='submit_quiz'),
    path('quiz/<int:quiz_id>/', views.get_quiz_detail, name='get_quiz_detail'),
    path('quiz/update/<int:quiz_id>/', views.update_quiz, name='update_quiz'),
    path('quiz/delete/<int:quiz_id>/', views.delete_quiz, name='delete_quiz'),
    path('quiz/question/update/<int:question_id>/', views.update_question, name='update_question'),
    path('quiz/question/delete/<int:question_id>/', views.delete_question, name='delete_question'),

    #chat
    path('conversations/get-or-create/', views.get_or_create_conversation, name='get_or_create_conversation'),
    path('messages/send/',views.send_message, name='send_message'),
    path('messages/react/', views.toggle_reaction, name='toggle_reaction'),
    path('messages/edit/<int:message_id>/', views.edit_message, name='edit_message'),
    path('messages/delete/<int:message_id>/', views.delete_message, name='delete_message'),

    #attendance
    path('attendance/<int:teacher_id>/', views.get_attendance_for_date, name='get_attendance_for_date'),
    path('attendance/save/', views.save_attendance, name='save_attendance'),
    path('attendance/student/<int:student_id>/', views.get_student_attendance_history, name='get_student_attendance_history'),
    path('attendance/dates/<int:teacher_id>/', views.get_attendance_dates, name='get_attendance_dates'),
    path('teacher/<int:teacher_id>/students-report/', views.get_teacher_students_report, name='teacher-students-report'),
]