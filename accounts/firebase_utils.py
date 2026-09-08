# accounts/firebase_utils.py (new file)
import firebase_admin
from firebase_admin import credentials, messaging
import os

from accounts.models import DeviceToken

if not firebase_admin._apps:
    cred = credentials.Certificate(os.path.join(os.path.dirname(__file__), '..', 'firebase-service-account.json'))
    firebase_admin.initialize_app(cred)

def send_push_to_user(role, user_id, title, body):
    tokens = list(DeviceToken.objects.filter(role=role, user_id=user_id).values_list('device_token', flat=True))
    if not tokens:
        return
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        tokens=tokens,
        android=messaging.AndroidConfig(
            notification=messaging.AndroidNotification(
                icon='ic_stat_notify',       # matches drawable-*/ic_stat_notify.png
                color='#013768',             # tint applied to the white silhouette
            )
        ),
    )
    try:
        messaging.send_each_for_multicast(message)
    except Exception as e:
        print(f'FCM send failed: {e}')

def notify_student(student, notify_type, title, message, related_id=None):
    from accounts.models import Notification
    Notification.objects.create(
        teacher_id=student.teacher_id,
        student_id=student.sid,
        recipient='student',
        notif_type=notify_type,
        title=title,
        message=message,
        related_id=related_id,
    )
    send_push_to_user(role='student', user_id=student.sid, title=title, body=message)

def notify_teacher(teacher, notify_type, title, message, related_id=None):
    from accounts.models import Notification
    Notification.objects.create(
        teacher_id=teacher.tid,
        student_id=None,
        recipient='teacher',
        notif_type=notify_type,
        title=title,
        message=message,
        related_id=related_id,
    )
    send_push_to_user(role='teacher', user_id=teacher.tid, title=title, body=message)