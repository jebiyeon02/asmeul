import AppKit
import SwiftUI

@main struct HollowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    Window("Hollow", id: "main") {
      ContentView(model: delegate.model).frame(width: 1000, height: 820).preferredColorScheme(.dark)
    }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
    MenuBarExtra("Hollow", systemImage: "waveform.path") {
      MenuPanel(model: delegate.model).preferredColorScheme(.dark)
    }.menuBarExtraStyle(.window)
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AudioModel()
  func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let ink = Color(red: 0.055, green: 0.065, blue: 0.08)
let accent = Color(red: 0.85, green: 0.73, blue: 0.52)
let muted = Color(red: 0.55, green: 0.57, blue: 0.59)

struct ContentView: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 28) {
        HStack(spacing: 9) {
          Image(systemName: "waveform.path").foregroundStyle(accent)
          Text("hollow").font(.system(size: 27, weight: .semibold, design: .rounded))
        }.padding(.top, 22)
        Text("MAKE ROOM\nFOR YOUR MUSIC.").font(.system(size: 10, weight: .medium)).tracking(2)
          .foregroundStyle(muted).lineSpacing(6)
        VStack(alignment: .leading, spacing: 8) {
          Label("공간 둘러보기", systemImage: "square.grid.2x2").foregroundStyle(accent).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(
              accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
          Text("음악은 그대로, 분위기는 새롭게.").font(.system(size: 10)).foregroundStyle(muted).padding(
            .horizontal, 8)
        }
        Spacer()
        VStack(alignment: .leading, spacing: 12) {
          Text("AUDIO SOURCE").font(.system(size: 9, weight: .semibold)).tracking(2)
            .foregroundStyle(muted)
          Picker("소스", selection: Binding(get: { model.selected }, set: { model.changeSource($0) }))
          {
            Text("전체 시스템").tag(UInt32(0))
            ForEach(model.processes) { Text($0.name).tag($0.id) }
          }.labelsHidden().frame(maxWidth: .infinity)
          Label(model.outputName, systemImage: "headphones").font(.system(size: 11))
            .foregroundStyle(muted).lineLimit(2)
        }
        Divider().overlay(.white.opacity(0.05))
        HStack {
          Circle().fill(model.running ? accent : muted).frame(width: 5, height: 5)
          Text(model.running ? "LIVE AUDIO" : "READY WHEN YOU ARE").font(
            .system(size: 8, weight: .medium)
          ).tracking(1)
        }.foregroundStyle(muted)
        Text("SOUNDSCAPES  /  0.3").font(.system(size: 8)).tracking(1.5).foregroundStyle(
          muted.opacity(0.6))
      }.padding(24).frame(width: 218).background(Color.white.opacity(0.018))
      Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text("나만의 공간에 들어오세요").font(.system(size: 21, weight: .medium))
              Text("어디서 듣든, 다른 곳에 있는 것처럼.").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            Button(action: { model.toggle() }) {
              HStack(spacing: 7) {
                Image(systemName: "power")
                Text(model.running ? "효과 끄기" : "효과 시작")
              }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(
                .vertical, 11
              ).background(model.running ? accent : Color.white.opacity(0.07), in: Capsule())
                .foregroundStyle(model.running ? ink : accent)
            }.buttonStyle(.plain).accessibilityIdentifier("power")
          }
          HStack(spacing: 12) {
            ForEach(Array(SpacePreset.all.suffix(2))) { preset in
              Button {
                model.selectPreset(preset.id)
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: preset.symbol).font(.system(size: 25, weight: .light))
                  VStack(alignment: .leading, spacing: 5) {
                    Text(preset.caption).font(.system(size: 14, weight: .medium))
                    Text(preset.id == 8 ? "비 · 책상 소리 · 먼 일본어 방송" : "풀벌레 · 바람 · 호수 · 작은 기억").font(
                      .system(size: 10))
                  }
                  Spacer(minLength: 0)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                  .foregroundStyle(model.preset == preset.id ? accent : muted)
                  .background(
                    accent.opacity(model.preset == preset.id ? 0.12 : 0.035),
                    in: RoundedRectangle(cornerRadius: 12)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(
                      accent.opacity(model.preset == preset.id ? 0.55 : 0.12)))
              }.buttonStyle(.plain).accessibilityIdentifier("featured-\(preset.id)")
            }
          }
          ZStack(alignment: .bottomLeading) {
            ArchitectureArt(orbit: model.orbit, active: model.running, scene: model.scene).frame(
              height: 170
            ).clipped()
            LinearGradient(colors: [.clear, ink.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
              VStack(alignment: .leading, spacing: 6) {
                Text("YOUR CURRENT SPACE").font(.system(size: 8, weight: .medium)).tracking(2.4)
                  .foregroundStyle(accent)
                Text(model.current.name).font(.system(size: 39, weight: .regular, design: .serif))
                Text(
                  model.scene == 0 ? model.current.caption : AmbienceScene.all[model.scene].detail
                ).font(
                  .system(size: 11)
                ).foregroundStyle(muted)
              }
              Spacer()
              Button {
                model.bypass.toggle()
              } label: {
                HStack(spacing: 5) {
                  Image(systemName: model.bypass ? "ear" : "waveform")
                  Text(model.bypass ? "원음 듣는 중" : "A/B 원음 비교")
                }.font(.system(size: 10)).padding(10).background(
                  .white.opacity(0.07), in: Capsule())
              }.buttonStyle(.plain).disabled(!model.running)
            }.padding(22)
          }.frame(height: 170).background(Color(red: 0.1, green: 0.105, blue: 0.11)).clipShape(
            RoundedRectangle(cornerRadius: 16)
          ).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.12)))
          HStack {
            Text("CHOOSE A SPACE").font(.system(size: 9, weight: .medium)).tracking(2)
            Spacer()
            Text("08 spaces").font(.system(size: 9, design: .monospaced))
          }.foregroundStyle(muted)
          HStack(spacing: 7) {
            ForEach(Array(SpacePreset.all.prefix(8))) { p in
              Button {
                model.selectPreset(p.id)
              } label: {
                VStack(spacing: 10) {
                  Image(systemName: p.symbol).font(.system(size: 20, weight: .light))
                  Text(p.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    .minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity).frame(height: 74).foregroundStyle(
                  model.preset == p.id ? accent : muted
                ).background(
                  model.preset == p.id ? accent.opacity(0.1) : Color.white.opacity(0.025),
                  in: RoundedRectangle(cornerRadius: 10)
                ).overlay(
                  RoundedRectangle(cornerRadius: 10).strokeBorder(
                    model.preset == p.id ? accent.opacity(0.45) : .white.opacity(0.05)))
              }.buttonStyle(.plain).help(p.caption)
            }
          }
          SoundscapePanel(model: model)
          HStack(spacing: 23) {
            control("Space", subtitle: "잔향의 깊이", value: $model.space, range: 0...0.65)
            control("Warmth", subtitle: "부드러운 음색", value: $model.warmth, range: 0...1)
            control("Orbit", subtitle: "천천히 좌우로", value: $model.orbit, range: 0...1)
          }.padding(17).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
          HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2").foregroundStyle(muted)
            Slider(value: $model.gain, in: 0...1).tint(accent).frame(width: 90).accessibilityLabel(
              "출력 볼륨")
            Text("\(Int(model.gain*100))%").font(.system(size: 10, design: .monospaced))
              .foregroundStyle(muted).frame(width: 28)
            Spacer()
            Menu {
              Button("사용 안 함") { model.setSleep(0) }
              ForEach([15, 30, 60], id: \.self) { n in Button("\(n)분 후 효과 끄기") { model.setSleep(n) }
              }
            } label: {
              Label(model.remaining.isEmpty ? "타이머" : model.remaining, systemImage: "moon.zzz")
            }.menuStyle(.borderlessButton).fixedSize().disabled(!model.running)
            Menu {
              Button("프리셋 내보내기…") { model.exportPreset() }
              Button("프리셋 가져오기…") { model.importPreset() }
              Divider()
              Button("Hollow 종료") { NSApp.terminate(nil) }
            } label: {
              Image(systemName: "ellipsis")
            }.menuStyle(.borderlessButton).frame(width: 24)
          }.font(.system(size: 10))
          HStack(alignment: .top, spacing: 8) {
            Circle().fill(model.error != nil ? Color.orange : accent.opacity(0.7)).frame(
              width: 5, height: 5
            ).padding(.top, 4)
            Text(model.error ?? model.status).font(.system(size: 10)).foregroundStyle(
              model.error != nil ? .orange : muted
            ).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("⌥ ⌘ H").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
          }
          HStack(spacing: 8) {
            ForEach(0..<14, id: \.self) { bar in
              RoundedRectangle(cornerRadius: 1).fill(
                Double(model.peak) > Double(bar) / 16 ? accent : Color.white.opacity(0.07)
              ).frame(width: 3, height: 8)
            }
            Text(
              model.running
                ? "\(Int(model.rate)) Hz · \(model.callbackCount) buffers"
                : "ON-DEVICE AUDIO · NO RECORDING"
            )
            .font(.system(size: 8, design: .monospaced)).foregroundStyle(muted)
          }.accessibilityElement(children: .ignore).accessibilityLabel("오디오 상태").accessibilityValue(
            "\(model.callbackCount) buffers, peak \(model.peak)")
          Spacer(minLength: 0)
        }.padding(.horizontal, 27).padding(.top, 38).padding(.bottom, 20)
      }
    }.background(ink).onDisappear { model.rememberMood() }
  }
  func control(
    _ title: String, subtitle: String, value: Binding<Double>, range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title).font(.system(size: 14, weight: .medium))
        Spacer()
        Text("\(Int(value.wrappedValue*100))").font(.system(size: 10, design: .monospaced))
          .foregroundStyle(accent)
      }
      Slider(value: value, in: range).tint(accent).accessibilityLabel(title)
      Text(subtitle).font(.system(size: 9)).foregroundStyle(muted)
    }
  }
}
struct ArchitectureArt: View {
  let orbit: Double, active: Bool
  var scene: Int = 0
  var body: some View {
    Canvas { ctx, size in
      if scene == 2 || scene == 3 || scene == 4 {
        for i in 0..<90 {
          let x = CGFloat((i * 137 + 41) % 997) / 997 * size.width
          let y = CGFloat((i * 83 + 17) % 179) / 179 * size.height
          var path = Path()
          path.move(to: CGPoint(x: x, y: y))
          path.addLine(to: CGPoint(x: x - 4, y: y + CGFloat(8 + i % 15)))
          ctx.stroke(
            path, with: .color(accent.opacity(0.08 + Double(i % 4) * 0.025)), lineWidth: 0.7)
        }
      }
      if scene == 5 {
        for i in 0..<17 {
          let y = size.height * 0.6 + CGFloat(i) * 5
          var p = Path()
          p.move(to: CGPoint(x: size.width * 0.48, y: y))
          p.addQuadCurve(
            to: CGPoint(x: size.width, y: y + 4), control: CGPoint(x: size.width * 0.77, y: y - 5))
          ctx.stroke(p, with: .color(accent.opacity(0.22 - Double(i) * 0.01)), lineWidth: 1)
        }
        ctx.fill(
          Path(ellipseIn: CGRect(x: size.width * 0.73, y: 25, width: 42, height: 42)),
          with: .color(accent.opacity(0.32)))
        return
      }
      if scene == 3 || scene == 4 {
        let rect = CGRect(x: size.width * 0.58, y: 30, width: 210, height: 105)
        ctx.stroke(
          Path(roundedRect: rect, cornerRadius: 12), with: .color(accent.opacity(0.5)), lineWidth: 1
        )
        for i in 0..<27 {
          let x = rect.minX + 14 + CGFloat(i) * 4
          var p = Path()
          p.move(to: CGPoint(x: x, y: rect.minY + 20))
          p.addLine(to: CGPoint(x: x, y: rect.maxY - 20))
          ctx.stroke(p, with: .color(accent.opacity(0.22)), lineWidth: 1)
        }
        ctx.stroke(
          Path(ellipseIn: CGRect(x: rect.maxX - 53, y: rect.minY + 27, width: 30, height: 30)),
          with: .color(accent.opacity(0.6)), lineWidth: 2)
        return
      }
      let center = CGPoint(x: size.width * 0.66, y: size.height * 0.72)
      for i in (0..<12).reversed() {
        let scale = CGFloat(i + 1) / 12
        let w = 40 + scale * size.width * 0.64
        let h = 60 + scale * 260
        let rect = CGRect(x: center.x - w / 2, y: center.y - h * 0.72, width: w, height: h)
        let path = Path(roundedRect: rect, cornerRadius: w / 2)
        ctx.stroke(path, with: .color(accent.opacity(0.08 + Double(12 - i) * 0.018)), lineWidth: 1)
      }
      for i in 0..<32 {
        let x = CGFloat(i) * size.width / 31
        var p = Path()
        p.move(to: CGPoint(x: x, y: size.height))
        p.addLine(to: center)
        ctx.stroke(p, with: .color(accent.opacity(0.045)), lineWidth: 0.6)
      }
      ctx.fill(
        Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 30, width: 6, height: 6)),
        with: .color(accent.opacity(active ? 1 : 0.5)))
    }.background(
      RadialGradient(
        colors: [accent.opacity(0.14), ink.opacity(0.1)], center: UnitPoint(x: 0.66, y: 0.6),
        startRadius: 0, endRadius: 250))
  }
}
struct MenuPanel: View {
  @ObservedObject var model: AudioModel
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("hollow").font(.system(size: 23, weight: .medium, design: .rounded))
        Spacer()
        Button(action: { model.toggle() }) {
          Image(systemName: "power").foregroundStyle(model.running ? accent : muted)
        }.buttonStyle(.plain)
      }
      Text(model.current.name).font(.system(size: 28, design: .serif)).foregroundStyle(accent)
      Picker("공간", selection: Binding(get: { model.preset }, set: { model.selectPreset($0) })) {
        ForEach(SpacePreset.all) { Text($0.name).tag($0.id) }
      }
      Picker("배경", selection: $model.scene) {
        ForEach(AmbienceScene.all) { Text($0.name).tag($0.id) }
      }
      HStack {
        Text("배경음")
        Slider(value: $model.ambience, in: 0...1).tint(accent)
      }
      Toggle(
        "배경만 듣기", isOn: Binding(get: { model.music < 0.001 }, set: { model.music = $0 ? 0 : 1 }))
      Toggle("원음 비교", isOn: $model.bypass).disabled(!model.running)
      Text(model.error ?? model.status).font(.caption).foregroundStyle(muted)
      HStack {
        Button("공간 둘러보기") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
        Spacer()
        Button("종료") { NSApp.terminate(nil) }
      }.font(.caption)
    }.padding(22).frame(width: 300).background(ink)
  }
}

