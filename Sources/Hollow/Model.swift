import AppKit
import AudioCore
import Carbon
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

struct AudioProcess: Identifiable, Hashable {
  let id: UInt32
  let name: String
  let bundleID: String
}
struct SavedMood: Codable {
  var space, warmth, orbit, gain: Double
  var ambience: Double? = nil
  var music: Double? = nil
  var tracks: [TrackSetting]? = nil
  var spatial: Bool? = nil
  var theme: AmbientTheme? = nil
}

enum AmbientTheme: String, Codable, CaseIterable, Identifiable {
  case deepSea
  case aurora
  case spectral

  var id: String { rawValue }

  var title: String {
    switch self {
    case .deepSea: return "심해의 휴식"
    case .aurora: return "오로라"
    case .spectral: return "스펙트럴"
    }
  }

  var subtitle: String {
    switch self {
    case .deepSea: return "딥 네이비 · 시안"
    case .aurora: return "인디고 · 민트"
    case .spectral: return "플럼 · 웜 골드"
    }
  }
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
  @Published var spatial = true { didSet { configure() } }
  @Published var running = false
  @Published var bypass = false { didSet { configure() } }
  @Published var space = 0.28 { didSet { configure() } }
  @Published var warmth = 0.2 { didSet { configure() } }
  @Published var orbit = 0.0 { didSet { configure() } }
  @Published var gain = 0.7 { didSet { configure() } }
  @Published var ambience = 0.65 { didSet { configure() } }
  @Published var music = 1.0 { didSet { configure() } }
  @Published var theme: AmbientTheme = .deepSea { didSet { rememberMood() } }
  @Published var animationsEnabled: Bool =
    UserDefaults.standard.object(forKey: "animations.enabled") as? Bool ?? true {
    didSet { UserDefaults.standard.set(animationsEnabled, forKey: "animations.enabled") }
  }
  @Published var catalog = ASMRTrack.builtIn
  @Published var tracks = ASMRTrack.builtIn.map { TrackSetting(id: $0.id) } {
    didSet { configure() }
  }
  @Published var durations: [Int: Double] = [:]
  @Published var assetsReady = false
  @Published var selected: UInt32 = 0
  @Published var processes: [AudioProcess] = []
  @Published var peak: Float = 0
  @Published var outputName = "기본 출력 장치"
  @Published var status = "헤드폰을 쓰고, 좋아하는 음악을 재생하세요."
  @Published var error: String?
  @Published var rate: Double = 0
  @Published var callbackCount: UInt64 = 0
  private let engine = hollow_create()!
  private var monitorTimer: Timer?
  private var lastCallbacks: UInt64 = 0
  private var stalled = 0
  private var refreshTick = 0
  private var hotKey: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?
  private var observers: [NSObjectProtocol] = []
  private var memories: [String: SavedMood] = [:]
  var selectedTrackCount: Int { tracks.filter(\.enabled).count }
  var memoryKey: String { processes.first(where: { $0.id == selected })?.bundleID ?? "system" }
  var activeTrackIDs: Set<Int> { Set(tracks.filter(\.enabled).map(\.id)) }
  var rainActive: Bool { tracks.contains { ($0.id == 0 || $0.id == 1) && $0.enabled } }
  var fireActive: Bool { tracks.contains { ($0.id == 18 || $0.id == 19) && $0.enabled } }

