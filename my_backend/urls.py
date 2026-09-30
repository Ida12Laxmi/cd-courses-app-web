"""
URL configuration for my_backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path,include
from django.conf import settings
from django.conf.urls.static import static
from accounts.webhook import zoom_webhook
from accounts.zoomsdk import zoom_sdk_token
from accounts import zoommeeting as zm


urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/', include('accounts.urls')),
    path("zoom/webhook/", zoom_webhook, name="zoom-webhook"),
    path("accounts/zoom/sdk-token/", zoom_sdk_token, name="zoom-sdk-token-accounts"),
    path("meetings/students/<int:teacher_id>/", zm.invitable_students, name="invitable_students"),
    path("meetings/schedule/", zm.schedule_meeting, name="schedule_meeting"),
    path("meetings/teacher/<int:teacher_id>/", zm.teacher_meetings, name="teacher_meetings"),
    path("meetings/student/<int:student_id>/", zm.student_meetings, name="student_meetings"),
    path("meetings/<int:pk>/host/", zm.host_meeting, name="host_meetings"),
    path("meetings/<int:pk>/update/", zm.update_meeting, name="update_meeting"),
    path("meetings/<int:pk>/delete/", zm.delete_meeting, name="delete_meeting"),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
