"""
Signs the JWT that the Flutter app passes to the Zoom Meeting SDK (authZoom / join).

Setup
-----
1. .env (plain KEY=value lines, no quotes):
       ZOOM_SDK_KEY=<Client ID from Marketplace > your app > App Credentials>
       ZOOM_SDK_SECRET=<Client Secret from the same box>

2. settings.py (next to your other settings; `import os` at the top):
       ZOOM_SDK_KEY = os.getenv("ZOOM_SDK_KEY", "")
       ZOOM_SDK_SECRET = os.getenv("ZOOM_SDK_SECRET", "")

3. accounts/urls.py:
       from .zoom_sdk import zoom_sdk_token
       path("zoom/sdk-token/", zoom_sdk_token, name="zoom-sdk-token"),
   (Full URL becomes /accounts/zoom/sdk-token/ because accounts.urls is mounted at accounts/.)

The Client Secret must stay on the server. Never put it in the Flutter app.

Check the claim names (appKey, sdkKey, mn, role, tokenExp) against Zoom's current
Meeting SDK authorization docs when you test, since Zoom occasionally changes them.
"""
import time

import jwt  # PyJWT
from django.conf import settings
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

# Zoom requires the token to live at least 30 minutes; 2 hours covers a class.
TOKEN_LIFETIME_SECONDS = 2 * 60 * 60


@api_view(["POST"])

@permission_classes([AllowAny])
def zoom_sdk_token(request):
    sdk_key = getattr(settings, "ZOOM_SDK_KEY", "")
    sdk_secret = getattr(settings, "ZOOM_SDK_SECRET", "")
    if not sdk_key or not sdk_secret:
        return Response({"error": "Zoom SDK credentials are not configured"}, status=500)

    meeting_number = str(request.data.get("meeting_number", "")).replace(" ", "")
    if not meeting_number.isdigit():
        return Response({"error": "meeting_number must be digits only"}, status=400)

    try:
        role = int(request.data.get("role", 0))  # 0 = participant, 1 = host
    except (TypeError, ValueError):
        return Response({"error": "role must be 0 or 1"}, status=400)
    if role not in (0, 1):
        return Response({"error": "role must be 0 or 1"}, status=400)

    iat = int(time.time()) - 30  # small allowance for clock skew
    exp = iat + TOKEN_LIFETIME_SECONDS
    payload = {
        "appKey": sdk_key,
        "sdkKey": sdk_key,
        "mn": meeting_number,
        "role": role,
        "iat": iat,
        "exp": exp,
        "tokenExp": exp,
    }
    token = jwt.encode(payload, sdk_secret, algorithm="HS256")

    return Response({"signature": token, "expires_at": exp})