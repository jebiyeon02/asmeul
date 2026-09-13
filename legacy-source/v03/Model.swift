import AppKit
import AudioCore
import Carbon
import CoreAudio
import SwiftUI

struct SpacePreset: Identifiable {
  let id: Int, name: String, caption: String, symbol: String
  let space: Double, warmth: Double, orbit: Double
  static let all: [SpacePreset] = [
    .init(
      id: 0, name: "Cathedral", caption: "높고 깊은 울림", symbol: "building.columns", space: 0.28,
      warmth: 0.2, orbit: 0),
    .init(
      id: 1, name: "Cave", caption: "어둠 속 긴 여운", symbol: "mountain.2", space: 0.36, warmth: 0.48,
      orbit: 0.12),
    .init(
      id: 2, name: "Concert Hall", caption: "넓게 펼쳐지는 무대", symbol: "music.mic", space: 0.24,
      warmth: 0.1, orbit: 0),
    .init(
      id: 3, name: "Underwater", caption: "물결 아래 고요함", symbol: "water.waves", space: 0.22,
      warmth: 0.95, orbit: 0.15),
    .init(
      id: 4, name: "Rainy Room", caption: "포근하고 차분한 방", symbol: "cloud.rain", space: 0.18,
      warmth: 0.55, orbit: 0),
    .init(
      id: 5, name: "Space", caption: "끝없이 떠다니는 소리", symbol: "sparkles", space: 0.42, warmth: 0.25,
      orbit: 0.45),
    .init(
      id: 6, name: "Bedroom", caption: "가까이 머무는 소리", symbol: "moon", space: 0.08, warmth: 0.42,
      orbit: 0),
    .init(
      id: 7, name: "Tokyo Radio", caption: "비 내리는 밤의 작은 라디오", symbol: "radio", space: 0.10,
      warmth: 0.42, orbit: 0),
    .init(
      id: 8, name: "Tokyo Office", caption: "비 오는 도쿄 사무실", symbol: "building.2.crop.circle",
      space: 0.12, warmth: 0.25, orbit: 0),
    .init(
      id: 9, name: "Twilight Lake", caption: "황혼의 호숫가", symbol: "sun.horizon", space: 0.2,
      warmth: 0.25, orbit: 0),
  ]
}
struct AudioProcess: Identifiable, Hashable {
  let id: UInt32
  let name: String
  let bundleID: String
}
struct SavedMood: Codable {
  var preset: Int
  var space, warmth, orbit, gain: Double
  var scene: Int? = nil
  var ambience: Double? = nil
  var music: Double? = nil
  var distance: Double? = nil
  var voice: Double? = nil
  var details: Double? = nil
  var piano: Double? = nil
}

func property<T: FixedWidthInteger>(
  _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T
) -> T? {
  var value = initial
  var size = UInt32(MemoryLayout<T>.size)
  var address = AudioObjectPropertyAddress(
    mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
    return nil
  }
  return value
}

func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
  var value: Unmanaged<CFString>?
  var size = UInt32(MemoryLayout.size(ofValue: value))
  var address = AudioObjectPropertyAddress(
    mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
    return nil
  }
  return value?.takeRetainedValue() as String?
}

@MainActor final class AudioModel: ObservableObject {
  @Published var running = false
  @Published var bypass = false { didSet { configure() } }
  @Published var preset = 0
  @Published var space = 0.28 { didSet { configure() } }
  @Published var warmth = 0.2 { didSet { configure() } }
  @Published var orbit = 0.0 { didSet { configure() } }
  @Published var gain = 0.7 { didSet { configure() } }
  @Published var scene = 0 { didSet { configure() } }
  @Published var ambience = 0.65 { didSet { configure() } }
  @Published var music = 1.0 { didSet { configure() } }
  @Published var distance = 0.3 { didSet { configure() } }
  @Published var details = 0.45 { didSet { configure() } }
  @Published var piano = 0.18 { didSet { configure() } }
  @Published var voice = 0.35 { didSet { configure() } }
  @Published var voiceStatus = "일본어 방송 음성 준비 중"
  @Published var assetsReady = false
  private let voiceBuilder = RadioVoiceBuilder()
  @Published var selected: UInt32 = 0
  @Published var processes: [AudioProcess] = []
  @Published var peak: Float = 0
  @Published var outputName = "기본 출력 장치"
  @Published var status = "헤드폰을 쓰고, 좋아하는 음악을 재생하세요."
  @Published var error: String?
  @Published var rate: Double = 0
  @Published var callbackCount: UInt64 = 0
  @Published var sleepMinutes = 0
  @Published var remaining = ""
  private let engine = hollow_create()!
  private var timer: Timer?
  private var sleepDeadline: Date?
  private var lastCallbacks: UInt64 = 0
  private var stalled = 0
  private var refreshTick = 0
  private var hotKey: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?
  private var observers: [NSObjectProtocol] = []
  private var memories: [String: SavedMood] = [:]
  var current: SpacePreset { SpacePreset.all[preset] }
  var memoryKey: String { processes.first(where: { $0.id == selected })?.bundleID ?? "system" }

