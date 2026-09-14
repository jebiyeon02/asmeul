import AppKit
import SwiftUI

@main struct ASMEULApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    Window("아스믈", id: "main") {
      ContentView(model: delegate.model).preferredColorScheme(.dark)
    // Keep the native titlebar controls available.  The title itself is hidden
    // after the window is attached, so the app keeps its edge-to-edge layout
    // while the red/yellow/green controls and native fullscreen action remain.
    }
    .defaultSize(width: 1080, height: 720)
    .windowStyle(.titleBar)
    Settings {
      SettingsView(model: delegate.model)
        .frame(width: 460, height: 300)
        .preferredColorScheme(.dark)
    }
    MenuBarExtra("ASMEUL", systemImage: "waveform.path") {
      MenuPanel(model: delegate.model).preferredColorScheme(.dark)
    }.menuBarExtraStyle(.window)
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AudioModel()
  func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor final class FocusWindowCoordinator: NSObject, ObservableObject {
  private weak var window: NSWindow?
  private weak var model: AudioModel?
  private var isTransitioning = false
  private var notificationTokens: [NSObjectProtocol] = []
  private var escapeMonitor: Any?

  func attach(window: NSWindow, model: AudioModel) {
    guard self.window !== window else {
      synchronize()
      return
    }

    self.window = window
    self.model = model
    configureWindowChrome(window)
    installEscapeMonitor()
    window.collectionBehavior.insert(.fullScreenPrimary)

    notificationTokens.forEach(NotificationCenter.default.removeObserver)
    notificationTokens = [
      NotificationCenter.default.addObserver(
        forName: NSWindow.didEnterFullScreenNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.isTransitioning = false
          // The user can enter fullscreen from the native green traffic light
          // or Window menu as well as from the in-app 몰입 button.
          if self?.model?.focusMode == false {
            self?.model?.focusMode = true
          }
          self?.synchronize()
        }
      },
      NotificationCenter.default.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.isTransitioning = false
          if self?.model?.focusMode == true {
            self?.model?.focusMode = false
          }
          self?.synchronize()
        }
      },
    ]

    synchronize()
  }

  private func configureWindowChrome(_ window: NSWindow) {
    // SwiftUI's hiddenTitleBar style removes these controls entirely. Keep the
    // titlebar transparent and title-less, but restore the standard controls.
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // Do not make the entire content view a window drag target. That setting
    // competes with ScrollView's pan gesture and makes dragging the sound list
    // move the app window instead of scrolling it.
    window.isMovableByWindowBackground = false
    window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
    window.standardWindowButton(.closeButton)?.isHidden = false
    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
    window.standardWindowButton(.zoomButton)?.isHidden = false
    window.standardWindowButton(.zoomButton)?.isEnabled = true
  }

  private func installEscapeMonitor() {
    guard escapeMonitor == nil else { return }
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53, self?.model?.focusMode == true else { return event }
      self?.model?.toggleFocusMode()
      return nil
    }
  }

  func setFocus(_ focused: Bool) {
    guard model != nil else { return }
    synchronize()
  }

  private func synchronize() {
    guard let window, let model else { return }
    let shouldBeFullscreen = model.focusMode
    let isFullscreen = window.styleMask.contains(.fullScreen)
    guard shouldBeFullscreen != isFullscreen, !isTransitioning else { return }

    isTransitioning = true
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window, let model = self.model else { return }
      guard model.focusMode == shouldBeFullscreen else {
        self.isTransitioning = false
        self.synchronize()
        return
      }

      if window.styleMask.contains(.fullScreen) != shouldBeFullscreen {
        window.toggleFullScreen(nil)
      } else {
        self.isTransitioning = false
      }
    }
  }

  deinit {
    notificationTokens.forEach(NotificationCenter.default.removeObserver)
    if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
  }
}

let ink = Color(red: 0.035, green: 0.04, blue: 0.055)
let accent = Color(red: 0.93, green: 0.79, blue: 0.55)
let muted = Color.white.opacity(0.52)
let hairline = Color.white.opacity(0.1)
let directions = ["앞", "왼쪽 앞", "오른쪽 앞", "왼쪽 뒤", "오른쪽 뒤", "뒤", "위"]

struct ContentView: View {
  @ObservedObject var model: AudioModel
  @StateObject private var windowCoordinator = FocusWindowCoordinator()
  @State private var windowVisible = true
  var body: some View {
    ZStack {
      if model.focusMode {
        FocusEnvironment(model: model)
          .transition(.opacity.combined(with: .scale(scale: 1.015)))
          .zIndex(2)
      } else {
        ZStack {
          AmbientFog(
            theme: model.theme,
            activeTrackIDs: model.activeTrackIDs,
            animationsEnabled: model.animationsEnabled,
            isPlaying: model.running)
          GeometryReader { proxy in
            let availableHeight = max(0, proxy.size.height - 36)
            let scrollHeight = max(180, availableHeight - 58 - 58 - 36)
            AdaptiveGlassContainer {
              HStack(spacing: 22) {
                Sidebar(model: model).frame(height: availableHeight)
                VStack(spacing: 18) {
                  header
                  ScrollView {
                    // Keep the shared card effect inside the scroll clipping boundary.
                    AdaptiveGlassContainer {
                      LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                      ) {
                        ForEach(model.catalog) { track in TrackCard(model: model, track: track) }
                      }.padding(.vertical, 2)
                    }
                  }
                  .scrollIndicators(.hidden)
                  .frame(height: scrollHeight)
                  BottomBar(model: model)
                }
                .frame(maxWidth: .infinity, minHeight: availableHeight, maxHeight: availableHeight)
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ink)
    .environment(\.motionVisible, windowVisible)
    .animation(.easeInOut(duration: 0.35), value: model.focusMode)
    .background(
      WindowAccessor(
        onResolve: { window in windowCoordinator.attach(window: window, model: model) },
        onVisibilityChange: { visible in
          if windowVisible != visible { windowVisible = visible }
        })
    )
    .onChange(of: model.focusMode) { _, focused in
      windowCoordinator.setFocus(focused)
    }
    .onDisappear { model.rememberMood() }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text("좋아하는 소리를 겹쳐보세요.")
          .font(.system(size: 27, weight: .medium, design: .rounded))
        HStack(spacing: 10) {
          Text("\(model.selectedTrackCount)개의 소리").font(.system(size: 11, weight: .medium))
            .contentTransition(.numericText())
            .foregroundStyle(model.selectedTrackCount > 0 ? accent : muted)
          Button {
            model.clearTracks()
          } label: {
            Label("선택 모두 해제", systemImage: "xmark.circle")
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 9).padding(.vertical, 5)
          }
          .buttonStyle(.plain)
          .foregroundStyle(
            model.selectedTrackCount > 0 ? Color.white.opacity(0.75) : muted.opacity(0.45)
          )
          .background(
            Color.white.opacity(model.selectedTrackCount > 0 ? 0.08 : 0.03), in: Capsule()
          )
          .disabled(model.selectedTrackCount == 0)
          .accessibilityIdentifier("clear-tracks")
        }
      }
      Spacer()
      SettingsLink {
        Image(systemName: "gearshape")
          .font(.system(size: 12, weight: .medium))
          .frame(width: 34, height: 30)
      }
      .buttonStyle(GlassButtonStyle())
      .accessibilityLabel("설정")
      Button {
        model.importSound()
      } label: {
        Label("MP3 추가", systemImage: "plus").font(.system(size: 11, weight: .medium))
          .padding(.horizontal, 14).padding(.vertical, 9)
      }.buttonStyle(GlassButtonStyle())
      Button {
        model.toggleFocusMode()
      } label: {
        Label("몰입", systemImage: "viewfinder")
          .font(.system(size: 11, weight: .medium))
          .padding(.horizontal, 13).padding(.vertical, 9)
      }
      .buttonStyle(GlassButtonStyle())
      .accessibilityIdentifier("focus-mode")
      Button {
        model.toggle()
      } label: {
        Label(model.running ? "중지" : "재생", systemImage: model.running ? "stop.fill" : "play.fill")
          .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 9)
      }.buttonStyle(GoldButtonStyle(active: model.running)).disabled(!model.assetsReady)
        .accessibilityIdentifier("power")
    }.frame(height: 58)
  }
}

