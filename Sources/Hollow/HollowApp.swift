import AppKit
import SwiftUI

@main struct ASMEULApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    Window("아스믈", id: "main") {
      ContentView(model: delegate.model).frame(width: 1080, height: 720).preferredColorScheme(.dark)
    }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
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

let ink = Color(red: 0.035, green: 0.04, blue: 0.055)
let accent = Color(red: 0.93, green: 0.79, blue: 0.55)
let muted = Color.white.opacity(0.52)
let hairline = Color.white.opacity(0.1)
let directions = ["앞", "왼쪽 앞", "오른쪽 앞", "왼쪽 뒤", "오른쪽 뒤", "뒤", "위"]

struct ContentView: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    ZStack {
      AmbientFog(
        theme: model.theme,
        activeTrackIDs: model.activeTrackIDs,
        animationsEnabled: model.animationsEnabled)
      GeometryReader { proxy in
        let availableHeight = max(0, proxy.size.height - 36)
        let scrollHeight = max(180, availableHeight - 58 - 58 - 36)
        HStack(spacing: 22) {
          Sidebar(model: model).frame(height: availableHeight)
          VStack(spacing: 18) {
            header
            ScrollView {
              LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
              ) {
                ForEach(model.catalog) { track in TrackCard(model: model, track: track) }
              }.padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: scrollHeight)
            BottomBar(model: model)
          }
          .frame(maxWidth: .infinity, minHeight: availableHeight, maxHeight: availableHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ink)
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
            ? "현재 30fps로 부드러운 앰비언트 모션을 렌더링합니다."
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
      Spacer()
      Divider().overlay(hairline).padding(.bottom, 22)
      Text("AUDIO SOURCE").font(.system(size: 8, weight: .medium)).tracking(1.7)
        .foregroundStyle(muted).padding(.bottom, 9)
      Picker("소스", selection: Binding(get: { model.selected }, set: { model.changeSource($0) })) {
        Text("전체 시스템").tag(UInt32(0))
        ForEach(model.processes) { Text($0.name).tag($0.id) }
      }.labelsHidden().controlSize(.small)
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
  let track: ASMRTrack
  var setting: TrackSetting {
    model.tracks.first(where: { $0.id == track.id }) ?? TrackSetting(id: track.id)
  }
  var duration: String {
    let seconds = Int(model.durations[track.id] ?? 0)
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
          Text(duration).font(.system(size: 8, design: .monospaced)).foregroundStyle(muted)
          if model.animationsEnabled {
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
          Button("음원 삭제", role: .destructive) {
            model.removeCustomSound(track.id)
          }
        }
      }
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
        HStack(spacing: 4) {
          ForEach(0..<8, id: \.self) { i in
            Capsule().fill(Double(model.peak) > Double(i) / 10 ? accent : Color.white.opacity(0.08))
              .frame(width: 3, height: 8)
          }
        }
        .frame(width: 52, alignment: .leading)
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

      Button(model.bypass ? "믹스로 돌아가기" : "A/B 원음 비교") { model.bypass.toggle() }
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

  private static let timelineStart = Date()

  @ViewBuilder
  var body: some View {
    Group {
      if animationsEnabled {
        // A fixed periodic schedule keeps the field moving reliably. Only this single
        // background layer is scheduled; cards stay static.
        TimelineView(.periodic(from: Self.timelineStart, by: 1.0 / 30.0)) { timeline in
          AmbientFogFrame(
            time: timeline.date.timeIntervalSinceReferenceDate,
            theme: theme,
            activeTrackIDs: activeTrackIDs,
            animationsEnabled: true)
        }
      } else {
        // Do not schedule a timeline when the user disables motion. The static mesh
        // remains visible while Canvas and its display-link updates are removed.
        AmbientFogFrame(
          time: 0,
          theme: theme,
          activeTrackIDs: activeTrackIDs,
          animationsEnabled: false)
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
  let animationsEnabled: Bool

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
        if animationsEnabled {
          AmbientParticles(time: time, theme: theme, activeTrackIDs: activeTrackIDs)
        }
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
    Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: true) {
      context, size in
      let t = time.truncatingRemainder(dividingBy: 600)
      if rainActive { drawRain(&context, size: size, time: t) }
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
  private var customActive: Bool { activeTrackIDs.contains { $0 >= 21 } }

  private func fraction(_ value: Double) -> Double { value - floor(value) }
}

struct AdaptiveGlassContainer<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  @ViewBuilder var body: some View {
    if #available(macOS 26.0, *) {
      // Keep adjacent cards optically separate. Liquid Glass uses this spacing
      // threshold to decide when nearby shapes should morph together.
      GlassEffectContainer(spacing: 28) { content }
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
                Button("음원 삭제", role: .destructive) {
                  model.removeCustomSound(track.id)
                }
              }
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(height: 250)
      HStack {
        Button("MP3 추가") { model.importSound() }
        Spacer()
        SettingsLink {
          Image(systemName: "gearshape")
        }
        .accessibilityLabel("설정")
        Button("아스믈 열기") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
      }.font(.caption)
    }.padding(22).frame(width: 310).background(ink)
  }
}
