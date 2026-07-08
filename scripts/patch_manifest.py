"""
`flutter create .` 실행 후 자동 생성된 AndroidManifest.xml에
위치 수집 앱에 필요한 권한을 주입하는 스크립트.
GitHub Actions 워크플로우에서 자동으로 실행됩니다.
"""
import re
import sys

MANIFEST_PATH = "android/app/src/main/AndroidManifest.xml"

PERMISSIONS = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
"""

# Android 14(API 34)부터는 포그라운드 서비스 시작 시 타입을 선언하지 않으면
# MissingForegroundServiceTypeException으로 즉시 크래시함.
# flutter_background_service가 만드는 서비스에 위치 타입을 명시해줘야 함.
SERVICE_DECLARATION = """
    <service
        android:name="id.flutter.flutter_background_service.BackgroundService"
        android:foregroundServiceType="location"
        android:exported="false" />
"""

def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    changed = False

    if "ACCESS_BACKGROUND_LOCATION" not in content:
        content = re.sub(
            r"(\s*)(<application)",
            PERMISSIONS + r"\1\2",
            content,
            count=1,
        )
        changed = True

    if "flutter_background_service.BackgroundService" not in content:
        content = re.sub(
            r"(\s*)(</application>)",
            SERVICE_DECLARATION + r"\1\2",
            content,
            count=1,
        )
        changed = True

    if not changed:
        print("이미 패치되어 있음, 건너뜀")
        return

    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print("AndroidManifest.xml 패치 완료")


if __name__ == "__main__":
    sys.exit(main())
