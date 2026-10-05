import asyncio
import logging
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.urls import re_path

from .group_call_push import notify_group_call
from .models import Student, Teacher, GroupMessage

log = logging.getLogger(__name__)


class GroupRoomConsumer(AsyncJsonWebsocketConsumer):
    # teacher_id -> {peer_id: {"name": str, "channel": str}}
    # Fine for one daphne process. With several workers keep this in Redis.
    rooms = {}

    async def connect(self):
        self.teacher_id = int(self.scope["url_route"]["kwargs"]["teacher_id"])
        qs = parse_qs(self.scope["query_string"].decode())
        self.role = (qs.get("role") or [""])[0]
        try:
            self.user_id = int((qs.get("user_id") or ["0"])[0])
        except ValueError:
            self.user_id = 0

        name = await self.lookup_name()
        if not name:
            await self.close(code=4403)  # not a member of this teacher's room
            return

        self.name = name
        self.peer_id = f"{self.role}_{self.user_id}"
        self.room_group = f"room_{self.teacher_id}"
        self.peer_group = f"peer_{self.teacher_id}_{self.peer_id}"

        await self.channel_layer.group_add(self.room_group, self.channel_name)
        await self.channel_layer.group_add(self.peer_group, self.channel_name)
        await self.accept()

        peers = self.rooms.setdefault(self.teacher_id, {})
        existing = [{"id": pid, "name": info["name"]} for pid, info in peers.items() if pid != self.peer_id]
        first_teacher_join = self.role == "teacher" and self.peer_id not in peers
        peers[self.peer_id] = {"name": self.name, "channel": self.channel_name}

        await self.send_json({
            "type": "welcome",
            "self": self.peer_id,
            "peers": existing,
            "history": await self.recent_chat(),
        })
        await self.channel_layer.group_send(self.room_group, {
            "type": "relay",
            "payload": {"type": "peer-joined", "id": self.peer_id, "name": self.name},
            "exclude": self.peer_id,
        })

        if first_teacher_join:
            # students who are somehow already in the room don't need a push
            online_students = [
                int(pid.split("_", 1)[1]) for pid in peers if pid.startswith("student_")
            ]
            self._push_task = asyncio.create_task(self.push_class_call(online_students))

    async def push_class_call(self, skip_ids):
        try:
            await database_sync_to_async(notify_group_call)(
                self.teacher_id, self.name, skip_ids
            )
        except Exception:
            log.exception("group call push failed")

    async def disconnect(self, code):
        if not hasattr(self, "peer_id"):
            return
        peers = self.rooms.get(self.teacher_id, {})
        # only announce if this socket is still the current one for this user
        if peers.get(self.peer_id, {}).get("channel") == self.channel_name:
            peers.pop(self.peer_id, None)
            await self.channel_layer.group_send(self.room_group, {
                "type": "relay",
                "payload": {"type": "peer-left", "id": self.peer_id},
                "exclude": self.peer_id,
            })
        await self.channel_layer.group_discard(self.room_group, self.channel_name)
        await self.channel_layer.group_discard(self.peer_group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        t = content.get("type")

        if t in ("offer", "answer", "ice"):
            target = content.get("to")
            if not target:
                return
            await self.channel_layer.group_send(f"peer_{self.teacher_id}_{target}", {
                "type": "relay",
                "payload": {**content, "from": self.peer_id, "name": self.name},
            })

        elif t == "chat":
            text = (content.get("text") or "").strip()
            if not text:
                return
            at = await self.save_chat(text)
            await self.channel_layer.group_send(self.room_group, {
                "type": "relay",
                "payload": {"type": "chat", "from": self.peer_id, "name": self.name, "text": text, "at": at},
            })

        elif t == "screen-state":
            await self.channel_layer.group_send(self.room_group, {
                "type": "relay",
                "payload": {"type": "screen-state", "from": self.peer_id, "sharing": bool(content.get("sharing"))},
                "exclude": self.peer_id,
            })

    # channel-layer handler for every group_send above
    async def relay(self, event):
        if event.get("exclude") == self.peer_id:
            return
        await self.send_json(event["payload"])

    @database_sync_to_async
    def lookup_name(self):
        if self.role == "teacher":
            t = Teacher.objects.filter(pk=self.user_id).first()
            return t.username if t and t.pk == self.teacher_id else None
        if self.role == "student":
            s = Student.objects.filter(pk=self.user_id, teacher_id=self.teacher_id).first()
            return s.username if s else None
        return None

    @database_sync_to_async
    def save_chat(self, text):
        m = GroupMessage.objects.create(
            teacher_id=self.teacher_id, sender_type=self.role,
            sender_id=self.user_id, sender_name=self.name, text=text,
        )
        return m.created_at.isoformat()

    @database_sync_to_async
    def recent_chat(self):
        qs = GroupMessage.objects.filter(teacher_id=self.teacher_id).order_by("-created_at")[:50]
        return [
            {"from": f"{m.sender_type}_{m.sender_id}", "name": m.sender_name,
             "text": m.text, "at": m.created_at.isoformat()}
            for m in reversed(list(qs))
        ]


websocket_urlpatterns = [
    re_path(r"^ws/group/(?P<teacher_id>\d+)/$", GroupRoomConsumer.as_asgi()),
]