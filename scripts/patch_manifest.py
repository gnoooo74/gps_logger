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

def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    if "ACCESS_BACKGROUND_LOCATION" in content:
        print("이미 패치되어 있음, 건너뜀")
        return

    # <application ...> 태그 바로 앞에 permission 블록 삽입
    new_content = re.sub(
        r"(\s*)(<application)",
        PERMISSIONS + r"\1\2",
        content,
        count=1,
    )

    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        f.write(new_content)

    print("AndroidManifest.xml 패치 완료")


if __name__ == "__main__":
    sys.exit(main())
