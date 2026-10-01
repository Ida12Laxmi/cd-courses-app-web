"""
accounts/zoommeeting.py

Teacher schedules + hosts a Zoom meeting; students added by the teacher join it.
Works the way the rest of your app does: the Flutter screens send teacher_id /
student_id (no login token on these calls).

Needs:  pip install requests
Settings: ZOOM_S2S_ACCOUNT_ID, ZOOM_S2S_CLIENT_ID, ZOOM_S2S_CLIENT_SECRET, ZOOM_HOST_EMAIL
"""
from datetime import timedelta, timezone as dt_tz

import requests
from django.conf import settings
from django.core.cache import cache
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from .firebase_utils import notify_student
from .models import ScheduledMeeting, Student, Teacher

MAX_MINUTES = 40  # Zoom Basic plan limit


def open_api(*methods):
    """Plain DRF view with no auth (same as your other id-based endpoints)."""
    def wrap(fn):
        fn = permission_classes([AllowAny])(fn)
        fn = authentication_classes([])(fn)
        return api_view(list(methods))(fn)
    return wrap


def _err(detail, code):
    return Response({"detail": detail}, status=code)

def _when_text(dt):
    return timezone.localtime(dt).strftime("%b %d, %I:%M %p")


def _teacher(teacher_id):
    try:
        return Teacher.objects.get(pk=int(teacher_id))
    except (TypeError, ValueError, Teacher.DoesNotExist):
        return None


def _student(student_id):
    try:
        return Student.objects.get(pk=int(student_id))
    except (TypeError, ValueError, Student.DoesNotExist):
        return None

def _overlapping_meeting(teacher, start, minutes, exclude_id=None):
    end = start + timedelta(minutes=minutes)
    candidates = ScheduledMeeting.objects.filter(
        teacher=teacher,
        start_time__lt=end,
        start_time__gt=start - timedelta(minutes=MAX_MINUTES),
    )
    if exclude_id is not None:
        candidates = candidates.exclude(pk=exclude_id)
    for existing in candidates:
        existing_end = existing.start_time + timedelta(minutes=existing.duration_minutes)
        if start < existing_end and end > existing.start_time:
            return existing
    return None

def _overlapping_meeting(teacher, start, minutes, exclude_id=None):
    end = start + timedelta(minutes=minutes)
    candidates = ScheduledMeeting.objects.filter(
        teacher=teacher,
        start_time__lt=end,
        start_time__gt=start - timedelta(minutes=MAX_MINUTES),
    )
    if exclude_id is not None:
        candidates = candidates.exclude(pk=exclude_id)
    for existing in candidates:
        existing_end = existing.start_time + timedelta(minutes=existing.duration_minutes)
        if start < existing_end and end > existing.start_time:
            return existing
    return None


# --- Zoom API helpers ---------------------------------------------------------
def _zoom_token():
    token = cache.get("zoom_s2s_token")
    if token:
        return token
    r = requests.post(
        "https://zoom.us/oauth/token",
        params={"grant_type": "account_credentials", "account_id": settings.ZOOM_S2S_ACCOUNT_ID},
        auth=(settings.ZOOM_S2S_CLIENT_ID, settings.ZOOM_S2S_CLIENT_SECRET),
        timeout=15,
    )
    r.raise_for_status()
    data = r.json()
    cache.set("zoom_s2s_token", data["access_token"], max(60, data.get("expires_in", 3600) - 120))
    return data["access_token"]


def _zoom(method, path, **kwargs):
    r = requests.request(
        method,
        f"https://api.zoom.us/v2{path}",
        headers={"Authorization": f"Bearer {_zoom_token()}"},
        timeout=20,
        **kwargs,
    )
    if not r.ok:
        raise requests.HTTPError(f"{r.status_code} {r.text}", response=r)
    return r.json() if r.content else {}


def _row(m):
    """Safe for teacher AND students: never includes start_url."""
    return {
        "id": m.id,
        "meeting_id": m.meeting_id,
        "passcode": m.passcode,
        "topic": m.topic,
        "description": m.description,
        "start_time": m.start_time.isoformat(),
        "duration_minutes": m.duration_minutes,
        "waiting_room": m.waiting_room,
        "host_video": m.host_video,
        "participant_video": m.participant_video,
        "student_ids": list(m.students.values_list("pk", flat=True)),
    }

def _notify_students(students, notify_type, title, message, related_id=None):
    """A failed notification must never break the schedule/update/delete call."""
    for s in students:
        try:
            notify_student(
                student=s,
                notify_type=notify_type,
                title=title,
                message=message,
                related_id=related_id,
            )
        except Exception as e:
            print(f"Zoom notification failed for student {s.pk}: {e}")

# --- Teacher endpoints --------------------------------------------------------
@open_api("GET")
def invitable_students(request, teacher_id):
    teacher = _teacher(teacher_id)
    if not teacher:
        return _err("Teacher not found", 404)
    # Student's primary key is `sid`, so always use pk (not id)
    students = Student.objects.filter(teacher=teacher)
    return Response(
        [{"id": s.pk, "name": getattr(s, "username", None) or str(s)} for s in students]
    )


