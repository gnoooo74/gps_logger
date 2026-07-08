# 위치 수집 앱 (Flutter)

15분 주기로 백그라운드에서 위치를 자동 수집하고, 날짜별 리스트로 보여주는 앱입니다.
목록에는 "구/동" 수준의 간단 주소를, 상세화면에서는 카카오맵 + 도로명/지번 상세주소를 보여줍니다.

## 1. 카카오 API 키 발급 (필수)

1. https://developers.kakao.com 접속 → 로그인 → [내 애플리케이션] → [애플리케이션 추가하기]
2. 생성된 앱의 [앱 키]에서 두 개를 복사해둡니다.
   - **REST API 키** → 역지오코딩(좌표→주소 변환)에 사용
   - **JavaScript 키** → 앱 안 지도 표시(WebView)에 사용
3. [플랫폼] 설정에서 **Web 플랫폼**을 추가하고, 사이트 도메인에 `file:///android_asset` 또는 실제 배포 도메인을 등록해야 지도가 로드됩니다. (WebView 로컬 HTML이라 처음에 안 뜨면 플랫폼 등록 없이도 되는 경우가 많지만, 안 뜨면 이 단계를 확인하세요)
4. 코드에 키 입력:
   - `lib/services/kakao_api.dart` → `kakaoRestApiKey` 값 교체
   - `lib/screens/detail_screen.dart` → `kakaoJsKey` 값 교체

키 없이는 주소 변환/지도 표시가 안 되니 꼭 먼저 설정하세요.

## 2. GitHub에 올려서 APK 자동 빌드하기

로컬에 Flutter를 설치할 필요 없이, GitHub Actions가 대신 빌드해줍니다.

```bash
cd location_tracker
git init
git add .
git commit -m "init: 위치 수집 앱"
git branch -M main
git remote add origin https://github.com/{본인계정}/{저장소이름}.git
git push -u origin main
```

푸시하면 자동으로 `.github/workflows/build_apk.yml`이 실행됩니다.

## 3. APK 다운로드

1. GitHub 저장소 → 상단 **Actions** 탭
2. 방금 실행된 워크플로우(초록 체크) 클릭
3. 맨 아래 **Artifacts** 섹션에서 `location-tracker-apk` 다운로드 (zip)
4. 압축 풀면 `app-release.apk` → 안드로이드 폰에 옮겨서 설치

> 참고: 안드로이드에서 "출처를 알 수 없는 앱" 설치 허용이 필요할 수 있습니다.

## 4. 참고 사항 (백그라운드 수집 관련)

- Android 12+ 는 배터리 최적화 때문에 백그라운드 타이머가 지연될 수 있습니다. 앱 설정 → 배터리 → "제한 없음"으로 바꿔주면 더 안정적으로 동작해요.
- 최초 실행 시 위치 권한 요청에서 **"항상 허용"**을 선택해야 백그라운드 수집이 계속됩니다. ("앱 사용 중에만 허용"을 선택하면 앱을 꺼두면 수집이 멈춰요)
- 수집 주기는 `lib/services/location_service.dart`의 `collectIntervalMinutes` 값을 바꾸면 조절됩니다.
- 카카오맵 API는 개인 기준 일 20만 건까지 무료라 이 정도 사용량에서는 걱정 없어요.

## 5. 폴더 구조

```
lib/
  models/location_record.dart      # 위치기록 데이터 모델
  db/database_helper.dart          # SQLite 저장/조회
  services/location_service.dart   # 백그라운드 자동 수집
  services/kakao_api.dart          # 카카오 역지오코딩 API
  screens/home_screen.dart         # 날짜별 리스트 화면
  screens/detail_screen.dart       # 지도+상세주소 화면
  main.dart                        # 앱 진입점, 권한요청
scripts/patch_manifest.py          # CI에서 안드로이드 권한 자동 주입
.github/workflows/build_apk.yml    # GitHub Actions APK 빌드
```