struct SettingsView: View {
  @ObservedObject var model: AudioModel

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .firstTextBaseline) {
        Label("ASMEUL", systemImage: "waveform.path")
          .font(.system(size: 22, weight: .medium, design: .rounded))
          .foregroundStyle(accent)
        Spacer()
        Text("설정")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(muted)
      }

      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 14) {
          Image(systemName: model.animationsEnabled ? "sparkles" : "sparkles.slash")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(model.animationsEnabled ? accent : muted)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 4) {
            Text("배경 애니메이션")
              .font(.system(size: 13, weight: .medium))
            Text("MeshGradient와 음원별 파티클 효과를 표시합니다.")
              .font(.system(size: 10))
              .foregroundStyle(muted)
          }
          Spacer()
          Toggle("", isOn: $model.animationsEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(accent)
        }
        Divider().overlay(hairline)
        Label(
          model.animationsEnabled
            ? (model.running
              ? "재생 중 가벼운 앰비언트 모션을 렌더링합니다."
              : "중지 상태에서는 현재 화면을 유지하고, 재생 시 다시 움직입니다.")
            : "애니메이션을 끄면 배경 업데이트와 파티클 렌더링을 중지합니다.",
          systemImage: model.animationsEnabled ? "waveform.path.ecg" : "pause.circle"
        )
        .font(.system(size: 10))
        .foregroundStyle(muted)
      }
      .padding(18)
      .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(hairline, lineWidth: 0.7))

      Spacer()
      Text("음원 선택에 따라 비·파도·바람·불씨·반딧불이·물방울 등의 움직임이 자동으로 바뀝니다.")
        .font(.system(size: 9))
        .foregroundStyle(Color.white.opacity(0.35))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ink)
  }
}