struct SoundscapePanel: View {
  @ObservedObject var model: AudioModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("BE THERE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(
          accent)
        Spacer()
        Toggle(
          "배경만 듣기", isOn: Binding(get: { model.music < 0.001 }, set: { model.music = $0 ? 0 : 1 })
        )
        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 10))
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8)
      {
        ForEach(AmbienceScene.all) { scene in
          Button {
            model.scene = scene.id
          } label: {
            HStack(spacing: 6) {
              Image(systemName: scene.symbol)
              Text(scene.name)
            }
            .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(
              .vertical, 10
            )
            .foregroundStyle(model.scene == scene.id ? ink : muted)
            .background(
              model.scene == scene.id ? accent : Color.white.opacity(0.04),
              in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain).accessibilityIdentifier("scene-\(scene.id)")
        }
      }
      HStack(spacing: 20) {
        mixControl("음악", value: $model.music)
        mixControl("배경 소리", value: $model.ambience)
        mixControl("거리감", value: $model.distance)
      }
      if model.scene == 4 || model.scene == 5 {
        HStack(spacing: 20) {
          mixControl(model.scene == 4 ? "필기 · 키보드" : "방울 · 나무 소리", value: $model.details)
          if model.scene == 5 { mixControl("잔잔한 피아노", value: $model.piano) }
        }
      }
      HStack(spacing: 10) {
        Text(
          (model.scene == 3 || model.scene == 4)
            ? model.voiceStatus
            : model.scene == 0 ? "공간을 고르면 음악 없이도 배경 소리가 재생됩니다." : "실제 녹음 기반 · 스테레오 공간 · 부드러운 장면 전환"
        )
        .font(.system(size: 9)).foregroundStyle(muted)
        Spacer(minLength: 0)
        if model.scene == 3 || model.scene == 4 {
          Image(systemName: "mic").font(.system(size: 10)).foregroundStyle(accent)
          Slider(value: $model.voice, in: 0...1).frame(width: 70).tint(accent).accessibilityLabel(
            "일본어 방송")
        }
      }
    }.padding(16).background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.12)))
  }
  func mixControl(_ title: String, value: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text("\(Int(value.wrappedValue*100))%").monospacedDigit()
      }
      .font(.system(size: 10)).foregroundStyle(muted)
      Slider(value: value, in: 0...1).tint(accent).accessibilityLabel(title)
    }
  }
}
