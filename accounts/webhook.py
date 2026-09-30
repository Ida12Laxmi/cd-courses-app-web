
import hashlib
import hmac
import json

from django.conf import settings
from django.http import HttpResponse, HttpResponseBadRequest, JsonResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
import os
from django.core.exceptions import ImproperlyConfigured

from .models import MeetingAttendance, ScheduledMeeting  # adjust import path



def _secret_token() -> str:
    token = getattr(settings, "ZOOM_WEBHOOK_SECRET_TOKEN", "") or os.getenv("ZOOM_WEBHOOK_SECRET_TOKEN", "")
    if not token:
        raise ImproperlyConfigured("ZOOM_WEBHOOK_SECRET_TOKEN is not set")
    return token

def _hmac_hex(message: str) -> str:
    return hmac.new(
        _secret_token().encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _signature_is_valid(request) -> bool:
    """Zoom signs each event: v0=HMAC_SHA256("v0:{timestamp}:{raw body}")."""
    timestamp = request.headers.get("x-zm-request-timestamp", "")
    signature = request.headers.get("x-zm-signature", "")
    body = request.body.decode("utf-8")
    expected = "v0=" + _hmac_hex(f"v0:{timestamp}:{body}")
    return hmac.compare_digest(expected, signature)


def _match_user(scheduled, email):
    """Return (teacher, student) by comparing the participant email to the scheduled pair."""
    if not scheduled or not email:
        return None, None
    email = email.strip().lower()
    if (getattr(scheduled.teacher, "email", "") or "").lower() == email:
        return scheduled.teacher, None
    if (getattr(scheduled.student, "email", "") or "").lower() == email:
        return None, scheduled.student
    return None, None


def _handle_joined(obj):
    participant = obj.get("participant", {})
    meeting_id = str(obj.get("id", ""))
    uuid = participant.get("participant_uuid") or participant.get("user_id") or ""
    email = participant.get("email")

    scheduled = ScheduledMeeting.objects.filter(meeting_id=meeting_id).first()
    teacher, student = _match_user(scheduled, email)

    MeetingAttendance.objects.create(
        meeting_id=meeting_id,
        participant_uuid=uuid,
        participant_name=participant.get("user_name", ""),
        participant_email=email or None,
        joined_at=parse_datetime(participant.get("join_time", "")) or timezone.now(),
        teacher=teacher,
        student=student,
    )


def _handle_left(obj):
    participant = obj.get("participant", {})
    meeting_id = str(obj.get("id", ""))
    uuid = participant.get("participant_uuid") or participant.get("user_id") or ""

    # Close the most recent open row (handles people who rejoin).
    row = (
        MeetingAttendance.objects.filter(
            meeting_id=meeting_id, participant_uuid=uuid, left_at__isnull=True
        )
        .order_by("-joined_at")
        .first()
    )
    if row:
        row.left_at = parse_datetime(participant.get("leave_time", "")) or timezone.now()
        row.save(update_fields=["left_at"])


@csrf_exempt
@require_POST
def zoom_webhook(request):
    try:
        payload = json.loads(request.body)
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")

    event = payload.get("event")

    # 1) One-time URL validation challenge when you save the endpoint in Marketplace.
    if event == "endpoint.url_validation":
        plain_token = payload["payload"]["plainToken"]
        return JsonResponse(
            {"plainToken": plain_token, "encryptedToken": _hmac_hex(plain_token)}
        )

    # 2) Every real event must carry a valid signature.
    if not _signature_is_valid(request):
        return HttpResponse(status=401)

    obj = payload.get("payload", {}).get("object", {})
    if event == "meeting.participant_joined":
        _handle_joined(obj)
    elif event == "meeting.participant_left":
        _handle_left(obj)

    return HttpResponse(status=200)