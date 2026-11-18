#!/usr/bin/env python3
"""Patch the generated android/ folder (idempotent): permissions + foreground service."""
import re

PATH = "android/app/src/main/AndroidManifest.xml"
PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
]
SERVICE = (
    '<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" '
    'android:foregroundServiceType="dataSync" android:exported="false" />'
)

text = open(PATH, encoding="utf-8").read()

missing = [p for p in PERMISSIONS if p not in text]
if missing:
    tags = "".join('\n    <uses-permission android:name="%s"/>' % p for p in missing)
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + tags, text, count=1)

if "flutter_foreground_task.service.ForegroundService" not in text:
    text = text.replace("</application>", "    " + SERVICE + "\n    </application>", 1)

# السماح باتصالات http:// (مثل OmniRoute محلياً أو على الشبكة) في نسخة release.
if "usesCleartextTraffic" not in text:
    text = re.sub(r"<application\b", '<application android:usesCleartextTraffic="true"', text, count=1)

open(PATH, "w", encoding="utf-8").write(text)
print("AndroidManifest patched")