struct Sidebar: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Label("ASMEUL", systemImage: "waveform.path")
          .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(accent)
          .shadow(color: accent.opacity(0.32), radius: 10)
        Text("아스믈").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(muted)
      }.padding(.top, 24)
      Divider().overlay(hairline).padding(.vertical, 28)
      HStack {
        Label("입체음향", systemImage: "headphones").font(.system(size: 11, weight: .medium))
        Spacer()
        Toggle("", isOn: $model.spatial).labelsHidden().toggleStyle(.switch).controlSize(.small)
          .tint(accent).onChange(of: model.spatial) { model.rememberMood() }
      }
      Divider().overlay(hairline).padding(.vertical, 23)
      Text("음악 효과").font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
        .padding(.bottom, 19)
      if model.music < 0.001 {
        Text("ASMR만 모드에서는 음악 효과가 들리지 않습니다")
          .font(.system(size: 8)).foregroundStyle(.orange.opacity(0.9))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, 2)
      }
      CompactSlider(title: "Space", value: $model.space)
      CompactSlider(title: "Warmth", value: $model.warmth)
      CompactSlider(title: "Orbit", value: $model.orbit)
      Divider().overlay(hairline).padding(.top, 3).padding(.bottom, 15)
      HStack(spacing: 8) {
        Text("무드").font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
        Spacer()
        Menu {
          ForEach(AmbientTheme.allCases) { option in
            Button {
              model.theme = option
            } label: {
              Label(option.title, systemImage: option == model.theme ? "checkmark" : "circle")
            }
          }
        } label: {
          HStack(spacing: 5) {
            Circle().fill(themeSwatch(model.theme)).frame(width: 8, height: 8)
            Text(model.theme.title).font(.system(size: 10, weight: .medium))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
          }.foregroundStyle(Color.white.opacity(0.82))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("배경 무드")
      }
      Divider().overlay(hairline).padding(.vertical, 18)
      HStack(spacing: 8) {
        Text("환경").font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
        Spacer()
        EnvironmentMenu(model: model)
      }
      Spacer()
      Divider().overlay(hairline).padding(.bottom, 22)
      Text("AUDIO SOURCE").font(.system(size: 8, weight: .medium)).tracking(1.7)
        .foregroundStyle(muted).padding(.bottom, 9)
      Picker("소스", selection: Binding(get: { model.selected }, set: { model.changeSource($0) })) {
        Text("전체 시스템").tag(UInt32(0))
        ForEach(model.processes) { Text($0.name).tag($0.id) }
      }.labelsHidden().controlSize(.small)
      if model.waitingForMusic {
        Text("음악 입력 대기 중 · 원음 유지")
          .font(.system(size: 9)).foregroundStyle(.orange)
          .padding(.top, 8)
          .help("음악이 재생 중인데 효과가 들리지 않으면 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 아스믈의 오디오 접근을 허용한 뒤 다시 시작하세요.")
      }
      Label(model.outputName, systemImage: "headphones")
        .font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).padding(.top, 12)
      Text("ASMEUL 0.9").font(.system(size: 7, weight: .medium)).tracking(1.5)
        .foregroundStyle(Color.white.opacity(0.25)).padding(.top, 17).padding(.bottom, 4)
    }.padding(.horizontal, 22).frame(width: 218).glass(cornerRadius: 16)
  }

  private func themeSwatch(_ theme: AmbientTheme) -> LinearGradient {
    switch theme {
    case .deepSea:
      return LinearGradient(
        colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .aurora:
      return LinearGradient(
        colors: [.mint, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .spectral:
      return LinearGradient(
        colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }
}

struct CompactSlider: View {
  let title: String
  @Binding var value: Double
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(title).font(.system(size: 11, weight: .medium))
        Spacer()
        Text("\(Int(value * 100))").font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(accent)
      }
      Slider(value: $value, in: 0...1).tint(accent).accessibilityLabel(title)
    }.padding(.bottom, 20)
  }
}

struct TrackCard: View {
  @ObservedObject var model: AudioModel
  @Environment(\.motionVisible) private var visible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let track: ASMRTrack
  @State private var isRenaming = false
  @State private var renameDraft = ""
  var setting: TrackSetting {
    model.tracks.first(where: { $0.id == track.id }) ?? TrackSetting(id: track.id)
  }
  var duration: String {
    guard let value = model.durations[track.id] else { return "--:--" }
    let seconds = Int(value)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
  var body: some View {
    VStack(spacing: 10) {
      Button {
        model.toggleTrack(track.id)
      } label: {
        HStack(spacing: 11) {
          Image(systemName: track.symbol).font(.system(size: 19, weight: .light)).frame(width: 24)
          Text(track.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
          Spacer()
          Text(model.loadingTracks.contains(track.id) ? "준비 중" : duration).font(.system(size: 8, design: .monospaced)).foregroundStyle(muted)
          if model.animationsEnabled && model.running && setting.enabled && visible && !reduceMotion {
            Image(systemName: setting.enabled ? "wave.3.right.circle.fill" : "circle")
              .font(.system(size: 18, weight: .light))
              .symbolEffect(.pulse.byLayer, options: .repeating, value: setting.enabled)
          } else {
            Image(systemName: setting.enabled ? "wave.3.right.circle.fill" : "circle")
              .font(.system(size: 18, weight: .light))
          }
        }.foregroundStyle(setting.enabled ? accent : Color.white.opacity(0.78)).contentShape(
          Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("track-\(track.id)")
      .accessibilityLabel(track.name)
      .accessibilityValue(setting.enabled ? "선택됨" : "선택 안 됨")
      HStack(spacing: 9) {
        Slider(
          value: Binding(get: { setting.volume }, set: { model.setTrackVolume(track.id, $0) }),
          in: 0...1
        ).tint(accent).accessibilityLabel("\(track.name) 음량")
        Text("\(Int(setting.volume * 100))%").font(.system(size: 8, design: .monospaced))
          .foregroundStyle(muted).frame(width: 30)
      }
      if model.spatial {
        HStack(spacing: 8) {
          Menu {
            ForEach(Array(directions.enumerated()), id: \.offset) { index, name in
              Button(name) { model.setPosition(track.id, direction: index) }
            }
          } label: {
            Label(
              directions[setting.direction ?? model.defaultDirection(track.id)],
              systemImage: "location.fill"
            ).font(.system(size: 8, weight: .medium)).foregroundStyle(muted)
          }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(track.name) 위치")
          Spacer()
          Image(systemName: "dot.circle").font(.system(size: 8)).foregroundStyle(muted)
          Slider(
            value: Binding(
              get: { setting.distance ?? 0.3 }, set: { model.setPosition(track.id, distance: $0) }),
            in: 0...1
          ).frame(width: 82).tint(accent).accessibilityLabel("\(track.name) 거리")
          Image(systemName: "circle.dotted").font(.system(size: 8)).foregroundStyle(muted)
        }.frame(height: 16)
      }
    }.padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: model.spatial ? 119 : 92)
      .glass(cornerRadius: 13, active: setting.enabled)
      .contextMenu {
        if track.custom {
          Button("이름 변경") {
            renameDraft = track.name
            isRenaming = true
          }
          Button("음원 삭제", role: .destructive) {
            model.removeCustomSound(track.id)
          }
        }
      }
      .alert("음원 이름 변경", isPresented: $isRenaming) {
        TextField("이름", text: $renameDraft)
        Button("취소", role: .cancel) {}
        Button("저장") {
          model.renameCustomSound(track.id, name: renameDraft)
        }
      } message: {
        Text("사용자 음원에 표시할 이름을 입력하세요.")
      }
  }
}

private struct OutputLevelMeter: View {
  @ObservedObject var meter: AudioMeter
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<8, id: \.self) { i in
        Capsule().fill(i < meter.litBars ? accent : Color.white.opacity(0.08))
          .frame(width: 3, height: 8)
      }
    }
    .frame(width: 52, alignment: .leading)
    .accessibilityLabel("출력 레벨")
  }
}

struct BottomBar: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    HStack(spacing: 12) {
      Button {
        model.toggle()
      } label: {
        Image(systemName: model.running ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)
          .background(
            model.running ? accent.opacity(0.16) : Color.white.opacity(0.04), in: Circle()
          )
          .overlay(Circle().stroke(model.running ? accent : hairline, lineWidth: 1.2))
          .foregroundStyle(model.running ? accent : Color.white.opacity(0.72))
          .shadow(color: model.running ? accent.opacity(0.35) : .clear, radius: 10)
      }
      .buttonStyle(.plain)
      .disabled(!model.assetsReady)
      .accessibilityIdentifier("bottom-power")

      if let error = model.error {
        Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
          .layoutPriority(1)
      } else {
        OutputLevelMeter(meter: model.meter)
      }

      Spacer(minLength: 8)

      Toggle(
        "ASMR만", isOn: Binding(get: { model.music < 0.001 }, set: { model.music = $0 ? 0 : 1 })
      )
      .toggleStyle(.switch)
      .controlSize(.mini)
      .tint(accent)
      .font(.system(size: 9))
      .fixedSize()

      Divider().frame(height: 24).overlay(hairline)

      HStack(spacing: 8) {
        Image(systemName: "speaker.wave.2").foregroundStyle(muted)
        Slider(value: $model.gain, in: 0...1).frame(width: 94).tint(accent)
          .accessibilityLabel("출력 볼륨")
        Text("\(Int(model.gain * 100))%")
          .font(.system(size: 8, design: .monospaced))
          .foregroundStyle(muted)
          .frame(width: 32, alignment: .trailing)
      }
      .fixedSize()

      Menu {
        Button("믹스 내보내기…") { model.exportPreset() }
        Button("믹스 가져오기…") { model.importPreset() }
        Divider()
        Button("아스믈 종료") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 24)
      .accessibilityLabel("더 보기")

      Divider().frame(height: 24).overlay(hairline)

      Button(model.bypass ? "믹스로 돌아가기" : "원음 듣기") { model.bypass.toggle() }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(accent)
        .disabled(!model.running)
        .fixedSize()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
    .glass(cornerRadius: 14)
  }
}

struct AmbientFog: View {
  let theme: AmbientTheme
  let activeTrackIDs: Set<Int>
  let animationsEnabled: Bool
  let isPlaying: Bool

