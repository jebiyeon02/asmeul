# 몰입모드 및 공통 UI 성능 확인

2026-09-14, Apple Silicon / macOS 26.6.2, release 빌드에서 확인했습니다.

## 확인한 병목

기존 몰입 화면은 12Hz `TimelineView`가 사진의 변환과 명암 레이어 전체를 갱신하고 `drawingGroup`으로 합성했습니다. `NSImage(contentsOf:)` 캐시가 있어도 렌더링 중 JPEG의 지연 디코딩이 반복됐습니다.

4초 `sample` 프로파일의 메인 스레드 표본 2,902개 중 1,174개가 ImageIO의 이미지 표면 생성 경로, 1,170개가 `applejpeg_decode_image_all` 경로에 걸렸습니다. 이 수치는 호출 횟수가 아니라 해당 스택에서 수집한 표본 수입니다.

## 변경 후 확인

- `CGImageSourceCreateThumbnailAtIndex`와 즉시 캐시 옵션으로 actor 안에서 디코딩하고, 크기별 `CGImage`를 재사용합니다. 미리보기에는 원본 크기의 텍스처를 쓰지 않습니다.
- 사진은 `CALayer.contents`에 유지하고 확대·이동만 Core Animation으로 처리합니다. 명암 레이어는 파티클 시간 변화에 의존하지 않습니다.
- 파티클은 최대 30fps, 메인 화면 광원은 최대 15fps로 분리했습니다. Canvas는 이 화면에 불필요한 extended-linear 색상 처리를 하지 않습니다.
- 오디오 모니터의 250ms 갱신은 별도 음량계 객체에 전달하며, 표시되는 막대 수가 같으면 알림을 보내지 않습니다.

| 측정 | 변경 전 | 변경 후 |
| --- | --- | --- |
| `top` CPU 구간 | 61.3%, 93.3% | 4.1%, 8.4%, 8.9%, 7.3% |
| 몰입 사진 | 눈 내리는 카페 | 지구의 밤 |
| 선택된 소리 | 빗소리 1 | 빗소리 1, 심우주1, 심우주2 |
| 메인 스레드 JPEG 디코딩 표본 | 1,170 / 2,902 | 0 / 2,509 |

변경 후 3초 프로파일에서 메인 스레드 표본 2,371 / 2,509개는 이벤트 대기 경로였습니다. 사진과 오디오 설정 및 시스템 부하가 다른 관찰 구간이므로 CPU 수치를 동일 조건의 개선율로 해석하지 않습니다. 프레임 표시 시간을 직접 계측하지 않았으므로 일정의 목표 fps를 실측 fps로 주장하지 않습니다.

## 검증

- `swift build -c release`: 통과.
- `scripts/test.sh`: 기존 DSP·믹서·HRTF 검사 및 새 렌더링 회귀 검사 통과.
- 애니메이션 시계: 정지/재개, 중복 시작/정지, 긴 정지 후 재개, 10분 이후 시간 연속성.
- 음량계: 값이 같을 때 알림 억제, 감쇠, 정지 후 초기화.
- 환경 사진 5개: 512px/2560px 디코딩 상한, 크기별 캐시 구분, 동일 이미지 재사용, 없는 파일 처리.
- 실제 앱 재실행, 저장된 믹스 유지, 재생, 몰입모드 진입, 사진·빗줄기·컨트롤 표시 확인.

긴 오디오 파일은 기존과 같이 시작 시 전체 디코딩합니다. 이번 변경은 오디오 로딩 방식이나 음질을 바꾸지 않았으며, 큰 믹스의 오디오 메모리 사용량은 별도 항목입니다.

구현 시 참고한 Apple 문서: [이미지와 그래픽 처리](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf), [애니메이션 일정](https://developer.apple.com/documentation/swiftui/timelineschedule/animation%28minimuminterval%3Apaused%3A%29).
