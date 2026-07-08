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
    <!-- 다운로드/gps_logs 폴더에 파일 로그를 쓰기 위한 권한.
         선언 안 하면 GpsLogFileService의 권한 요청이 계속 조용히 실패함. -->
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" tools:ignore="ScopedStorage"/>
"""

# Android 14(API 34)부터는 포그라운드 서비스 시작 시 타입을 선언하지 않으면
# MissingForegroundServiceTypeException으로 즉시 크래시함.
# flutter_background_service가 만드는 서비스에 위치 타입을 명시해줘야 함.
# tools:replace="android:exported" 가 필요한 이유: flutter_background_service_android
# 플러그인 자체 매니페스트가 이 서비스를 exported=true로 선언하고 있어서,
# 여기서 값을 지정하면 매니페스트 병합 충돌(Manifest merger failed)이 남.
SERVICE_DECLARATION = """
    <service
        android:name="id.flutter.flutter_background_service.BackgroundService"
        android:foregroundServiceType="location"
        android:exported="false"
        tools:replace="android:exported" />
"""

def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    changed = False

    # tools:replace 속성을 쓰려면 루트 <manifest> 태그에 xmlns:tools 선언이 있어야 함.
    # `flutter create`가 만드는 기본 매니페스트에는 xmlns:android만 있고 없음.
    if "xmlns:tools" not in content:
        content = re.sub(
            r'(<manifest\s+xmlns:android="[^"]*")',
            r'\1 xmlns:tools="http://schemas.android.com/tools"',
            content,
            count=1,
        )
        changed = True

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