  var body: some View {
    ZStack {
      // Keep broad lights at 60 Hz; faster particles can use high-refresh displays.
      MotionTimeline(isRunning: animationsEnabled && isPlaying, framesPerSecond: 60) { time in
        AmbientFogFrame(
          time: animationsEnabled ? time : 0, theme: theme,
          activeTrackIDs: activeTrackIDs)
      }
      if animationsEnabled {
        MotionTimeline(isRunning: isPlaying, framesPerSecond: 120) { time in
          AmbientParticles(time: time, theme: theme, activeTrackIDs: activeTrackIDs)
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

private struct AmbientFogFrame: View {
  let time: TimeInterval
  let theme: AmbientTheme
  let activeTrackIDs: Set<Int>

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        ink
        mesh
        fogLight(
          color: primaryLight, opacity: 0.2, size: 560, blur: 150,
          x: -proxy.size.width * 0.28 + sin(time * 0.18) * 160,
          y: proxy.size.height * 0.3 + cos(time * 0.14) * 100, pulse: 0.19
        )
        .blendMode(.screen)
        fogLight(
          color: secondaryLight, opacity: 0.12, size: 430, blur: 130,
          x: proxy.size.width * 0.12 + sin(time * 0.11) * 130,
          y: -proxy.size.height * 0.08 + cos(time * 0.16) * 90, pulse: 0.23
        )
        .blendMode(.screen)
        fogLight(
          color: warmLight, opacity: 0.12, size: 390, blur: 120,
          x: proxy.size.width * 0.3 + cos(time * 0.13) * 125,
          y: -proxy.size.height * 0.3 + sin(time * 0.17) * 85, pulse: 0.27
        )
        .blendMode(.screen)
      }
    }
  }

  @ViewBuilder private var mesh: some View {
    if #available(macOS 15.0, *) {
      MeshGradient(
        width: 3, height: 3,
        points: meshPoints,
        colors: meshColors, smoothsColors: true)
    } else {
      LinearGradient(
        colors: [Color(red: 0.06, green: 0.065, blue: 0.08), ink, .black],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private var meshPoints: [SIMD2<Float>] {
    [
      .init(0, 0), .init(Float(0.5 + 0.16 * sin(time * 0.16)), 0), .init(1, 0),
      .init(0, 0.5),
      .init(
        Float(0.5 + 0.16 * cos(time * 0.12)),
        Float(0.5 + 0.12 * sin(time * 0.1))),
      .init(1, 0.5), .init(0, 1), .init(0.5, 1), .init(1, 1),
    ]
  }

  private var meshColors: [Color] {
    switch theme {
    case .deepSea:
      return [
        ink, Color(red: 0.05, green: 0.09, blue: 0.19), ink,
        Color(red: 0.025, green: 0.07, blue: 0.13),
        Color(red: 0.07, green: 0.14, blue: 0.23),
        Color(red: 0.05, green: 0.09, blue: 0.16), ink,
        Color(red: 0.03, green: 0.08, blue: 0.15), .black,
      ]
    case .aurora:
      return [
        ink, Color(red: 0.08, green: 0.08, blue: 0.2), ink,
        Color(red: 0.03, green: 0.1, blue: 0.14),
        Color(red: 0.12, green: 0.16, blue: 0.25),
        Color(red: 0.09, green: 0.08, blue: 0.2), ink,
        Color(red: 0.04, green: 0.12, blue: 0.16), .black,
      ]
    case .spectral:
      return [
        ink, Color(red: 0.14, green: 0.07, blue: 0.17), ink,
        Color(red: 0.07, green: 0.04, blue: 0.12),
        Color(red: 0.18, green: 0.1, blue: 0.2),
        Color(red: 0.18, green: 0.08, blue: 0.08), ink,
        Color(red: 0.1, green: 0.05, blue: 0.14), .black,
      ]
    }
  }

  private var primaryLight: Color {
    if fireActive { return .orange }
    if snowActive { return .white }
    if rainActive { return .blue }
    if waveActive { return .cyan }
    if windActive { return .mint }
    if caveActive { return .indigo }
    if fireflyActive { return .yellow }
    if underwaterActive { return .blue }
    if radioActive || cityActive || pencilActive { return .orange }
    if keyboardActive { return .white }
    if chimesActive { return .yellow }
    switch theme {
    case .deepSea: return .indigo
    case .aurora: return .purple
    case .spectral: return .purple
    }
  }

  private var secondaryLight: Color {
    if fireActive { return .red }
    if snowActive { return .cyan }
    if rainActive { return .cyan }
    if waveActive { return .blue }
    if windActive { return .cyan }
    if caveActive { return .purple }
    if fireflyActive { return .orange }
    if underwaterActive { return .teal }
    if radioActive || cityActive || pencilActive { return .purple }
    if keyboardActive { return .cyan }
    if chimesActive { return .white }
    switch theme {
    case .deepSea: return .cyan
    case .aurora: return .mint
    case .spectral: return .indigo
    }
  }

  private var warmLight: Color {
    if fireActive { return .yellow }
    if snowActive { return .blue }
    if rainActive { return .indigo }
    if waveActive { return .mint }
    if windActive { return .white }
    if caveActive { return .purple }
    if fireflyActive { return .yellow }
    if underwaterActive { return .cyan }
    if radioActive || cityActive || pencilActive { return .orange }
    if keyboardActive { return .indigo }
    if chimesActive { return .yellow }
    switch theme {
    case .deepSea: return .blue
    case .aurora: return .purple
    case .spectral: return .orange
    }
  }

  private func fogLight(
    color: Color, opacity: Double, size: CGFloat, blur: CGFloat, x: CGFloat, y: CGFloat,
    pulse: Double
  ) -> some View {
    let breathing = 0.7 + 0.3 * (0.5 + 0.5 * sin(time * pulse))
    let scale = 0.9 + 0.1 * (0.5 + 0.5 * cos(time * pulse * 0.73))
    let gradient = RadialGradient(
      stops: [
        .init(color: color.opacity(opacity * breathing), location: 0),
        .init(color: color.opacity(opacity * breathing * 0.42), location: 0.34),
        .init(color: color.opacity(opacity * 0.08), location: 0.7),
        .init(color: .clear, location: 1),
      ],
      center: .center,
      startRadius: 0,
      endRadius: size * 0.5)
    return Circle().fill(gradient).frame(width: size, height: size)
      .scaleEffect(scale).blur(radius: blur * 0.32).offset(x: x, y: y)
  }

  private var rainActive: Bool {
    activeTrackIDs.contains(0) || activeTrackIDs.contains(1)
  }

  private var fireActive: Bool {
    activeTrackIDs.contains(18) || activeTrackIDs.contains(19)
  }

  private var snowActive: Bool { activeTrackIDs.contains(32) }

  private var waveActive: Bool {
    activeTrackIDs.contains(10) || activeTrackIDs.contains(14) || activeTrackIDs.contains(15)
  }

  private var windActive: Bool { activeTrackIDs.contains(11) }

  private var caveActive: Bool {
    activeTrackIDs.contains(7) || activeTrackIDs.contains(8)
  }

  private var fireflyActive: Bool {
    activeTrackIDs.contains(9) || activeTrackIDs.contains(17)
  }

  private var underwaterActive: Bool { activeTrackIDs.contains(20) }
  private var radioActive: Bool { activeTrackIDs.contains(2) }
  private var keyboardActive: Bool { activeTrackIDs.contains(3) || activeTrackIDs.contains(4) }
  private var pencilActive: Bool { activeTrackIDs.contains(5) || activeTrackIDs.contains(6) }
  private var cityActive: Bool { activeTrackIDs.contains(12) }
  private var chimesActive: Bool { activeTrackIDs.contains(13) }
}

private struct AmbientParticles: View {
  let time: TimeInterval
  let theme: AmbientTheme
  let activeTrackIDs: Set<Int>

  var body: some View {
    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) {
      context, size in
      let t = time
      if rainActive { drawRain(&context, size: size, time: t) }
      if snowActive { drawSnow(&context, size: size, time: t) }
      if waveActive { drawWaves(&context, size: size, time: t) }
      if windActive { drawWind(&context, size: size, time: t) }
      if fireflyActive { drawFireflies(&context, size: size, time: t) }
      if caveActive { drawCaveEcho(&context, size: size, time: t) }
      if underwaterActive { drawUnderwater(&context, size: size, time: t) }
      if radioActive { drawRadio(&context, size: size, time: t) }
      if keyboardActive { drawKeyboard(&context, size: size, time: t) }
      if pencilActive { drawPencil(&context, size: size, time: t) }
      if cityActive { drawCity(&context, size: size, time: t) }
      if chimesActive { drawChimes(&context, size: size, time: t) }
      if fireActive { drawFire(&context, size: size, time: t) }
      if customActive || activeTrackIDs.isEmpty { drawDust(&context, size: size, time: t) }
    }
    .blendMode(.screen)
    .opacity(0.9)
  }

  private func drawRain(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<44 {
      let seed = Double(index)
      let baseX = fraction(seed * 0.61803398875 + 0.17)
      // Faster vertical motion makes rainfall read immediately even on a large desk view.
      let cycle = fraction(seed * 0.137 + time * (0.105 + fraction(seed * 0.17) * 0.075))
      let x = baseX * size.width + sin(time * 0.11 + seed) * 12
      let y = cycle * size.height - 48
      let length = 11 + fraction(seed * 0.47) * 18
      let alpha = 0.1 + fraction(seed * 0.23) * 0.16
      var path = Path()
      path.move(to: CGPoint(x: x, y: y))
      path.addLine(to: CGPoint(x: x - 3.5, y: y + length))
      context.stroke(path, with: .color(Color.white.opacity(alpha)), lineWidth: 0.7)
    }
  }

  private func drawSnow(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<58 {
      let seed = Double(index)
      let fallSpeed = 0.022 + fraction(seed * 0.17) * 0.024
      let cycle = fraction(seed * 0.137 + time * fallSpeed)
      let baseX = fraction(seed * 0.61803398875 + 0.09)
      let drift = sin(time * (0.18 + fraction(seed * 0.13) * 0.12) + seed * 1.7) * (10 + fraction(seed * 0.31) * 18)
      let x = baseX * size.width + drift
      let y = cycle * (size.height + 90) - 45
      let radius = 1.1 + fraction(seed * 0.47) * 2.5
      let alpha = 0.12 + fraction(seed * 0.23) * 0.2
      let core = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
      context.fill(Path(ellipseIn: core), with: .color(Color.white.opacity(alpha)))

      if index % 5 == 0 {
        let arm = radius * 2.8
        var flake = Path()
        flake.move(to: CGPoint(x: x - arm, y: y))
        flake.addLine(to: CGPoint(x: x + arm, y: y))
        flake.move(to: CGPoint(x: x, y: y - arm))
        flake.addLine(to: CGPoint(x: x, y: y + arm))
        context.stroke(flake, with: .color(Color.cyan.opacity(alpha * 0.7)), lineWidth: 0.6)
      }
    }
  }

  private func drawWaves(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for band in 0..<7 {
      let bandPhase = Double(band) * 0.73
      let baseY = size.height * (0.2 + CGFloat(band) * 0.105)
      var path = Path()
      for sample in 0...42 {
        let progress = CGFloat(sample) / 42
        let x = progress * size.width
        let wave = sin(Double(sample) * 0.42 + time * 0.82 + bandPhase)
        let y = baseY + CGFloat(wave) * (5 + CGFloat(band % 3) * 2)
        if sample == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
      }
      let alpha = 0.06 + Double(band % 3) * 0.025
      context.stroke(
        path, with: .color(Color.cyan.opacity(alpha)), lineWidth: band == 2 ? 1.1 : 0.75)
    }
  }

  private func drawWind(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for stream in 0..<10 {
      let seed = Double(stream)
      let baseY = size.height * (0.16 + CGFloat(stream) * 0.08)
      var path = Path()
      for sample in 0...24 {
        let progress = CGFloat(sample) / 24
        let x = progress * size.width
        let sway = sin(time * 0.62 + seed * 0.7 + Double(sample) * 0.34) * (9 + seed * 0.45)
        let y = baseY + CGFloat(sway)
        if sample == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
      }
      context.stroke(
        path,
        with: .color(Color.mint.opacity(0.04 + Double(stream % 3) * 0.025)),
        lineWidth: stream % 3 == 0 ? 1.1 : 0.7)
    }
  }

  private func drawFireflies(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<20 {
      let seed = Double(index)
      let baseX = fraction(seed * 0.731 + 0.14) * size.width
      let baseY = (0.2 + fraction(seed * 0.271) * 0.62) * size.height
      let x = baseX + CGFloat(sin(time * 0.18 + seed * 1.7) * 42)
      let y = baseY + CGFloat(cos(time * 0.24 + seed * 0.9) * 28)
      let pulse = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 1.7 + seed * 2.2))
      let radius = 1.2 + fraction(seed * 0.41) * 2.2
      let glow = CGRect(x: x - radius * 3, y: y - radius * 3, width: radius * 6, height: radius * 6)
      let core = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
      context.fill(Path(ellipseIn: glow), with: .color(Color.yellow.opacity(0.025 * pulse)))
      context.fill(Path(ellipseIn: core), with: .color(Color.yellow.opacity(0.22 * pulse)))
    }
  }

  private func drawCaveEcho(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.54)
    for index in 0..<6 {
      let seed = Double(index)
      let cycle = fraction(seed * 0.19 + time * 0.055)
      let width = 100 + CGFloat(cycle) * 520
      let height = width * (0.32 + CGFloat(index % 2) * 0.08)
      let rect = CGRect(
        x: center.x - width * 0.5, y: center.y - height * 0.5, width: width, height: height)
      context.stroke(
        Path(ellipseIn: rect),
        with: .color(Color.indigo.opacity((1 - cycle) * (0.08 + Double(index % 2) * 0.025))),
        lineWidth: index == 2 ? 1.1 : 0.7)
    }
  }

