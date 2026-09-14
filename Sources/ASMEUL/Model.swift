import AppKit
import AudioCore
import Carbon
import CoreAudio
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let sourceLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "studio.asmeul", category: "AudioSource")

struct EnvironmentPhoto: Identifiable, Hashable, Codable {
  let id: String
  let title: String
  let subtitle: String
  let fileName: String

  static let library: [EnvironmentPhoto] = [
    EnvironmentPhoto(
      id: "earth-orbit", title: "지구 궤도", subtitle: "EARTH ORBIT",
      fileName: "environment-earth-orbit.jpg"),
    EnvironmentPhoto(
      id: "earth-night", title: "지구의 밤", subtitle: "EARTH AT NIGHT",
      fileName: "environment-earth-night.jpg"),
    EnvironmentPhoto(
      id: "snowy-cafe", title: "눈 내리는 카페", subtitle: "SNOWY CAFE",
      fileName: "environment-snowy-cafe.jpg"),
    EnvironmentPhoto(
      id: "sunset-camp", title: "황혼의 캠프", subtitle: "SUNSET CAMP",
      fileName: "environment-sunset-camp.jpg"),
    EnvironmentPhoto(
      id: "river-valley", title: "강가의 계곡", subtitle: "RIVER VALLEY",
      fileName: "environment-river-valley.jpg"),
  ]
}

struct SavedMood: Codable {
  var space, warmth, orbit, gain: Double
  var ambience: Double? = nil
  var music: Double? = nil
  var tracks: [TrackSetting]? = nil
  var spatial: Bool? = nil
  var theme: AmbientTheme? = nil
  var environmentID: String? = nil
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
  @Published var waitingForMusic = false
  @Published var bypass = false { didSet { configure() } }
  @Published var space = 0.28 { didSet { configure() } }
  @Published var warmth = 0.2 { didSet { configure() } }
  @Published var orbit = 0.0 { didSet { configure() } }
  @Published var gain = 0.7 { didSet { configure() } }
  @Published var ambience = 0.65 { didSet { configure() } }
  @Published var music = 1.0 { didSet { configure() } }
  @Published var focusMode = false
  @Published var environmentID = EnvironmentPhoto.library[0].id
  @Published var theme: AmbientTheme = .deepSea { didSet { rememberMood() } }
  @Published var animationsEnabled: Bool =
    UserDefaults.standard.object(forKey: "animations.enabled") as? Bool ?? true {
    didSet { UserDefaults.standard.set(animationsEnabled, forKey: "animations.enabled") }
  }
  @Published var catalog = ASMRTrack.builtIn
  @Published var tracks = ASMRTrack.builtIn.map { TrackSetting(id: $0.id) } {
    didSet { configureTracks(previous: oldValue) }
  }
  @Published var durations: [Int: Double] = [:]
  @Published var assetsReady = true
  @Published private(set) var loadingTracks: Set<Int> = []
  @Published private(set) var importingSound = false
  @Published var selected: UInt32 = 0
  @Published var processes: [AudioProcess] = []
  let meter = AudioMeter()
  @Published var outputName = "기본 출력 장치"
  @Published var status = "헤드폰을 쓰고, 좋아하는 음악을 재생하세요."
  @Published var error: String?
  private var rate: Double = 0
  private let engine = asmeul_create()!
  private var monitorTimer: Timer?
  private var lastCallbacks: UInt64 = 0
  private var stalled = 0
  private let soundLoader = SoundLoader()
  private var soundTasks: [Int: Task<Void, Never>] = [:]
  private var loadGenerations: [Int: UUID] = [:]
  private var loadedTracks: Set<Int> = []
  private var evictionTasks: [Int: DispatchWorkItem] = [:]
  private var metadataTask: Task<Void, Never>?
  private var importTask: Task<Void, Never>?
  private var shuttingDown = false
  private var pendingSourceRefresh: DispatchWorkItem?
  private var sourceRetryWorkItem: DispatchWorkItem?
  private var sourceRetryAttempt = 0
  private let sourceRetryDelays: [TimeInterval] = [0.15, 0.4, 0.8, 1.5]
  private var hardwareListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var capturedProcessIDs: [UInt32] = []
  private var captureWaitTicks = 0
  private var hotKey: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?
  private var observers: [NSObjectProtocol] = []
  private var memories: [String: SavedMood] = [:]
  private var pendingMoodSave: DispatchWorkItem?
  private var restoringMood = false
  var playbackActive: Bool { running || waitingForMusic }
  var selectedTrackCount: Int { tracks.reduce(0) { $0 + ($1.enabled ? 1 : 0) } }
  var memoryKey: String { processes.first(where: { $0.id == selected })?.bundleID ?? "system" }
  var activeTrackIDs: Set<Int> { Set(tracks.filter(\.enabled).map(\.id)) }
  var selectedEnvironment: EnvironmentPhoto {
    EnvironmentPhoto.library.first(where: { $0.id == environmentID })
      ?? EnvironmentPhoto.library[0]
  }
  var rainActive: Bool { tracks.contains { ($0.id == 0 || $0.id == 1) && $0.enabled } }
  var fireActive: Bool { tracks.contains { ($0.id == 18 || $0.id == 19) && $0.enabled } }

