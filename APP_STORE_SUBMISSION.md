# ASMEUL Mac App Store 제출 준비

## 현재 포함된 배포 설정

- 앱 이름과 실행 파일, SwiftPM 타깃, 리소스 번들, 내부 오디오 API는 `ASMEUL`로 통일합니다.
- App Store 빌드는 App Sandbox, 사용자 선택 파일 읽기/쓰기, Core Audio 입력 권한만 요청합니다.
- 시스템 오디오 접근 이유 문구와 개인정보 매니페스트를 앱 번들에 포함합니다.
- 제출용 앱은 Apple Distribution으로 서명하고 Mac Installer Distribution으로 서명한 `ASMEUL.pkg`로 만듭니다.
- 앱은 macOS 14.4 이상, 현재 빌드 머신과 같은 Apple Silicon 아키텍처를 대상으로 합니다.

## 등록 완료된 배포 정보

- App Store Connect 앱 이름: `ASMEUL`
- App Store Connect Apple ID: `6811824420`
- 번들 ID: `studio.asmeul`
- Team ID: `6XF54T55WS`
- Provider Public ID: `57dc6630-8fb3-4f02-ad05-e3974b1b2056`
- 버전 / 빌드: `1.0` / `1`
- App Store 프로비저닝 프로파일: `ASMEUL Mac App Store` (`eb0db081-7aba-4810-838d-221a13d6d71e`)
- Apple Distribution 인증서: `Apple Distribution: Yeonjun Jeong (6XF54T55WS)`
- Installer 인증서: `3rd Party Mac Developer Installer: Yeonjun Jeong (6XF54T55WS)`

인증서와 프로비저닝 프로파일은 이 Mac의 로그인 Keychain 및 Xcode 프로파일 폴더에 설치되어 있습니다. 아래 명령으로 제출 패키지를 다시 만들 수 있습니다.

```bash
ASMEUL_PROVISIONING_PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/eb0db081-7aba-4810-838d-221a13d6d71e.provisionprofile" \
./scripts/build-app-store.sh
```

완성 파일은 `build/app-store/ASMEUL.pkg`입니다. 업로드 인증을 Keychain에 저장한 뒤 다음 형식으로 전송합니다.

```bash
xcrun altool --upload-package build/app-store/ASMEUL.pkg \
  --platform macos \
  --apple-id 6811824420 \
  --bundle-id studio.asmeul \
  --bundle-version 1 \
  --bundle-short-version-string 1.0 \
  --provider-public-id 57dc6630-8fb3-4f02-ad05-e3974b1b2056 \
  --wait \
  -p '@keychain:ASMEUL_ALTOOL'
```

`ASMEUL_ALTOOL`에는 Apple ID의 일반 암호가 아니라 계정 페이지에서 발급한 앱 전용 암호를 저장합니다. 암호는 문서나 셸 기록에 남기지 않습니다.

2026년 9월 14일 기준 `altool --validate-app`의 Apple 서버 검증을 오류 없이 통과했습니다. 검증된 패키지의 SHA-256은 `9f08cb2efee7eab9e39d9a4c73c0542643bc416babe09382e9aaed462afe3604`입니다.

같은 날 App Store Connect 업로드와 처리도 완료되어 빌드 상태가 `VALID_BINARY`로 확인됐습니다. Delivery UUID는 `ae8a9ed3-8136-4e6a-8539-321287f4705f`이며, 버전 `1.0`의 빌드 선택 목록에 `1.0 (1)`로 표시됩니다.

배포 인증서 없이 샌드박스 번들만 먼저 검사하려면 아래 명령을 사용합니다. 결과 ZIP은 제출용이 아닙니다.

```bash
ASMEUL_APP_STORE_DRY_RUN=1 ./scripts/build-app-store.sh
```

## 제출 전 체크리스트

- `ASMEUL_VERSION`은 App Store Connect 버전과 맞추고 `ASMEUL_BUILD_NUMBER`는 매 업로드마다 증가시킵니다.
- `./scripts/test.sh`와 `./scripts/test-performance.sh`를 통과시킵니다.
- 샌드박스 빌드에서 시스템 전체 오디오와 앱별 오디오, MP3 가져오기, 프리셋 가져오기/내보내기를 실제로 확인합니다.
- App Store Connect에 설명, 키워드, 지원 URL, 개인정보 처리방침 URL, 카테고리, 연령 등급, 가격/배포 국가와 macOS 스크린샷을 입력합니다.
- App Privacy에는 현재 코드 기준으로 추적 및 서버 전송 데이터가 없음을 반영하되, 분석 SDK나 네트워크 기능을 추가했다면 답변과 개인정보 매니페스트를 다시 검토합니다.
- 음원과 이미지의 배포 권리를 확인하고 `SOUND_CREDITS.md`의 근거를 보관합니다.

## 가격 계획

- 출시 기념 무료: 2026년 9월 24일까지
- 유료 전환: 2026년 9월 25일부터
- 1회 구매 가격: 대한민국 기준 ₩4,900

## App Review 메모 초안

ASMEUL은 사용자가 Mac에서 재생 중인 오디오에 공간 효과를 적용하고 로컬 ASMR 음원을 겹쳐 듣는 앱입니다. 재생 버튼을 누르면 macOS의 시스템 오디오 녹음 권한을 요청합니다. 캡처한 오디오는 메모리에서 실시간으로 처리해 기본 출력 장치로 재생하며 녹음, 파일 저장, 네트워크 전송을 하지 않습니다. 사용자가 MP3 또는 프리셋을 선택하면 해당 파일은 앱 기능 수행을 위해서만 로컬 앱 컨테이너에 복사됩니다.

검토 방법: 앱을 실행하고 시스템 오디오 권한을 허용한 뒤 음악을 재생합니다. 왼쪽 입력에서 시스템 전체 또는 실행 중인 앱을 고르고, 소리 카드를 하나 이상 선택한 후 하단 재생 버튼을 누르면 효과가 적용됩니다.