  private func drawUnderwater(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<18 {
      let seed = Double(index)
      let cycle = fraction(seed * 0.23 + time * (0.018 + fraction(seed * 0.11) * 0.014))
      let x = fraction(seed * 0.613 + 0.08) * size.width + CGFloat(sin(time * 0.22 + seed) * 15)
      let y = size.height + 24 - CGFloat(cycle) * (size.height + 70)
      let radius = 1.4 + fraction(seed * 0.37) * 4.2
      let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
      context.stroke(Path(ellipseIn: rect), with: .color(Color.cyan.opacity(0.08)), lineWidth: 0.8)
      if index % 4 == 0 {
        context.fill(
          Path(ellipseIn: rect.insetBy(dx: radius * 0.58, dy: radius * 0.58)),
          with: .color(Color.white.opacity(0.06)))
      }
    }
  }

  private func drawRadio(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for band in 0..<3 {
      let baseY = size.height * (0.44 + CGFloat(band) * 0.065)
      var path = Path()
      for sample in 0...42 {
        let progress = CGFloat(sample) / 42
        let x = size.width * 0.12 + progress * size.width * 0.76
        let y = baseY + CGFloat(sin(Double(sample) * 0.68 + time * 0.5 + Double(band)) * 4)
        if sample == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
      }
      context.stroke(
        path, with: .color(Color.orange.opacity(0.04 + Double(band) * 0.018)), lineWidth: 0.8)
    }
  }

