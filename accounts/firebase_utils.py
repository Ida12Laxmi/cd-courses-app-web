# accounts/firebase_utils.py
import firebase_admin
from firebase_admin import credentials, messaging
import os

from accounts.models import DeviceToken

if not firebase_admin._apps:
    cred = credentials.Certificate(os.path.join(os.path.dirname(__file__), '..', 'firebase-service-account.json'))
    firebase_admin.initialize_app(cred)


def _is_dead_token_error(exception) -> bool:
    """
    True if this error means the token will NEVER work again (app
    uninstalled, token expired/rotated, malformed token) — safe to
    delete. False for transient errors (quota, network, etc.) which
    should just be retried later, not treated as dead.
    """
    if isinstance(exception, messaging.UnregisteredError):
        return True
    from firebase_admin.exceptions import InvalidArgumentError
    if isinstance(exception, InvalidArgumentError):
        return True
    return False


def send_push_to_user(role, user_id, title, body):
    tokens = list(DeviceToken.objects.filter(role=role, user_id=user_id).values_list('device_token', flat=True))
    if not tokens:
        return

    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        tokens=tokens,
        android=messaging.AndroidConfig(
            priority='high',
            notification=messaging.AndroidNotification(
                icon='ic_stat_notify',
                color='#013768',
                channel_id='high_importance_channel',
            ),
        ),
        apns=messaging.APNSConfig(
            headers={'apns-priority': '10'},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=title, body=body),
                    sound='default',
                    content_available=True,
                ),
            ),
        ),
    )

    try:
        response = messaging.send_each_for_multicast(message)
        if response.failure_count:
            dead_tokens = []
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    print(f'FCM token failed ({tokens[idx][:12]}...): {resp.exception!r}')
                    if _is_dead_token_error(resp.exception):
                        dead_tokens.append(tokens[idx])

            if dead_tokens:
                deleted_count, _ = DeviceToken.objects.filter(device_token__in=dead_tokens).delete()
                print(f'Removed {deleted_count} dead device token(s) for role={role}, user_id={user_id}')
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