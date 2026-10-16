import logging
import time

import firebase_admin
from django.conf import settings
from firebase_admin import credentials, messaging

from .models import DeviceToken, Notification, Student

log = logging.getLogger(__name__)


_last_sent = {}
COOLDOWN_SECONDS = 120


def _ensure_firebase():
    if firebase_admin._apps:
        return True
    try:
        path = getattr(settings, "FIREBASE_CREDENTIALS_PATH", None)
        if path:
            firebase_admin.initialize_app(credentials.Certificate(path))
        else:
            firebase_admin.initialize_app()  # uses GOOGLE_APPLICATION_CREDENTIALS
        return True
    except Exception as e:
        log.warning("Firebase is not configured, no push sent: %s", e)
        return False


def _send_push(tokens, title, body, data):
    if not tokens or not _ensure_firebase():
        return 0

    msg = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=data,
        android=messaging.AndroidConfig(priority="high"),
    )
    resp = messaging.send_each_for_multicast(msg)

    # forget tokens of phones where the app was uninstalled
    dead = [
        t for t, r in zip(tokens, resp.responses)
        if not r.success and isinstance(r.exception, messaging.UnregisteredError)
    ]
    if dead:
        DeviceToken.objects.filter(device_token__in=dead).delete()

    return resp.success_count


def notify_group_call(teacher_id, teacher_name, skip_student_ids=(), subject=""):
    """Synchronous. Call it through database_sync_to_async / a thread.

    subject = ""      -> invite all of the teacher's students
    subject = "Math"  -> invite only students whose subject is Math (case-insensitive)

    Returns {"invited": <students notified>, "pushed": <phone pushes delivered>,
             "cooldown": <True if skipped because an identical invite was just sent>}
    """
    subject = (subject or "").strip()

    key = (teacher_id, subject.lower())
    now = time.time()
    if now - _last_sent.get(key, 0) < COOLDOWN_SECONDS:
        return {"invited": 0, "pushed": 0, "cooldown": True}
    _last_sent[key] = now

    qs = Student.objects.filter(teacher_id=teacher_id).exclude(pk__in=list(skip_student_ids))
    if subject:
        qs = qs.filter(subject__iexact=subject)
    students = list(qs)
    if not students:
        return {"invited": 0, "pushed": 0, "cooldown": False}

    subject_text = f" ({subject})" if subject else ""
    title = f"Class Room is live{subject_text}"
    body = (
        f"{teacher_name or 'Your teacher'} has started the "
        f"{subject + ' ' if subject else ''}class room. Tap to join."
    )

    # 1) shows up in the student's notification list
    Notification.objects.bulk_create([
        Notification(
            teacher_id=teacher_id,
            student=s,
            recipient="student",
            notif_type="group_call",
            title=title,
            message=body,
            related_id=teacher_id,
        )
        for s in students
    ])

    # 2) phone push
    tokens = list(
        DeviceToken.objects.filter(role="student", user_id__in=[s.sid for s in students])
        .values_list("device_token", flat=True)
    )
    pushed = _send_push(
        tokens, title, body,
        {"type": "group_call", "teacher_id": str(teacher_id), "subject": subject},
    )
    return {"invited": len(students), "pushed": pushed, "cooldown": False}