  var savedMood: SavedMood {
    SavedMood(
      preset: preset, space: space, warmth: warmth, orbit: orbit, gain: gain, scene: scene,
      ambience: ambience, music: music, distance: distance, voice: voice, details: details,
      piano: piano)
  }
  init() {
    if let data = UserDefaults.standard.data(forKey: "moods"),
      let saved = try? JSONDecoder().decode([String: SavedMood].self, from: data)
    {
      memories = saved
    }
    do {
      try SoundLibrary.loadResources(into: engine)
      assetsReady = true
    } catch { self.error = "배경음 파일을 읽지 못했습니다: \(error.localizedDescription)" }
    voiceBuilder.build(
      deliver: { [weak self] slot, samples, rate in
        guard let self else { return }
        samples.withUnsafeBufferPointer { pointer in
          _ = hollow_load_sound(
            self.engine, Int32(slot), pointer.baseAddress, UInt32(samples.count / 2), rate)
        }
      }, status: { [weak self] in self?.voiceStatus = $0 })
    refreshProcesses()
    restoreMood()
    updateOutput()
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in self?.stop(message: "Mac이 잠자기에 들어가 효과를 껐습니다.") }
      })
    // Carbon hot keys do not require Accessibility or input monitoring permission.
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, data in
        guard let data else { return OSStatus(eventNotHandledErr) }
        let model = Unmanaged<AudioModel>.fromOpaque(data).takeUnretainedValue()
        Task { @MainActor in model.toggle() }
        return noErr
      }, 1, &eventType, pointer, &hotKeyHandler)
    let result = RegisterEventHotKey(
      UInt32(kVK_ANSI_H), UInt32(optionKey | cmdKey), EventHotKeyID(signature: 0x484F_4C4C, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    if result != noErr { status = "⌥⌘H 단축키가 다른 앱에서 사용 중입니다. 화면 버튼으로 시작하세요." }
  }
  func configure() {
    let fade: Double
    if let deadline = sleepDeadline {
      fade = min(1, max(0, deadline.timeIntervalSinceNow / 15))
    } else {
      fade = 1
    }
    hollow_configure(
      engine, Int32(preset), Float(space * fade), Float(warmth * fade), Float(orbit * fade),
      Float(gain), bypass ? 1 : 0)
    hollow_soundscape(
      engine, Int32(scene), Float(ambience), Float(music), Float(distance), Float(voice),
      Float(fade))
    hollow_scene_layers(engine, Float(details), Float(piano))
  }
  func rememberMood() {
    memories[memoryKey] = savedMood
    if let data = try? JSONEncoder().encode(memories) {
      UserDefaults.standard.set(data, forKey: "moods")
    }
  }
  func restoreMood() {
    guard let value = memories[memoryKey] else {
      selectPreset(0)
      return
    }
    preset = min(9, max(0, value.preset))
    scene = min(5, max(0, value.scene ?? (preset == 1 ? 1 : preset == 4 ? 2 : preset == 7 ? 3 : 0)))
    ambience = min(1, max(0, value.ambience ?? 0.65))
    music = min(1, max(0, value.music ?? 1))
    distance = min(1, max(0, value.distance ?? 0.3))
    voice = min(1, max(0, value.voice ?? 0.35))
    details = min(1, max(0, value.details ?? 0.45))
    piano = min(1, max(0, value.piano ?? 0.18))
    space = min(0.65, max(0, value.space))
    warmth = min(1, max(0, value.warmth))
    orbit = min(1, max(0, value.orbit))
    gain = min(1, max(0, value.gain))
    configure()
  }
  func changeSource(_ id: UInt32) {
    rememberMood()
    stop(message: "소스를 변경했습니다.")
    selected = id
    restoreMood()
  }
  func selectPreset(_ id: Int) {
    let p = SpacePreset.all[id]
    preset = id
    scene = id == 1 ? 1 : id == 4 ? 2 : id == 7 ? 3 : id == 8 ? 4 : id == 9 ? 5 : 0
    if id >= 7 { music = 0 } else { music = 1 }
    if id >= 7 {
      ambience = 0.65
      distance = 0.35
      voice = 0.35
      details = 0.45
      piano = 0.18
    }
    space = p.space
    warmth = p.warmth
    orbit = p.orbit
    configure()
  }
  func toggle() { if running { stop() } else { start() } }
  func start() {
    guard assetsReady else { return }
    error = nil
    configure()
    if hollow_start(engine, selected) == 0 {
      running = true
      rate = hollow_sample_rate(engine)
      status = "음악과 공간의 소리를 함께 듣고 있어요."
      lastCallbacks = 0
      stalled = 0
      updateOutput()
    } else {
      error =
        "오디오를 시작하지 못했습니다: \(String(cString:hollow_error(engine))). 시스템 설정에서 Hollow의 시스템 오디오 녹음 권한과 출력 장치를 확인하세요."
      running = false
    }
  }
  func stop(message: String = "효과를 껐습니다. 앱의 원래 소리로 재생됩니다.") {
    hollow_stop(engine)
    running = false
    peak = 0
    status = message
    sleepDeadline = nil
    sleepMinutes = 0
    remaining = ""
    rememberMood()
  }
  func setSleep(_ minutes: Int) {
    sleepMinutes = minutes
    sleepDeadline = minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil
    remaining = ""
  }
  func updateOutput() {
    if let device: UInt32 = property(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
      initial: UInt32(0)),
      let name = stringProperty(device, kAudioObjectPropertyName)
    {
      outputName = name
    }
  }
  func sampleRateForOutput() -> Double? {
    var value = 0.0
    var size = UInt32(MemoryLayout<Double>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(hollow_output_device(engine), &address, 0, nil, &size, &value)
        == noErr
    else { return nil }
    return value
  }
  func tick() {
    refreshTick += 1
    if refreshTick % 30 == 0 {
      refreshProcesses()
      updateOutput()
    }
    guard running else { return }
    peak = max(hollow_peak(engine), peak * 0.85)
    let callbacks = hollow_callbacks(engine)
    callbackCount = callbacks
    if callbacks == lastCallbacks { stalled += 1 } else { stalled = 0 }
    lastCallbacks = callbacks
    if stalled > 40 {
      stop(message: "오디오 신호 경로가 응답하지 않아 원음으로 복구했습니다.")
      error = "권한 또는 출력 장치를 확인하고 다시 시작하세요."
      return
    }
    if let output: UInt32 = property(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
      initial: UInt32(0)), output != hollow_output_device(engine)
    {
      stop(message: "출력 장치가 바뀌어 원음으로 복구했습니다. 새 장치에서 다시 시작하세요.")
      updateOutput()
      return
    }
    if let sampleRate: Double = sampleRateForOutput(), sampleRate != rate {
      stop(message: "출력 샘플레이트가 바뀌어 효과를 껐습니다. 다시 시작하세요.")
      return
    }
    if selected != 0 && !processes.contains(where: { $0.id == selected }) {
      stop(message: "선택한 앱이 종료되어 효과를 껐습니다.")
      selected = 0
      return
    }
    if let deadline = sleepDeadline {
      let seconds = max(0, Int(deadline.timeIntervalSinceNow))
      remaining = String(format: "%02d:%02d", seconds / 60, seconds % 60)
      configure()
      if seconds == 0 { stop(message: "타이머가 끝나 효과를 껐습니다. 음악 재생은 계속됩니다.") }
    }
  }
  func refreshProcesses() {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return }
    var ids = [UInt32](repeating: 0, count: Int(size) / 4)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return }
    processes = ids.compactMap { id in
      guard let pid: Int32 = property(id, kAudioProcessPropertyPID, initial: Int32(0)),
        pid != getpid(),
        let bundle = stringProperty(id, kAudioProcessPropertyBundleID)
      else { return nil }
      let app = NSRunningApplication(processIdentifier: pid)
      let name =
        app?.localizedName ?? (bundle as String).split(separator: ".").last.map(String.init)
        ?? "Audio process"
      return AudioProcess(
        id: id, name: name, bundleID: (bundle as String).isEmpty ? "pid-\(pid)" : bundle as String)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
  func exportPreset() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(current.name).hollow.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(
        savedMood
      ).write(to: url, options: .atomic)
    } catch { self.error = error.localizedDescription }
  }
  func importPreset() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      guard data.count < 65536 else { throw CocoaError(.fileReadTooLarge) }
      let value = try JSONDecoder().decode(SavedMood.self, from: data)
      let layerValues: [Double] = [
        value.ambience ?? 0.65, value.music ?? 1.0, value.distance ?? 0.3, value.voice ?? 0.35,
        value.details ?? 0.45, value.piano ?? 0.18,
      ]
      guard (0...9).contains(value.preset),
        (0...5).contains(value.scene ?? 0),
        layerValues.allSatisfy({ $0.isFinite && (0.0...1.0).contains($0) }),
        [value.space, value.warmth, value.orbit, value.gain].allSatisfy({
          $0.isFinite && (0...1).contains($0)
        }), value.space <= 0.65
      else { throw CocoaError(.fileReadCorruptFile) }
      memories[memoryKey] = value
      restoreMood()
      rememberMood()
    } catch { self.error = "프리셋을 읽을 수 없습니다: \(error.localizedDescription)" }
  }
  func shutdown() {
    voiceBuilder.cancel()
    stop()
    timer?.invalidate()
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    hollow_destroy(engine)
  }
}