  private func drawKeyboard(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<16 {
      let seed = Double(index)
      let pulse = 0.5 + 0.5 * sin(time * 2.2 + seed * 1.47)
      let x = size.width * (0.18 + CGFloat(index) * 0.043)
      let y = size.height * 0.78 + CGFloat(sin(time * 0.48 + seed) * 5)
      let height = 8 + CGFloat(pulse) * 16
      let rect = CGRect(x: x, y: y - height, width: 3, height: height)
      context.fill(
        Path(roundedRect: rect, cornerRadius: 1.5),
        with: .color(Color.white.opacity(0.045 + pulse * 0.11)))
    }
  }

  private func drawPencil(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<8 {
      let seed = Double(index)
      let cycle = fraction(seed * 0.18 + time * 0.07)
      let x = cycle * size.width
      let y = size.height * (0.25 + fraction(seed * 0.29) * 0.5)
      var path = Path()
      path.move(to: CGPoint(x: x - 15, y: y + 9))
      path.addLine(to: CGPoint(x: x + 5, y: y - 9))
      context.stroke(
        path, with: .color(Color.orange.opacity(0.06 + Double(index % 3) * 0.025)), lineWidth: 0.9)
    }
  }

  private func drawCity(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<18 {
      let seed = Double(index)
      let x = fraction(seed * 0.517 + time * 0.008 * (1 + fraction(seed * 0.13))) * size.width
      let y = size.height * (0.2 + fraction(seed * 0.347) * 0.58)
      let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 0.8 + seed * 2.1))
      let width = 2 + CGFloat(index % 3)
      let rect = CGRect(x: x, y: y, width: width, height: width * 0.7)
      context.fill(
        Path(roundedRect: rect, cornerRadius: 1),
        with: .color(Color.yellow.opacity(0.04 + pulse * 0.12)))
    }
  }

  private func drawChimes(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<12 {
      let seed = Double(index)
      let x = fraction(seed * 0.639 + 0.12) * size.width + CGFloat(sin(time * 0.36 + seed) * 16)
      let y = fraction(seed * 0.277 + time * 0.025) * size.height
      let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 1.2 + seed * 1.3))
      let length = 2 + CGFloat(pulse) * 5
      var path = Path()
      path.move(to: CGPoint(x: x - length, y: y))
      path.addLine(to: CGPoint(x: x + length, y: y))
      path.move(to: CGPoint(x: x, y: y - length))
      path.addLine(to: CGPoint(x: x, y: y + length))
      context.stroke(path, with: .color(Color.white.opacity(0.05 + pulse * 0.1)), lineWidth: 0.8)
    }
  }

  private func drawFire(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for index in 0..<28 {
      let seed = Double(index)
      let baseX = 0.14 + fraction(seed * 0.731) * 0.72
      let cycle = fraction(seed * 0.317 + time * (0.018 + fraction(seed * 0.19) * 0.022))
      let x = baseX * size.width + sin(time * 0.3 + seed * 1.7) * 24
      let y = size.height + 28 - cycle * (size.height + 100)
      let radius = 0.8 + fraction(seed * 0.41) * 2.0
      let alpha = 0.16 + fraction(seed * 0.29) * 0.25
      let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
      context.fill(Path(ellipseIn: rect), with: .color(Color.orange.opacity(alpha)))
      if index % 4 == 0 {
        let core = CGRect(
          x: x - radius * 0.32, y: y - radius * 0.32,
          width: radius * 0.64, height: radius * 0.64)
        context.fill(Path(ellipseIn: core), with: .color(Color.yellow.opacity(alpha * 0.9)))
      }
    }
  }

  private func drawDust(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    let color: Color = theme == .deepSea ? .cyan : (theme == .aurora ? .mint : .orange)
    for index in 0..<22 {
      let seed = Double(index)
      let x = fraction(seed * 0.618 + 0.31) * size.width + sin(time * 0.08 + seed) * 18
      let y = fraction(seed * 0.271 + time * (0.004 + fraction(seed * 0.13) * 0.004)) * size.height
      let radius = 0.6 + fraction(seed * 0.43) * 1.2
      let alpha = 0.05 + fraction(seed * 0.21) * 0.1
      context.fill(
        Path(
          ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
        with: .color(color.opacity(alpha)))
    }
  }

  private var rainActive: Bool {
    activeTrackIDs.contains(0) || activeTrackIDs.contains(1)
  }

  private var fireActive: Bool {
    activeTrackIDs.contains(18) || activeTrackIDs.contains(19)
  }

  private var snowActive: Bool { activeTrackIDs.contains(32) }

  private var waveActive: Bool {
    activeTrackIDs.contains(10) || activeTrackIDs.contains(14) || activeTrackIDs.contains(15)
  }

  private var windActive: Bool { activeTrackIDs.contains(11) }

  private var caveActive: Bool {
    activeTrackIDs.contains(7) || activeTrackIDs.contains(8)
  }

  private var fireflyActive: Bool {
    activeTrackIDs.contains(9) || activeTrackIDs.contains(17)
  }

  private var underwaterActive: Bool { activeTrackIDs.contains(20) }
  private var radioActive: Bool { activeTrackIDs.contains(2) }
  private var keyboardActive: Bool { activeTrackIDs.contains(3) || activeTrackIDs.contains(4) }
  private var pencilActive: Bool { activeTrackIDs.contains(5) || activeTrackIDs.contains(6) }
  private var cityActive: Bool { activeTrackIDs.contains(12) }
  private var chimesActive: Bool { activeTrackIDs.contains(13) }
  private var customActive: Bool { activeTrackIDs.contains { (21..<32).contains($0) } }

  private func fraction(_ value: Double) -> Double { value - floor(value) }
}

struct EnvironmentMenu: View {
  @ObservedObject var model: AudioModel
  var compact = false