  var savedMood: SavedMood {
    SavedMood(
      space: space, warmth: warmth, orbit: orbit, gain: gain, ambience: ambience, music: music,
      tracks: tracks, spatial: spatial, theme: theme)
  }
  func toggleTrack(_ id: Int) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    tracks[index].enabled.toggle()
    rememberMood()
  }
  func setTrackVolume(_ id: Int, _ value: Double) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    tracks[index].volume = value
  }
  func clearTracks() {
    for i in tracks.indices { tracks[i].enabled = false }
    rememberMood()
  }
  init() {
    loadCustomCatalog()
    if let data =
      (UserDefaults.standard.data(forKey: "mixes.v4") ?? UserDefaults.standard.data(forKey: "moods")),
      let saved = try? JSONDecoder().decode([String: SavedMood].self, from: data)
    {
      memories = saved
    }
    do {
      durations = try SoundLibrary.loadResources(into: engine)
      assetsReady = true
    } catch { self.error = "배경음 파일을 읽지 못했습니다: \(error.localizedDescription)" }
    for item in catalog where item.custom {
      do {
        durations[item.id] = try SoundLibrary.load(
          url: customSoundsDirectory.appendingPathComponent(item.file), slot: item.id, into: engine)
      } catch {
        self.error = "사용자 음원 \(item.name)을 읽지 못했습니다. 다시 추가해 주세요."
      }
    }
    refreshProcesses()
    restoreMood()
    updateOutput()
    monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
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
  func defaultDirection(_ id: Int) -> Int {
    [
      1, 2, 4, 1, 1, 2, 2, 3, 4, 3, 0, 6, 5, 4, 1, 2, 3, 3, 1, 2, 6, 0, 1, 2, 3, 4, 5, 6, 0, 1, 2,
      3,
    ][min(31, max(0, id))]
  }
  func setPosition(_ id: Int, direction: Int? = nil, distance: Double? = nil) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    if let direction { tracks[index].direction = direction }
    if let distance { tracks[index].distance = distance }
    rememberMood()
  }
  func configure() {
    let fade = 1.0
    hollow_configure(
      engine, Float(space * fade), Float(warmth * fade), Float(orbit * fade),
      Float(gain), bypass ? 1 : 0)
    hollow_spatial(engine, spatial ? 1 : 0)
    hollow_mix(engine, Float(ambience), Float(music), Float(fade))
    for track in tracks {
      hollow_position(
        engine, Int32(track.id), Int32(track.direction ?? defaultDirection(track.id)),
        Float(track.distance ?? 0.3))
      hollow_track_gain(engine, Int32(track.id), track.enabled ? Float(track.volume) : 0)
    }
  }

  func rememberMood() {
    memories[memoryKey] = savedMood
    if let data = try? JSONEncoder().encode(memories) {
      UserDefaults.standard.set(data, forKey: "mixes.v4")
    }
  }
  func restoreMood() {
    guard let value = memories[memoryKey] else {
      space = 0.28
      warmth = 0.2
      orbit = 0
      gain = 0.7
      ambience = 0.65
      music = 1
      theme = .deepSea
      tracks = catalog.map { TrackSetting(id: $0.id) }
      return
    }
    spatial = value.spatial ?? true
    theme = value.theme ?? .deepSea
    ambience = min(1, max(0, value.ambience ?? 0.65))
    music = min(1, max(0, value.music ?? 1))
    tracks = catalog.map { item in
      guard let stored = value.tracks?.first(where: { $0.id == item.id }), stored.volume.isFinite
      else { return TrackSetting(id: item.id) }
      return TrackSetting(
        id: item.id, enabled: stored.enabled, volume: min(1, max(0, stored.volume)),
        direction: min(6, max(0, stored.direction ?? defaultDirection(item.id))),
        distance: (stored.distance?.isFinite == true) ? min(1, max(0, stored.distance!)) : 0.3)
    }
    space = min(1, max(0, value.space))
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
  func toggle() { if running { stop() } else { start() } }
  func start() {
    guard assetsReady else { return }
    error = nil
    configure()
    if hollow_start(engine, selected) == 0 {
      running = true
      rate = hollow_sample_rate(engine)
      status = "선택한 ASMR을 함께 재생하고 있어요."
      lastCallbacks = 0
      stalled = 0
      updateOutput()
    } else {
      error =
        "오디오를 시작하지 못했습니다: \(String(cString:hollow_error(engine))). 시스템 설정에서 아스믈의 시스템 오디오 녹음 권한과 출력 장치를 확인하세요."
      running = false
    }
  }
  func stop(message: String = "효과를 껐습니다. 앱의 원래 소리로 재생됩니다.") {
    hollow_stop(engine)
    running = false
    peak = 0
    status = message
    rememberMood()
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
    if refreshTick % 12 == 0 {
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
    panel.nameFieldStringValue = "My Mix.asmeul.json"
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
      let levels: [Double] = [
        value.space, value.warmth, value.orbit, value.gain, value.ambience ?? 0.65,
        value.music ?? 1,
      ]
      let savedTracks = value.tracks ?? []
      guard levels.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
        savedTracks.count <= catalog.count,
        Set(savedTracks.map(\.id)).count == savedTracks.count,
        savedTracks.allSatisfy({ t in
          catalog.contains(where: { $0.id == t.id }) && t.volume.isFinite
            && (0...1).contains(t.volume)
        })
      else { throw CocoaError(.fileReadCorruptFile) }
      memories[memoryKey] = value
      restoreMood()
      rememberMood()
    } catch { self.error = "프리셋을 읽을 수 없습니다: \(error.localizedDescription)" }
  }
  var customSoundsDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Hollow/User Sounds", isDirectory: true)
  }
  private var customCatalogURL: URL { customSoundsDirectory.appendingPathComponent("catalog.json") }
  func loadCustomCatalog() {
    guard let data = try? Data(contentsOf: customCatalogURL),
      let saved = try? JSONDecoder().decode([ASMRTrack].self, from: data)
    else { return }
    var used = Set<Int>()
    let valid = saved.filter {
      (21..<32).contains($0.id) && $0.custom && used.insert($0.id).inserted
        && FileManager.default.fileExists(
          atPath: customSoundsDirectory.appendingPathComponent($0.file).path)
    }
    catalog.append(contentsOf: valid)
    tracks.append(contentsOf: valid.map { TrackSetting(id: $0.id) })
  }
  func importSound() {
    guard let slot = (21..<32).first(where: { id in !catalog.contains(where: { $0.id == id }) })
    else {
      error = "사용자 음원은 최대 11개까지 추가할 수 있습니다."
      return
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.mp3]
    panel.allowsMultipleSelection = false
    panel.message = "아스믈에 추가할 MP3를 선택하세요. 최대 길이는 60분입니다."
    guard panel.runModal() == .OK, let source = panel.url else { return }
    do {
      try FileManager.default.createDirectory(
        at: customSoundsDirectory, withIntermediateDirectories: true)
      let destination = customSoundsDirectory.appendingPathComponent("custom-\(slot).mp3")
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: source, to: destination)
      let duration = try SoundLibrary.load(url: destination, slot: slot, into: engine)
      let rawName = source.deletingPathExtension().lastPathComponent.trimmingCharacters(
        in: .whitespacesAndNewlines)
      let item = ASMRTrack(
        id: slot, name: rawName.isEmpty ? "사용자 음원 \(slot - 20)" : rawName,
        file: destination.lastPathComponent, symbol: "waveform", supplied: true, custom: true)
      catalog.append(item)
      tracks.append(TrackSetting(id: slot))
      durations[slot] = duration
      let custom = catalog.filter(\.custom)
      try JSONEncoder().encode(custom).write(to: customCatalogURL, options: .atomic)
      status = "\(item.name)을 추가했습니다."
      error = nil
    } catch let importError {
      self.error = "MP3를 추가하지 못했습니다: \(importError.localizedDescription)"
    }
  }
  func removeCustomSound(_ id: Int) {
    guard let index = catalog.firstIndex(where: { $0.id == id && $0.custom }) else { return }
    let item = catalog[index]
    let fileURL = customSoundsDirectory.appendingPathComponent(item.file)
    do {
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
    } catch {
      self.error = "\(item.name)을 삭제하지 못했습니다: \(error.localizedDescription)"
      return
    }

    // Stop the slot immediately before removing its UI and persisted catalog entry.
    hollow_track_gain(engine, Int32(id), 0)
    catalog.remove(at: index)
    tracks.removeAll { $0.id == id }
    durations.removeValue(forKey: id)

    do {
      try FileManager.default.createDirectory(
        at: customSoundsDirectory, withIntermediateDirectories: true)
      let custom = catalog.filter(\.custom)
      try JSONEncoder().encode(custom).write(to: customCatalogURL, options: .atomic)
      status = "\(item.name)을 삭제했습니다."
      error = nil
    } catch {
      self.error = "음원 목록을 저장하지 못했습니다: \(error.localizedDescription)"
    }
    rememberMood()
  }
  func shutdown() {
    stop()
    monitorTimer?.invalidate()
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    hollow_destroy(engine)
  }
}