@open_api("POST")
def schedule_meeting(request):
    d = request.data
    teacher = _teacher(d.get("teacher_id"))
    if not teacher:
        return _err("Teacher not found", 404)

    start = parse_datetime(str(d.get("start_time", "")))
    if start is None or timezone.is_naive(start):
        return _err("start_time must be an ISO datetime with timezone", 400)
    if start <= timezone.now():
        return _err("start_time must be in the future", 400)

    try:
        minutes = int(d.get("duration_minutes", 40))
    except (TypeError, ValueError):
        minutes = 0
    if not 1 <= minutes <= MAX_MINUTES:
        return _err(f"duration_minutes must be 1-{MAX_MINUTES}", 400)

    # Same teacher can't double-book overlapping times; different teachers can
    # freely share a slot (checked by scoping the query to `teacher=teacher`).
    clash = _overlapping_meeting(teacher, start, minutes)
    if clash:
        clash_end = clash.start_time + timedelta(minutes=clash.duration_minutes)
        return _err(
            f"You already have '{clash.topic}' from {clash.start_time.isoformat()} "
            f"to {clash_end.isoformat()}. Pick a different time.",
            409,
        )

    topic = (d.get("topic") or "").strip() or "Class"
    waiting_room = bool(d.get("waiting_room", False))
    students = Student.objects.filter(teacher=teacher, pk__in=d.get("student_ids") or [])

    host = getattr(settings, "ZOOM_HOST_EMAIL", "") or "me"
    try:
        z = _zoom(
            "POST",
            f"/users/{host}/meetings",
            json={
                "topic": topic,
                "type": 2,  # scheduled meeting
                "start_time": start.astimezone(dt_tz.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "duration": minutes,
                "agenda": (d.get("description") or "").strip(),
                "settings": {
                    "waiting_room": waiting_room,
                    "host_video": bool(d.get("host_video", False)),
                    "participant_video": bool(d.get("participant_video", False)),
                    "join_before_host": False,
                },
            },
        )
    except requests.RequestException as e:
        return _err(f"Zoom error: {e}", 502)

    meeting = ScheduledMeeting.objects.create(
        meeting_id=str(z["id"]),
        passcode=z.get("password", ""),
        topic=topic,
        description=(d.get("description") or "").strip(),       # NEW
        start_time=start,
        duration_minutes=minutes,
        waiting_room=waiting_room,
        host_video=bool(d.get("host_video", False)),             # NEW
        participant_video=bool(d.get("participant_video", False)),  # NEW
        start_url=z.get("start_url", ""),
        join_url=z.get("join_url", ""),
        teacher=teacher,
    )
    meeting.students.set(students)
    _notify_students(
        students,
        "class_scheduled",
        "New class scheduled",
        f'"{topic}" is scheduled for {_when_text(start)}.',
        meeting.id,
    )
    return Response(_row(meeting), status=201)


@open_api("GET")
def teacher_meetings(request, teacher_id):
    teacher = _teacher(teacher_id)
    if not teacher:
        return _err("Teacher not found", 404)
    return Response([_row(m) for m in ScheduledMeeting.objects.filter(teacher=teacher)])

"""
@open_api("POST")
def host_meeting(request, pk):
    Returns a fresh host link (start_url expires quickly, so we re-fetch it).
    teacher = _teacher(request.data.get("teacher_id"))
    if not teacher:
        return _err("Teacher not found", 404)
    meeting = get_object_or_404(ScheduledMeeting, pk=pk, teacher=teacher)
    try:
        z = _zoom("GET", f"/meetings/{meeting.meeting_id}")
    except requests.RequestException as e:
        return _err(f"Zoom error: {e}", 502)
    meeting.start_url = z.get("start_url", meeting.start_url)
    meeting.save(update_fields=["start_url"])
    return Response({"start_url": meeting.start_url})
"""

HOST_EARLY_MINUTES = 0 

@open_api("POST")
def host_meeting(request, pk):
    """Returns a fresh host link, only inside the meeting's time window."""
    teacher = _teacher(request.data.get("teacher_id"))
    if not teacher:
        return _err("Teacher not found", 404)
    meeting = get_object_or_404(ScheduledMeeting, pk=pk, teacher=teacher)

    now = timezone.now()
    opens_at = meeting.start_time - timedelta(minutes=HOST_EARLY_MINUTES)
    ends_at = meeting.start_time + timedelta(minutes=meeting.duration_minutes)

    if now > ends_at:
        return _err("Time passed. This meeting has already ended.", 400)
    if now < opens_at:
        return _err(
            f"Not started yet. You can host this meeting from {_when_text(opens_at)}.",
            400,
        )

    try:
        z = _zoom("GET", f"/meetings/{meeting.meeting_id}")
    except requests.RequestException as e:
        return _err(f"Zoom error: {e}", 502)
    meeting.start_url = z.get("start_url", meeting.start_url)
    meeting.save(update_fields=["start_url"])
    return Response({"start_url": meeting.start_url})


# --- Student endpoint ---------------------------------------------------------
@open_api("GET")
def student_meetings(request, student_id):
    student = _student(student_id)
    if not student:
        return _err("Student not found", 404)
    return Response([_row(m) for m in ScheduledMeeting.objects.filter(students=student)])

@open_api("PUT")
def update_meeting(request, pk):
    d = request.data
    teacher = _teacher(d.get("teacher_id"))
    if not teacher:
        return _err("Teacher not found", 404)
    meeting = get_object_or_404(ScheduledMeeting, pk=pk, teacher=teacher)

    start = parse_datetime(str(d.get("start_time", "")))
    if start is None or timezone.is_naive(start):
        return _err("start_time must be an ISO datetime with timezone", 400)
    if start != meeting.start_time and start <= timezone.now():
        return _err("start_time must be in the future", 400)

    try:
        minutes = int(d.get("duration_minutes", meeting.duration_minutes))
    except (TypeError, ValueError):
        minutes = 0
    if not 1 <= minutes <= MAX_MINUTES:
        return _err(f"duration_minutes must be 1-{MAX_MINUTES}", 400)

    clash = _overlapping_meeting(teacher, start, minutes, exclude_id=meeting.pk)
    if clash:
        clash_end = clash.start_time + timedelta(minutes=clash.duration_minutes)
        return _err(
            f"You already have '{clash.topic}' from {clash.start_time.isoformat()} "
            f"to {clash_end.isoformat()}. Pick a different time.",
            409,
        )

    topic = (d.get("topic") or "").strip() or meeting.topic
    description = (d.get("description") or "").strip()
    waiting_room = bool(d.get("waiting_room", meeting.waiting_room))
    host_video = bool(d.get("host_video", meeting.host_video))
    participant_video = bool(d.get("participant_video", meeting.participant_video))
    students = Student.objects.filter(teacher=teacher, pk__in=d.get("student_ids") or [])

    # 1) Update Zoom first (PATCH returns 204, _zoom handles the empty body)
    try:
        _zoom(
            "PATCH",
            f"/meetings/{meeting.meeting_id}",
            json={
                "topic": topic,
                "type": 2,
                "start_time": start.astimezone(dt_tz.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "duration": minutes,
                "agenda": description,
                "settings": {
                    "waiting_room": waiting_room,
                    "host_video": host_video,
                    "participant_video": participant_video,
                    "join_before_host": False,
                },
            },
        )
    except requests.RequestException as e:
        return _err(f"Zoom error: {e}", 502)

    # 2) Then update your DB
    meeting.topic = topic
    meeting.description = description
    meeting.start_time = start
    meeting.duration_minutes = minutes
    meeting.waiting_room = waiting_room
    meeting.host_video = host_video
    meeting.participant_video = participant_video
    meeting.save()

    old_ids = set(meeting.students.values_list("pk", flat=True))
    meeting.students.set(students)

    new_students = list(students)
    new_ids = {s.pk for s in new_students}
    added = [s for s in new_students if s.pk not in old_ids]
    kept = [s for s in new_students if s.pk in old_ids]
    removed = list(Student.objects.filter(pk__in=old_ids - new_ids))

    when = _when_text(start)
    _notify_students(added, "class_scheduled", "New class scheduled",
                     f'"{topic}" is scheduled for {when}.', meeting.id)
    _notify_students(kept, "class_updated", "Class updated",
                     f'"{topic}" was updated. It is now on {when}.', meeting.id)
    _notify_students(removed, "class_cancelled", "Removed from class",
                     f'You were removed from "{topic}".', None)
    
    meeting.students.set(students)
    return Response(_row(meeting))

@open_api("DELETE")
def delete_meeting(request, pk):
    teacher = _teacher(request.query_params.get("teacher_id"))
    if not teacher:
        return _err("Teacher not found", 404)
    meeting = get_object_or_404(ScheduledMeeting, pk=pk, teacher=teacher)

    # 1) Delete on Zoom (204). A 404 means it's already gone there, so carry on.
    try:
        _zoom("DELETE", f"/meetings/{meeting.meeting_id}")
    except requests.HTTPError as e:
        if e.response is None or e.response.status_code != 404:
            return _err(f"Zoom error: {e}", 502)
    except requests.RequestException as e:
        return _err(f"Zoom error: {e}", 502)

    students = list(meeting.students.all())
    topic = meeting.topic
    when = _when_text(meeting.start_time)

    # 2) Delete from your DB (students stop seeing it)
    meeting.delete()
    

    _notify_students(
        students,
        "class_cancelled",
        "Class cancelled",
        f'"{topic}" on {when} was cancelled by your teacher.',
        None,
    )

    return Response(status=204)