  var body: some View {
    Menu {
      ForEach(EnvironmentPhoto.library) { option in
        Button {
          model.selectEnvironment(option.id)
        } label: {
          Label(
            option.title,
            systemImage: option.id == model.environmentID
              ? "checkmark.circle.fill" : "photo")
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: compact ? "photo.on.rectangle" : "photo")
          .font(.system(size: compact ? 11 : 10, weight: .medium))
        Text(model.selectedEnvironment.title)
          .font(.system(size: compact ? 9 : 10, weight: .medium))
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 7, weight: .bold))
      }
      .foregroundStyle(compact ? Color.white.opacity(0.72) : Color.white.opacity(0.82))
      .padding(.horizontal, compact ? 10 : 0)
      .padding(.vertical, compact ? 7 : 4)
      .background(
        compact ? Color.black.opacity(0.18) : Color.clear,
        in: Capsule())
    }
    .menuStyle(.borderlessButton)
    .accessibilityLabel("몰입 환경")
  }
}

struct EnvironmentThumbnail: View {
  let photo: EnvironmentPhoto
  let selected: Bool
  let width: CGFloat
  let height: CGFloat
  let showLabels: Bool
  @State private var image: CGImage?

  init(
    photo: EnvironmentPhoto,
    selected: Bool,
    width: CGFloat = 112,
    height: CGFloat = 58,
    showLabels: Bool = true
  ) {
    self.photo = photo
    self.selected = selected
    self.width = width
    self.height = height
    self.showLabels = showLabels
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      photoImage
        .frame(width: width, height: height)
        .clipped()
      LinearGradient(
        colors: [.clear, Color.black.opacity(0.78)],
        startPoint: .top,
        endPoint: .bottom)
      if showLabels {
        VStack(alignment: .leading, spacing: 2) {
          Text(photo.title)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
          Text(photo.subtitle)
            .font(.system(size: 6, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.bottom, 7)
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(selected ? accent : Color.white.opacity(0.12), lineWidth: selected ? 1.5 : 0.7))
    .shadow(color: selected ? accent.opacity(0.22) : .clear, radius: 8)
    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(photo.title)
    .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
    .task(id: photo.fileName) {
      guard let url = Bundle.module.url(forResource: photo.fileName, withExtension: nil) else { return }
      let decoded = await EnvironmentImageStore.shared.image(at: url, maxPixelSize: 512)
      guard !Task.isCancelled else { return }
      image = decoded
    }
  }

  @ViewBuilder private var photoImage: some View {
    if let image {
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFill()
    } else {
      Color.white.opacity(0.06)
    }
  }
}

struct FocusEnvironment: View {
  @ObservedObject var model: AudioModel
  @State private var dockExpanded = false

  var body: some View {
    ZStack {
      CinematicEnvironment(
        theme: model.theme,
        photo: model.selectedEnvironment,
        activeTrackIDs: model.activeTrackIDs,
        animationsEnabled: model.animationsEnabled,
        isPlaying: model.running)

      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Spacer()
          Text(Date(), style: .time)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2.5)
            .foregroundStyle(Color.white.opacity(0.58))
            .shadow(color: .black.opacity(0.35), radius: 8)

          Button {
            model.toggleFocusMode()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.76))
              .frame(width: 30, height: 30)
              .background(Color.black.opacity(0.18), in: Circle())
              .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("exit-focus-mode")
          .accessibilityLabel("몰입 모드 나가기")
        }
        Spacer()
      }
      .padding(.horizontal, 30)
      .padding(.top, 24)

      VStack(spacing: 0) {
        Spacer()
        FocusDock(model: model, isExpanded: $dockExpanded)
          .padding(.bottom, 18)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: model.focusMode) { _, focused in
      if !focused { dockExpanded = false }
    }
    .onExitCommand {
      // Escape is the familiar exit affordance while the immersive view owns
      // the whole window. Leave normal window navigation untouched.
      if model.focusMode { model.toggleFocusMode() }
    }
  }
}

private struct CinematicEnvironment: View {
  let theme: AmbientTheme
  let photo: EnvironmentPhoto
  let activeTrackIDs: Set<Int>
  let animationsEnabled: Bool
  let isPlaying: Bool

  var body: some View {
    ZStack {
      FocusPhotoBackground(photo: photo, isAnimating: animationsEnabled && isPlaying)
      if animationsEnabled && !activeTrackIDs.isEmpty {
        MotionTimeline(isRunning: isPlaying, framesPerSecond: 120) { time in
          AmbientParticles(time: time, theme: theme, activeTrackIDs: activeTrackIDs)
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

private struct FocusPhotoBackground: View {
  let photo: EnvironmentPhoto
  let isAnimating: Bool
  @Environment(\.displayScale) private var displayScale
  @Environment(\.motionVisible) private var visible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var image: CGImage?

  var body: some View {
    GeometryReader { proxy in
      // Bucket resize requests and cap decoded textures, including on large Retina displays.
      let pixels = min(4096, max(512, Int(ceil(max(proxy.size.width, proxy.size.height) * displayScale * 1.06 / 512)) * 512))
      ZStack {
        Color.black
        if let image {
          CompositedPhoto(image: image, isAnimating: isAnimating && visible && !reduceMotion)
        }
        LinearGradient(
          colors: [Color.black.opacity(0.22), Color.black.opacity(0.08), Color.black.opacity(0.46)],
          startPoint: .top, endPoint: .bottom)
        RadialGradient(
          colors: [.clear, Color.black.opacity(0.22)], center: .center,
          startRadius: min(proxy.size.width, proxy.size.height) * 0.18,
          endRadius: max(proxy.size.width, proxy.size.height) * 0.78)
        Color.black.opacity(0.3)
      }
      .clipped()
      .task(id: "\(photo.fileName):\(pixels)") {
        guard let url = Bundle.module.url(forResource: photo.fileName, withExtension: nil) else { return }
        let decoded = await EnvironmentImageStore.shared.image(at: url, maxPixelSize: pixels)
        guard !Task.isCancelled else { return }
        image = decoded
      }
    }
  }
}

struct FocusDock: View {
  @ObservedObject var model: AudioModel
  @Binding var isExpanded: Bool
  @State private var isPinned = false

  private let dockWidth: CGFloat = 660
  private let collapsedHeight: CGFloat = 78
  private let expandedHeight: CGFloat = 176
  private let dockBarHeight: CGFloat = 72

  private var activeTracks: [ASMRTrack] {
    model.catalog.filter { track in
      model.tracks.first(where: { $0.id == track.id })?.enabled == true
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      if isExpanded {
        FocusDockDetails(model: model, tracks: activeTracks)
          .frame(width: dockWidth, height: 78, alignment: .topLeading)
          .padding(.bottom, dockBarHeight)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .offset(y: 12)),
              removal: .opacity.combined(with: .offset(y: 10))))
      }

      dockBar
    }
    .frame(width: dockWidth, height: isExpanded ? expandedHeight : collapsedHeight, alignment: .bottom)
    .glass(cornerRadius: 38)
    .accessibilityIdentifier("focus-dock")
    .onHover { hovering in
      withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
        if hovering {
          isExpanded = true
        } else if !isPinned {
          isExpanded = false
        }
      }
    }
    .animation(.spring(response: 0.46, dampingFraction: 0.88), value: isExpanded)
  }

  private var dockBar: some View {
    HStack(spacing: 0) {
      HStack(spacing: 15) {
        if activeTracks.isEmpty {
          Image(systemName: "waveform")
            .font(.system(size: 16, weight: .light))
            .foregroundStyle(Color.white.opacity(0.68))
        } else {
          ForEach(Array(activeTracks.prefix(4))) { track in
            Image(systemName: track.symbol)
              .font(.system(size: 17, weight: .light))
              .foregroundStyle(Color.white.opacity(0.8))
              .help(track.name)
          }
        }
      }
      .frame(width: 180, alignment: .leading)

      Spacer(minLength: 12)

      Button {
        model.toggle()
      } label: {
        Image(systemName: model.running ? "pause.fill" : "play.fill")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 58, height: 58)
          .background(
            model.running ? accent.opacity(0.25) : Color.white.opacity(0.06),
            in: Circle())
          .overlay(Circle().stroke(accent.opacity(0.78), lineWidth: 1.2))
          .foregroundStyle(model.running ? accent : Color.white.opacity(0.84))
          .shadow(color: accent.opacity(model.running ? 0.42 : 0.12), radius: 14)
      }
      .buttonStyle(.plain)
      .disabled(!model.assetsReady)
      .accessibilityIdentifier("focus-dock-power")

      Spacer(minLength: 12)

      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2.fill")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.76))
        Slider(value: $model.gain, in: 0...1)
          .frame(width: 88)
          .tint(accent)
          .accessibilityLabel("몰입 모드 출력 볼륨")
      }
      .frame(width: 142, alignment: .trailing)

      Divider()
        .frame(height: 28)
        .overlay(Color.white.opacity(0.18))
        .padding(.horizontal, 15)

      Button {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
          if isExpanded {
            isPinned = false
            isExpanded = false
          } else {
            isPinned = true
            isExpanded = true
          }
        }
      } label: {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.68))
          .frame(width: 26, height: 30)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isExpanded ? "믹스 목록 접기" : "믹스 목록 펼치기")
    }
    .padding(.horizontal, 24)
    .frame(width: dockWidth, height: dockBarHeight)
  }
}

