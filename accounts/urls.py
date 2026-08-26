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
    path('resend-student-otp/', views.resend_student_otp, name='resend-student-otp' ),
    path('students/login/', views.login_student, name='student_login'),
    path('students/<int:student_id>/assignments/',views.get_assignment_student, name='get_assignment_student'),
    path('students/<int:student_id>/projects/',views.get_project_student, name='get_project_student'),
    path('students/<int:student_id>/content/<str:content_type>/', views.student_list_content, name='student_list_content'),
    path('content/<int:cid>/stream/', views.stream_content, name='stream_content'),
    path('students/<int:student_id>/assignments/submit/', views.submit_assignment, name='submit_assignment'),
    path('students/<int:student_id>/projects/submit/', views.submit_project, name='submit_project'),
    #path('students/check-verification/', views.check_student_verification, name='check_student_verification'),
    
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

    #bills
    path('bills/student/<int:student_id>/', views.bills_by_student, name='bills_by_student'),
    path('bills/create/', views.create_bill,name='create_bill'),
    path('bills/cash-paid/<int:bill_id>/', views.mark_cash_paid,name='mark_cash_paid'),
    path('bills/submit-proof/<int:bill_id>/', views.submit_payment_proof,name='submit_payment_proof'),
    path('bills/verify/<int:bill_id>/', views.verify_payment,name='verify_payment'),
    path('bills/delete/<int:bill_id>/', views.delete_bill,name='delete_bill'),
    path('teacher/payment-qr/<int:teacher_id>/', views.get_teacher_qr,name='get_teacher_qr'),
    path('teacher/payment-qr/upload/<int:teacher_id>/', views.upload_teacher_qr,name='upload_teacher_qr'),
    
    path('bills/teacher/<int:teacher_id>/', views.bills_by_teacher,name='bills_by_teacher'),
    
    path('bills/update/<int:bill_id>/', views.update_bill,name='update_bill'),

    path('teacher/change-password/<int:teacher_id>/', views.change_teacher_password, name='change_teacher_password'),

    #notifications

    path('notifications/teacher/<int:teacher_id>/', views.teacher_notifications, name='teacher_notifications'),
    path('notifications/read/<int:notif_id>/', views.mark_notification_as_read, name='mark_notification_as_read'),
    path('notifications/read-all/<int:teacher_id>/', views.mark_all_read, name='mark_all_read'),
    path('notifications/read-all/student/<int:student_id>/', views.mark_all_read_student, name='mark_all_read_student'),
   
    path('notifications/delete/<int:notif_id>/', views.delete_notification, name='delete_notification'),

    path('students/<int:student_id>/assignments/submit/', views.submit_assignment, name='submit_assignment'),
    path('students/<int:student_id>/projects/submit/', views.submit_project, name='submit_project'),

    #firebase
    path('devices/register-token/', views.register_device_token, name='register_device_token'),

    #notifications for students
   # path('students/<int:student_id>/notifications/', views.student_notifications, name='student_notifications'),
   path('notifications/student/<int:student_id>/', views.student_notifications, name='student_notifications'),

   path('students/<int:student_id>/search/', views.student_search_content, name='student-search-content'),

   path('teacher/<int:teacher_id>/search/', views.teacher_search_content, name='teacher_search_content'),

   path('students/assignments/update/<int:asid>/', views.student_update_assignment,name='student_update_assignment'),
   path('students/assignments/delete/<int:asid>/', views.student_delete_assignment,name='student_delete_assignment'),

   path('students/projects/update/<int:psid>/', views.student_update_project,name='student_update_project'),
   path('students/projects/delete/<int:psid>/', views.student_delete_project,name='student_delete_project'),

   path('assignments/feedback/<int:asid>/', views.assignment_feedback,name='assignment_feedback'),
   path('assignments/delete/<int:asid>/', views.delete_assignment,name='delete_assignment'),

   path('projects/feedback/<int:psid>/', views.project_feedback,name='project_feedback'),
   path('projects/delete/<int:psid>/', views.delete_project,name='delete_project'),


#searchofsubmissions
   path('students/<int:student_id>/<str:content_type>/search/', views.student_search_submissions, name='student_search_submissions'),

   path('student/change-password/<int:student_id>/', views.change_student_password, name='change_student_password'),

   #reset password of teacher and student
   path('forgot-password/', views.forgot_password_teacher, name='forgot_password_teacher'),
   path('reset-password/', views.reset_password_teacher, name='reset_password_teacher'),
   path('students/forgot-password/', views.forgot_password_student, name='forgot_password_student'),
   path('students/reset-password/', views.reset_password_student, name='reset_password_student'),

   #register-admin
   path('register_admin/',views.register_admin, name='register_admin'),
   path('login_adminside/',views.login_adminside,name='login_adminside'),

   #count
   # accounts/urls.py
   path('dashboard_stats/', views.dashboard_stats, name='dashboard_stats'),

   path('dashboard_charts/', views.dashboard_charts, name='dashboard_charts'),
   path('dashboard_activity/', views.dashboard_activity, name='dashboard_activity'),

   path('list_teachers/',views.list_teachers,name='list_teachers'),
   path('update_teacher/<int:teacher_id>/',views.update_teacher, name='update_teacher'),
   path('delete_teacher/<int:teacher_id>/',views.delete_teacher,name='delete_teacher'),

   path('list_students/',views.list_students_all,name='list_students_all'),

   path('list_attendance/',views.list_attendance,name='list_attendance'),

   path('list_bills/',views.list_bills,name='list_bills'),

   path('list_timetables/',views.list_timetables,name='list_timetables'),

   path('list_certificate/', views.list_certificate,name='list_certificate'),

   path('list_announcement/',views.list_announcement,name='list_announcement'),

   path('admin_notifications/', views.admin_notifications, name='admin_notifications'),
   path('mark_all_read_admin/', views.mark_all_read_admin, name='mark_all_read_admin'),

]
