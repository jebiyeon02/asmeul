# ASMEUL 프레임 끊김 분석

2026-09-14 · ASMEUL 0.9 release · Apple M5 / macOS 26.6.2 · 내장 Retina 디스플레이

이 문서는 수정 전 진단 기록입니다. 이후 사용자의 요청으로 유리 효과 컨테이너 연결과 파티클 60fps 변경을 적용했습니다. 변경 및 검증 결과는 [PERFORMANCE_NOTES.md](PERFORMANCE_NOTES.md)의 후속 변경 항목에 기록했습니다.

## 판단

메인 스레드의 지속적인 CPU 포화보다 유리 효과·배경·창 합성 비용을 먼저 확인할 근거가 있다. 다만 이번 측정으로 사용자가 체감한 Mission Control 끊김을 재현하거나 ASMEUL의 GPU 병목을 확정하지는 못했다.

## 확인한 코드

1. `Sources/ASMEUL/ASMEULApp.swift:1573`의 `AdaptiveGlassContainer`는 정의만 있고 사용처가 없다. 실제 `GlassEffectContainer`가 메인 화면의 여러 유리 표면을 묶지 않는다. 각 트랙 카드(518), 사이드바(413), 하단 바(630)는 `AppleGlassSurface`를 통해 개별 `glassEffect`를 적용한다(1600). Apple은 여러 유리 효과를 컨테이너로 묶어 렌더링 성능을 개선하도록 안내한다. 컨테이너 누락은 확인된 사실이지만 이것이 끊김의 직접 원인인지는 비교 측정이 필요하다.
2. 메인 배경은 전체 화면 `MeshGradient`, 큰 광원 3개, blur와 screen blend로 구성된다(643–818). 그 위에 유리 카드와 반경 11의 그림자(1590)가 놓인다. 움직이는 배경과 여러 유리 표면의 조합은 렌더링 비용을 분리해 측정할 우선 대상이다. 실제 오프스크린 패스 수나 GPU 실행 시간은 측정하지 않았다.
3. 광원은 최대 15fps, 파티클은 최대 30fps 일정이다(`ASMEULApp.swift:643`, `RenderingSupport.swift:18–27`). 각각 약 66.7ms, 33.3ms 간격의 콘텐츠 갱신이라 시스템 애니메이션보다 덜 부드럽게 보일 수 있다. 이는 앱 창 전체나 Mission Control의 주사율을 제한한다는 뜻은 아니다.
4. 모션 중단은 재생 여부, 접근성 동작 줄이기, 창 occlusion 상태에 의존한다(`RenderingSupport.swift:24–30, 62–79`). 창이 비활성화되거나 시스템 전환 중일 때 별도로 장식 효과를 줄이는 처리는 없다. Mission Control에서 실제로 visible 상태가 유지되는지는 이번에 계측하지 않았다.

## 관측과 한계

- 재생 정지 상태: 3초 `sample`의 메인 스레드 표본 2,666개가 모두 이벤트 대기 경로였다.
- UI가 재생 중임을 확인한 뒤 수집한 별도 3초 `sample`: 메인 스레드 2,407개 중 2,270개(약 94.3%)가 이벤트 대기 경로였다. 이는 표본 비율이며 전체 CPU 사용률이나 GPU 여유율은 아니다.
- `Animation Hitches` 템플릿을 12초 설정으로 수집했다. 기록 메타데이터상 전체 구간은 약 13초였고, 내보낸 `hitches` 테이블에는 행이 없었다. 해당 구간에서 사용자의 증상을 확실히 재현한 것도 아니므로 무결함의 증거로 해석하지 않는다.
- Mission Control 단축키 입력은 시도했지만 전환 상태와 체감 끊김을 확실히 검증하지 못했다. 실제 표시 fps, hitch 비율, ASMEUL에 귀속되는 GPU 시간은 결론을 내릴 만큼 확보하지 못했다.
- WindowServer는 여러 앱과 시스템 창을 함께 처리하므로 그 프로세스의 CPU 수치를 ASMEUL의 비용으로 돌리지 않았다. 추적 도구 자체에도 부하가 있어 추적 중 시스템 메모리·CPU 수치로 원인을 판단하지 않았다.
- 기존 `PERFORMANCE_NOTES.md`는 사진 디코딩과 CPU 개선을 확인했지만 실제 프레임 표시 시간은 측정하지 않았다고 명시한다. 기존 최적화 성공이 현재 프레임 문제 해결을 보장하지 않는다.

## 다음 비교 측정 순서

동일한 창 크기, 스크롤 위치, 선택 트랙, 재생 상태를 유지한 채 한 가지씩 비교한다.

1. 카드의 유리 효과를 단순한 반투명 표면으로 대체한 진단 빌드와 원본을 비교해 유리 합성 비용을 분리한다.
2. 유리 효과를 유지하면서 실제 `GlassEffectContainer`를 연결한 빌드를 비교한다. 카드가 붙거나 형태가 합쳐지지 않도록 간격도 확인한다.
3. 배경과 파티클만 정지시켜 동적 배경과 유리의 조합 영향을 비교한다.
4. Mission Control 진입·복귀와 스크롤을 반복해 표시 간격, render/GPU 시간과 hitch를 비교한다. 비용을 먼저 줄인 뒤 파티클 갱신률을 조정한다.

앱 소스·빌드·저장 설정은 변경하지 않았다. 진단 표본과 내보낸 XML은 `.build/frame-analysis/`에 저장했다. 대용량 원본 trace는 필요한 자료를 내보낸 뒤 정리했다.

## 근거 문서

- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)
- [Apple: Demystify and eliminate hitches in the render phase](https://developer.apple.com/videos/play/tech-talks/10857/)