private struct FocusDockDetails: View {
  @ObservedObject var model: AudioModel
  let tracks: [ASMRTrack]

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 8) {
        ForEach(EnvironmentPhoto.library) { photo in
          Button {
            model.selectEnvironment(photo.id)
          } label: {
            EnvironmentThumbnail(
              photo: photo,
              selected: model.environmentID == photo.id,
              width: 80,
              height: 48,
              showLabels: false)
          }
          .buttonStyle(.plain)
          .help(photo.title)
          .accessibilityIdentifier("environment-\(photo.id)")
        }
      }

      Divider()
        .frame(height: 48)
        .overlay(Color.white.opacity(0.18))

      if tracks.isEmpty {
        Image(systemName: "waveform")
          .font(.system(size: 16, weight: .light))
          .foregroundStyle(Color.white.opacity(0.45))
          .frame(width: 42)
          .help("믹서에서 사운드를 선택하세요")
      } else {
        HStack(spacing: 8) {
          ForEach(Array(tracks.prefix(3))) { track in
            VStack(spacing: 5) {
              Image(systemName: track.symbol)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(accent)
              Slider(
                value: Binding(
                  get: { model.tracks.first(where: { $0.id == track.id })?.volume ?? 0 },
                  set: { model.setTrackVolume(track.id, $0) }),
                in: 0...1)
                .tint(accent)
                .frame(width: 42)
                .accessibilityLabel("\(track.name) 음량")
            }
            .frame(width: 44)
            .help(track.name)
          }
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 11)
    .padding(.bottom, 7)
  }
}

struct AdaptiveGlassContainer<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  @ViewBuilder var body: some View {
    if #available(macOS 26.0, *) {
      // Share glass rendering without merging cards across their 12-point gaps.
      // This is the effect's merging threshold, not the layout's spacing.
      GlassEffectContainer(spacing: 0) { content }
    } else {
      content
    }
  }
}

extension View {
  func glass(cornerRadius: CGFloat, active: Bool = false) -> some View {
    modifier(AppleGlassSurface(cornerRadius: cornerRadius, active: active))
      .shadow(
        color: active ? Color.indigo.opacity(0.14) : Color.black.opacity(0.22), radius: 11, y: 5)
  }
}

struct AppleGlassSurface: ViewModifier {
  let cornerRadius: CGFloat
  let active: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(
        .clear.tint(active ? Color.indigo.opacity(0.1) : Color.white.opacity(0.02)),
        in: .rect(cornerRadius: cornerRadius)
      )
      .background(
        Color.black.opacity(active ? 0.26 : 0.2),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      content
        .background(
          .ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .background(
          active ? Color.indigo.opacity(0.07) : Color.white.opacity(0.018),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(hairline, lineWidth: 0.7))
    }
  }
}

struct GlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.55 : 0.78))
      .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.035), in: Capsule())
      .overlay(Capsule().stroke(hairline, lineWidth: 0.7))
  }
}

struct GoldButtonStyle: ButtonStyle {
  let active: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(ink)
      .background(accent.opacity(configuration.isPressed ? 0.75 : 0.96), in: Capsule())
      .shadow(color: accent.opacity(active ? 0.35 : 0.18), radius: active ? 14 : 8)
  }
}

struct MenuPanel: View {
  @ObservedObject var model: AudioModel
  @Environment(\.openWindow) private var openWindow
  @State private var isRenaming = false
  @State private var renameDraft = ""
  @State private var renameTrackID: Int?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("ASMEUL", systemImage: "waveform.path")
          .font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(accent)
        Spacer()
        Button {
          model.toggle()
        } label: {
          Image(systemName: model.running ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.plain).foregroundStyle(accent)
      }
      Text("\(model.selectedTrackCount)개의 소리").font(.caption).foregroundStyle(muted)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(model.catalog) { track in
            HStack(spacing: 8) {
              Toggle(
                track.name,
                isOn: Binding(
                  get: { model.tracks.first(where: { $0.id == track.id })?.enabled ?? false },
                  set: { _ in model.toggleTrack(track.id) })
              ).toggleStyle(.checkbox).tint(accent)
            }
            .contextMenu {
              if track.custom {
                Button("이름 변경") {
                  renameDraft = track.name
                  renameTrackID = track.id
                  isRenaming = true
                }
                Button("음원 삭제", role: .destructive) {
                  model.removeCustomSound(track.id)
                }
              }
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(height: 250)
      HStack {
        Spacer()
        Button("아스믈 열기") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
      }.font(.caption)
    }
    .padding(22)
    .frame(width: 310)
    .background(ink)
    .alert("음원 이름 변경", isPresented: $isRenaming) {
      TextField("이름", text: $renameDraft)
      Button("취소", role: .cancel) { renameTrackID = nil }
      Button("저장") {
        if let renameTrackID {
          model.renameCustomSound(renameTrackID, name: renameDraft)
        }
        self.renameTrackID = nil
      }
    } message: {
      Text("사용자 음원에 표시할 이름을 입력하세요.")
    }
  }
}
