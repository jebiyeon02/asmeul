import AppKit
import SwiftUI

@main struct ASMEULApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    Window("아스믈", id: "main") {
      ContentView(model: delegate.model).frame(width: 1080, height: 720).preferredColorScheme(.dark)
    }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
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
      AmbientFog()
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
        Text("\(model.selectedTrackCount)개의 소리").font(.system(size: 11, weight: .medium))
          .contentTransition(.numericText())
          .foregroundStyle(model.selectedTrackCount > 0 ? accent : muted)
      }
      Spacer()
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
          Image(systemName: setting.enabled ? "wave.3.right.circle.fill" : "circle")
            .font(.system(size: 18, weight: .light))
            .symbolEffect(.pulse.byLayer, options: .repeating, value: setting.enabled)
        }.foregroundStyle(setting.enabled ? accent : Color.white.opacity(0.78)).contentShape(
          Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("track-\(track.id)")
        .accessibilityLabel(track.name).accessibilityValue(setting.enabled ? "선택됨" : "선택 안 됨")
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
  }
}

struct BottomBar: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    HStack(spacing: 14) {
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
      }.buttonStyle(.plain).disabled(!model.assetsReady).accessibilityIdentifier("bottom-power")
      if let error = model.error {
        Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
      } else {
        HStack(spacing: 4) {
          ForEach(0..<8, id: \.self) { i in
            Capsule().fill(Double(model.peak) > Double(i) / 10 ? accent : Color.white.opacity(0.08))
              .frame(width: 3, height: 8)
          }
        }
      }
      Spacer()
      Toggle(
        "ASMR만", isOn: Binding(get: { model.music < 0.001 }, set: { model.music = $0 ? 0 : 1 })
      )
      .toggleStyle(.switch).controlSize(.mini).tint(accent).font(.system(size: 9))
      Divider().frame(height: 24).overlay(hairline)
      Image(systemName: "speaker.wave.2").foregroundStyle(muted)
      Slider(value: $model.gain, in: 0...1).frame(width: 105).tint(accent).accessibilityLabel(
        "출력 볼륨")
      Text("\(Int(model.gain * 100))%").font(.system(size: 8, design: .monospaced))
        .foregroundStyle(muted).frame(width: 30)
      Menu {
        Button("선택 모두 해제") { model.clearTracks() }
        Button("믹스 내보내기…") { model.exportPreset() }
        Button("믹스 가져오기…") { model.importPreset() }
        Divider()
        Button("아스믈 종료") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton).frame(width: 22)
      Divider().frame(height: 24).overlay(hairline)
      Button(model.bypass ? "믹스로 돌아가기" : "A/B 원음 비교") { model.bypass.toggle() }
        .buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundStyle(accent)
        .disabled(!model.running)
    }.padding(.horizontal, 14).frame(height: 58).glass(cornerRadius: 14)
  }
}

struct AmbientFog: View {
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 12, paused: scenePhase != .active)) { timeline in
      AmbientFogFrame(time: timeline.date.timeIntervalSinceReferenceDate)
    }.ignoresSafeArea().allowsHitTesting(false)
  }
}

private struct AmbientFogFrame: View {
  let time: TimeInterval

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        mesh
        fogLight(
          color: .indigo, opacity: 0.14, size: 500, blur: 135,
          x: -proxy.size.width * 0.28 + sin(time * 0.18) * 45,
          y: proxy.size.height * 0.3 + cos(time * 0.14) * 30)
        fogLight(
          color: .orange, opacity: 0.08, size: 390, blur: 120,
          x: proxy.size.width * 0.3 + cos(time * 0.13) * 40,
          y: -proxy.size.height * 0.3 + sin(time * 0.17) * 35)
      }
    }
  }

  @ViewBuilder private var mesh: some View {
    if #available(macOS 15.0, *) {
      MeshGradient(
        width: 3, height: 3,
        points: meshPoints,
        colors: [
          ink, Color(red: 0.08, green: 0.09, blue: 0.16), ink,
          Color(red: 0.04, green: 0.05, blue: 0.1),
          Color(red: 0.12, green: 0.1, blue: 0.2),
          Color(red: 0.12, green: 0.08, blue: 0.09), ink,
          Color(red: 0.07, green: 0.06, blue: 0.11), .black,
        ], smoothsColors: true)
    } else {
      LinearGradient(
        colors: [Color(red: 0.06, green: 0.065, blue: 0.08), ink, .black],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private var meshPoints: [SIMD2<Float>] {
    [
      .init(0, 0), .init(Float(0.5 + 0.05 * sin(time * 0.16)), 0), .init(1, 0),
      .init(0, 0.5),
      .init(
        Float(0.5 + 0.08 * cos(time * 0.12)),
        Float(0.5 + 0.06 * sin(time * 0.1))),
      .init(1, 0.5), .init(0, 1), .init(0.5, 1), .init(1, 1),
    ]
  }

  private func fogLight(
    color: Color, opacity: Double, size: CGFloat, blur: CGFloat, x: CGFloat, y: CGFloat
  ) -> some View {
    Circle().fill(color.opacity(opacity)).frame(width: size, height: size).blur(radius: blur)
      .offset(x: x, y: y)
  }
}

struct AdaptiveGlassContainer<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  @ViewBuilder var body: some View {
    if #available(macOS 26.0, *) {
      // Keep adjacent cards optically separate. A nonzero spacing lets Liquid Glass
      // morph neighboring shapes into one large surface, which is undesirable for
      // independently selectable sound cards.
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
        .regular.tint(active ? Color.indigo.opacity(0.13) : nil),
        in: .rect(cornerRadius: cornerRadius))
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
            Toggle(
              track.name,
              isOn: Binding(
                get: { model.tracks.first(where: { $0.id == track.id })?.enabled ?? false },
                set: { _ in model.toggleTrack(track.id) })
            ).toggleStyle(.checkbox).tint(accent)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(height: 250)
      HStack {
        Button("MP3 추가") { model.importSound() }
        Spacer()
        Button("아스믈 열기") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
      }.font(.caption)
    }.padding(22).frame(width: 310).background(ink)
  }
}