  var savedMood: SavedMood {
    SavedMood(
      space: space, warmth: warmth, orbit: orbit, gain: gain, ambience: ambience, music: music,
      tracks: tracks, spatial: spatial, theme: theme, environmentID: environmentID)
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
    var updated = tracks
    for i in updated.indices { updated[i].enabled = false }
    tracks = updated
    rememberMood()
  }
  func selectEnvironment(_ id: String) {
    guard EnvironmentPhoto.library.contains(where: { $0.id == id }) else { return }
    environmentID = id
    rememberMood()
  }
  init() {
    migrateLegacyData()
    animationsEnabled =
      UserDefaults.standard.object(forKey: "animations.enabled") as? Bool ?? true
    loadCustomCatalog()
    if let data =
      (UserDefaults.standard.data(forKey: "mixes.v4") ?? UserDefaults.standard.data(forKey: "moods")),
      let saved = try? JSONDecoder().decode([String: SavedMood].self, from: data)
    {
      memories = saved
    }
    let urls = Dictionary(uniqueKeysWithValues: catalog.compactMap { item in
      soundURL(item).map { (item.id, $0) }
    })
    let loader = soundLoader
    metadataTask = Task(priority: .utility) { [weak self] in
      let values = await loader.metadata(urls)
      guard !Task.isCancelled, let self, !self.shuttingDown else { return }
      self.durations.merge(values) { current, _ in current }
    }
    refreshProcesses()
    restoreMood()
    updateOutput()
    installHardwareListeners()
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in Task { @MainActor in self?.stop(message: "Mac이 잠자기에 들어가 효과를 껐습니다.") }
      })
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.scheduleSourceRefresh() }
      })
    }
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
      3, 4, 5, 1, 3,
    ][min(35, max(0, id))]
  }
  func setPosition(_ id: Int, direction: Int? = nil, distance: Double? = nil) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    var updated = tracks[index]
    if let direction { updated.direction = direction }
    if let distance { updated.distance = distance }
    tracks[index] = updated
    rememberMood()
  }
  func configure() {
    guard !restoringMood else { return }
    let fade = 1.0
    asmeul_configure(
      engine, Float(space * fade), Float(warmth * fade), Float(orbit * fade),
      Float(gain), bypass ? 1 : 0)
    asmeul_spatial(engine, spatial ? 1 : 0)
    asmeul_mix(engine, Float(ambience), Float(music), Float(fade))
  }

  private func configureTracks(previous: [TrackSetting] = []) {
    guard !restoringMood else { return }
    let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
    for track in tracks where old[track.id] != track {
      asmeul_position(
        engine, Int32(track.id), Int32(track.direction ?? defaultDirection(track.id)),
        Float(track.distance ?? 0.3))
      asmeul_track_gain(engine, Int32(track.id), track.enabled ? Float(track.volume) : 0)
      if track.enabled { requestSound(track.id) }
      else { releaseSoundLater(track.id) }
    }
  }

  private func soundURL(_ item: ASMRTrack) -> URL? {
    item.custom ? customSoundsDirectory.appendingPathComponent(item.file)
      : try? SoundLibrary.resourceURL(for: item)
  }

  private func requestSound(_ id: Int) {
    evictionTasks.removeValue(forKey: id)?.cancel()
    guard !shuttingDown, !loadedTracks.contains(id), soundTasks[id] == nil,
      let item = catalog.first(where: { $0.id == id }), let url = soundURL(item) else { return }
    let generation = UUID()
    loadGenerations[id] = generation
    loadingTracks.insert(id)
    let loader = soundLoader
    soundTasks[id] = Task(priority: .utility) { [weak self] in
      do {
        let prepared = try await loader.prepare(url: url, slot: id)
        guard !Task.isCancelled, let self, !self.shuttingDown,
          self.loadGenerations[id] == generation else { return }
        guard prepared.install(into: self.engine) else { throw CocoaError(.fileReadCorruptFile) }
        self.loadedTracks.insert(id)
        self.durations[id] = prepared.duration
        self.finishLoading(id)
      } catch {
        guard !Task.isCancelled, let self, !self.shuttingDown,
          self.loadGenerations[id] == generation else { return }
        self.finishLoading(id)
        self.error = "\(item.name)을 준비하지 못했습니다: \(error.localizedDescription)"
        if let index = self.tracks.firstIndex(where: { $0.id == id }) {
          self.tracks[index].enabled = false
        }
      }
    }
  }

  private func finishLoading(_ id: Int) {
    soundTasks.removeValue(forKey: id)
    loadGenerations.removeValue(forKey: id)
    loadingTracks.remove(id)
  }

  private func releaseSoundLater(_ id: Int) {
    soundTasks.removeValue(forKey: id)?.cancel()
    loadGenerations.removeValue(forKey: id)
    loadingTracks.remove(id)
    evictionTasks.removeValue(forKey: id)?.cancel()
    guard loadedTracks.contains(id) else { return }
    // Let the existing 40 ms gain smoother fade out before unpublishing PCM.
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.shuttingDown,
        !self.tracks.contains(where: { $0.id == id && $0.enabled }) else { return }
      asmeul_unload_sound(self.engine, Int32(id))
      self.loadedTracks.remove(id)
      self.evictionTasks.removeValue(forKey: id)
    }
    evictionTasks[id] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + (running ? 0.75 : 0), execute: work)
  }

  private func startMonitor() {
    monitorTimer?.invalidate()
    monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    monitorTimer?.tolerance = 0.05
  }

  private func installHardwareListeners() {
    for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
      var address = AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
      let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in self?.scheduleSourceRefresh() }
      }
      if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
        hardwareListeners.append((AudioObjectID(kAudioObjectSystemObject), address, listener))
      }
    }
  }

  private func scheduleSourceRefresh() {
    guard !shuttingDown else { return }
    // Coalesce the bursts generated by starting/stopping an aggregate device.
    guard pendingSourceRefresh == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.shuttingDown else { return }
      self.pendingSourceRefresh = nil
      self.refreshProcesses()
      self.updateOutput()
      if self.waitingForMusic && !self.running {
        self.startWhenSourceIsReady()
      } else {
        self.tick()
      }
    }
    pendingSourceRefresh = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  func rememberMood() {
    guard !restoringMood else { return }
    memories[memoryKey] = savedMood
    pendingMoodSave?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.flushMoodSave() }
    pendingMoodSave = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
  }

  private func flushMoodSave() {
    pendingMoodSave?.cancel()
    pendingMoodSave = nil
    if let data = try? JSONEncoder().encode(memories) {
      UserDefaults.standard.set(data, forKey: "mixes.v4")
    }
  }
  func restoreMood() {
    restoringMood = true
    defer {
      restoringMood = false
      configure()
      configureTracks()
    }
    guard let value = memories[memoryKey] else {
      space = 0.28
      warmth = 0.2
      orbit = 0
      gain = 0.7
      ambience = 0.65
      music = 1
      theme = .deepSea
      environmentID = EnvironmentPhoto.library[0].id
      tracks = catalog.map { TrackSetting(id: $0.id) }
      return
    }
    spatial = value.spatial ?? true
    theme = value.theme ?? .deepSea
    environmentID = EnvironmentPhoto.library.contains(where: { $0.id == value.environmentID })
      ? (value.environmentID ?? EnvironmentPhoto.library[0].id)
      : EnvironmentPhoto.library[0].id
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
  }
  func changeSource(_ id: UInt32) {
    guard selected != id else { return }
    let resume = running || waitingForMusic
    rememberMood()
    stop(message: "소스를 변경했습니다.")
    selected = id
    // A music input change must preserve the ASMR selection and mix volumes.
    if music < 0.001 {
      // Every source, including the whole system, explicitly enables music.
      music = 1
      status = "\(processes.first(where: { $0.id == id })?.name ?? "전체 시스템") 음악 입력을 켰습니다."
    }
    rememberMood()
    if resume { start() }
  }
  func toggle() { if running || waitingForMusic { stop() } else { start() } }
  func toggleFocusMode() { focusMode.toggle() }
  func start() {
    cancelSourceRetry()
    sourceRetryAttempt = 0
    startWhenSourceIsReady()
  }

  private func startWhenSourceIsReady() {
    guard assetsReady else { return }
    error = nil
    refreshProcesses()

    let processIDs: [UInt32]
    switch resolveAudioSource(selected: selected, sources: processes) {
    case .system:
      processIDs = []
    case .missingApplication:
      cancelSourceRetry()
      waitingForMusic = false
      error = "선택한 앱이 종료되었습니다. 다른 소스를 선택하세요."
      return
    case .waitingForProcesses:
      waitForSelectedSource()
      return
    case .processes(let ids):
      processIDs = ids
    }

    cancelSourceRetry()
    sourceRetryAttempt = 0
    waitingForMusic = false
    configure()
    configureTracks()
    let idText = processIDs.map { String($0) }.joined(separator: ",")
    sourceLogger.info(
      "starting selectedPid=\(self.selected, privacy: .public) coreAudioObjectIDs=[\(idText, privacy: .public)]")
    let result = selected == 0 ? asmeul_start(engine, 0) : processIDs.withUnsafeBufferPointer {
      asmeul_start_processes(engine, $0.baseAddress, UInt32($0.count))
    }
    if result == 0 {
      capturedProcessIDs = processIDs
      captureWaitTicks = 0
      waitingForMusic = false
      running = true
      startMonitor()
      rate = asmeul_sample_rate(engine)
      status = "음악 입력을 확인하고 있어요. 원음과 ASMR을 함께 재생합니다."
      lastCallbacks = 0
      stalled = 0
      updateOutput()
    } else {
      waitingForMusic = false
      error =
        "오디오를 시작하지 못했습니다: \(String(cString:asmeul_error(engine))). 시스템 설정에서 아스믈의 시스템 오디오 녹음 권한과 출력 장치를 확인하세요."
      running = false
    }
  }

  private func waitForSelectedSource() {
    running = false
    waitingForMusic = true
    capturedProcessIDs = []
    let sourceName = processes.first(where: { $0.id == selected })?.name ?? "선택한 앱"
    status = "\(sourceName) 음악 입력 대기 중 · 원음 유지"
    sourceLogger.info(
      "waiting selectedPid=\(self.selected, privacy: .public) coreAudioObjectIDs=[] attempt=\(self.sourceRetryAttempt, privacy: .public)")

    guard sourceRetryWorkItem == nil, sourceRetryAttempt < sourceRetryDelays.count else { return }
    let delay = sourceRetryDelays[sourceRetryAttempt]
    sourceRetryAttempt += 1
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.shuttingDown, self.waitingForMusic, !self.running else { return }
      self.sourceRetryWorkItem = nil
      self.startWhenSourceIsReady()
    }
    sourceRetryWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func cancelSourceRetry() {
    sourceRetryWorkItem?.cancel()
    sourceRetryWorkItem = nil
  }

  private func rebuildForChangedSource() {
    let source = processes.first(where: { $0.id == selected })
    let idText = source?.processIDs.map { String($0) }.joined(separator: ",") ?? ""
    sourceLogger.info(
      "rebuilding selectedPid=\(self.selected, privacy: .public) coreAudioObjectIDs=[\(idText, privacy: .public)]")
    asmeul_stop(engine)
    monitorTimer?.invalidate()
    monitorTimer = nil
    running = false
    capturedProcessIDs = []
    meter.reset()
    cancelSourceRetry()
    sourceRetryAttempt = 0
    startWhenSourceIsReady()
  }

  func stop(message: String = "효과를 껐습니다. 앱의 원래 소리로 재생됩니다.") {
    cancelSourceRetry()
    sourceRetryAttempt = 0
    asmeul_stop(engine)
    monitorTimer?.invalidate()
    monitorTimer = nil
    running = false
    waitingForMusic = false
    capturedProcessIDs = []
    meter.reset()
    status = message
    rememberMood()
  }
  func updateOutput() {
    if let device: UInt32 = property(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
      initial: UInt32(0)),
      let name = stringProperty(device, kAudioObjectPropertyName)
    {
      if outputName != name { outputName = name }
    }
  }
  func sampleRateForOutput() -> Double? {
    var value = 0.0
    var size = UInt32(MemoryLayout<Double>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(asmeul_output_device(engine), &address, 0, nil, &size, &value)
        == noErr
    else { return nil }
    return value
  }
  private func pollMusicInput() -> Bool {
    let captureState = asmeul_poll_capture(engine)
    if captureState < 0 {
      let detail = String(cString: asmeul_error(engine))
      stop(message: "음악 입력을 연결하지 못해 원음으로 복구했습니다.")
      error = "오디오 연결 실패: \(detail)"
      return false
    }
    if captureState == 0 {
      captureWaitTicks = min(20, captureWaitTicks + 1)
      if captureWaitTicks == 20 && !waitingForMusic {
        waitingForMusic = true
        status = "음악 입력 대기 중 · 원음 유지"
      }
    } else if captureWaitTicks >= 0 {
      captureWaitTicks = -1
      waitingForMusic = false
      status = "음악과 선택한 ASMR을 함께 재생하고 있어요."
    }
    return true
  }
  func tick() {
    guard !shuttingDown, running else { return }
    guard pollMusicInput() else { return }
    asmeul_collect_sounds(engine)
    meter.update(peak: asmeul_peak(engine))
    let callbacks = asmeul_callbacks(engine)
    if callbacks == lastCallbacks { stalled += 1 } else { stalled = 0 }
    lastCallbacks = callbacks
    if stalled > 40 {
      stop(message: "오디오 신호 경로가 응답하지 않아 원음으로 복구했습니다.")
      error = "권한 또는 출력 장치를 확인하고 다시 시작하세요."
      return
    }
    if let output: UInt32 = property(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
      initial: UInt32(0)), output != asmeul_output_device(engine)
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
    if selected != 0, let source = processes.first(where: { $0.id == selected }),
      source.processIDs != capturedProcessIDs
    {
      status = "앱의 오디오 연결이 바뀌어 다시 연결합니다."
      rebuildForChangedSource()
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
    let records: [AudioProcessRecord] = ids.prefix(Int(size) / MemoryLayout<UInt32>.size).compactMap { id in
      guard let pid: Int32 = property(id, kAudioProcessPropertyPID, initial: Int32(0)),
        pid != getpid()
      else { return nil }
      return AudioProcessRecord(
        id: id, pid: pid, bundleID: stringProperty(id, kAudioProcessPropertyBundleID),
        bundlePath: NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL.path)
    }
    let apps: [AudioApplication] = NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.processIdentifier != getpid(), app.activationPolicy == .regular,
        let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty
      else { return nil }
      return AudioApplication(
        pid: app.processIdentifier, name: name,
        bundleID: app.bundleIdentifier ?? "pid-\(app.processIdentifier)",
        bundlePath: app.bundleURL?.standardizedFileURL.path)
    }
    let updated = groupedAudioSources(applications: apps, records: records, selected: selected)
    if updated != processes { processes = updated }
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
        value.environmentID == nil
          || EnvironmentPhoto.library.contains(where: { $0.id == value.environmentID }),
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
    return base.appendingPathComponent("ASMEUL/User Sounds", isDirectory: true)
  }
  private var legacyCustomSoundsDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let previousAppName = ["Hol", "low"].joined()
    return base.appendingPathComponent("\(previousAppName)/User Sounds", isDirectory: true)
  }
  private var customCatalogURL: URL { customSoundsDirectory.appendingPathComponent("catalog.json") }
  private func migrateLegacyData() {
    let defaults = UserDefaults.standard
    let previousDomain = ["studio", ["hol", "low"].joined(), "prototype"]
      .joined(separator: ".")
    if let previousDefaults = UserDefaults(suiteName: previousDomain) {
      for key in ["animations.enabled", "mixes.v4", "moods"]
      where defaults.object(forKey: key) == nil {
        if let value = previousDefaults.object(forKey: key) {
          defaults.set(value, forKey: key)
        }
      }
    }

    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: customSoundsDirectory.path),
      fileManager.fileExists(atPath: legacyCustomSoundsDirectory.path)
    else { return }
    do {
      try fileManager.createDirectory(
        at: customSoundsDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fileManager.moveItem(at: legacyCustomSoundsDirectory, to: customSoundsDirectory)
    } catch {
      sourceLogger.notice(
        "legacy user sounds migration skipped: \(error.localizedDescription, privacy: .public)")
    }
  }
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
    guard !importingSound else { return }
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
    let destination = customSoundsDirectory.appendingPathComponent("custom-\(slot)-\(UUID().uuidString).mp3")
    let rawName = source.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let loader = soundLoader
    importingSound = true
    status = "음원을 추가하고 있어요."
    importTask = Task(priority: .utility) { [weak self] in
      do {
        let duration = try await loader.importRecording(from: source, to: destination, slot: slot)
        guard !Task.isCancelled, let self, !self.shuttingDown else {
          try? FileManager.default.removeItem(at: destination)
          return
        }
        let item = ASMRTrack(id: slot,
          name: rawName.isEmpty ? "사용자 음원 \(slot - 20)" : rawName,
          file: destination.lastPathComponent, symbol: "waveform", supplied: true, custom: true)
        // Persist before publishing so a failed save cannot leave a ghost card.
        try JSONEncoder().encode(self.catalog.filter(\.custom) + [item])
          .write(to: self.customCatalogURL, options: .atomic)
        self.catalog.append(item)
        self.tracks.append(TrackSetting(id: slot))
        self.durations[slot] = duration
        self.status = "\(item.name)을 추가했습니다."
        self.error = nil
        self.importingSound = false
        self.importTask = nil
      } catch {
        try? FileManager.default.removeItem(at: destination)
        guard !Task.isCancelled, let self, !self.shuttingDown else { return }
        self.error = "MP3를 추가하지 못했습니다: \(error.localizedDescription)"
        self.importingSound = false
        self.importTask = nil
      }
    }
  }

  func renameCustomSound(_ id: Int, name: String) {
    guard let index = catalog.firstIndex(where: { $0.id == id && $0.custom }) else { return }
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      error = "음원 이름을 입력해 주세요."
      return
    }
    catalog[index].name = String(cleaned.prefix(80))
    do {
      try FileManager.default.createDirectory(
        at: customSoundsDirectory, withIntermediateDirectories: true)
      let custom = catalog.filter(\.custom)
      try JSONEncoder().encode(custom).write(to: customCatalogURL, options: .atomic)
      status = "\(catalog[index].name)으로 이름을 변경했습니다."
      error = nil
    } catch {
      self.error = "음원 이름을 저장하지 못했습니다: \(error.localizedDescription)"
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
    soundTasks.removeValue(forKey: id)?.cancel()
    loadGenerations.removeValue(forKey: id)
    loadingTracks.remove(id)
    evictionTasks.removeValue(forKey: id)?.cancel()
    loadedTracks.remove(id)
    asmeul_track_gain(engine, Int32(id), 0)
    asmeul_unload_sound(engine, Int32(id))
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
    guard !shuttingDown else { return }
    shuttingDown = true
    metadataTask?.cancel()
    importTask?.cancel()
    soundTasks.values.forEach { $0.cancel() }
    soundTasks.removeAll()
    evictionTasks.values.forEach { $0.cancel() }
    evictionTasks.removeAll()
    pendingSourceRefresh?.cancel()
    for (object, var address, listener) in hardwareListeners {
      AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
    }
    hardwareListeners.removeAll()
    stop()
    flushMoodSave()
    monitorTimer?.invalidate()
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    asmeul_destroy(engine)
  }
}
