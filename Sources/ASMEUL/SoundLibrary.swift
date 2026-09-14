import AVFoundation
import AudioCore
import Foundation

struct ASMRTrack: Identifiable, Codable {
  let id: Int
  var name: String
  let file: String
  let symbol: String
  let supplied: Bool
  var custom: Bool = false
  static let builtIn: [ASMRTrack] = [
    .init(id: 0, name: "빗소리 1", file: "rain.mp3", symbol: "cloud.rain", supplied: false),
    .init(id: 1, name: "빗소리 2", file: "user-rain.mp3", symbol: "cloud.heavyrain", supplied: true),
    .init(id: 2, name: "일본 배경음 1", file: "user-japan.mp3", symbol: "radio", supplied: true),
    .init(id: 3, name: "키보드 1", file: "keyboard.mp3", symbol: "keyboard", supplied: false),
    .init(id: 4, name: "키보드 2", file: "user-keyboard.mp3", symbol: "keyboard", supplied: true),
    .init(id: 5, name: "연필 소리 1", file: "writing.mp3", symbol: "pencil.line", supplied: false),
    .init(id: 6, name: "연필 소리 2", file: "user-pencil.mp3", symbol: "pencil.line", supplied: true),
    .init(id: 7, name: "물방울 1", file: "cave.mp3", symbol: "drop", supplied: false),
    .init(id: 8, name: "물방울 2", file: "cave-echo.mp3", symbol: "drop.degreesign", supplied: false),
    .init(id: 9, name: "풀벌레 1", file: "crickets.mp3", symbol: "leaf", supplied: false),
    .init(id: 10, name: "물결 1", file: "lake.mp3", symbol: "water.waves", supplied: false),
    .init(id: 11, name: "바람 1", file: "grass.mp3", symbol: "wind", supplied: false),
    .init(id: 12, name: "도시 소리 1", file: "city.mp3", symbol: "building.2", supplied: false),
    .init(id: 13, name: "종 소리 1", file: "user-chimes.mp3", symbol: "bell", supplied: true),
    .init(id: 14, name: "파도 1", file: "user-wave-1.mp3", symbol: "water.waves", supplied: true),
    .init(id: 15, name: "파도 2", file: "user-wave-2.mp3", symbol: "water.waves", supplied: true),
    .init(id: 16, name: "지저귀는 새소리 1", file: "user-birds.mp3", symbol: "bird", supplied: true),
    .init(id: 17, name: "매미 1", file: "user-cicada.mp3", symbol: "leaf", supplied: true),
    .init(id: 18, name: "모닥불 1", file: "user-fire-1.mp3", symbol: "flame", supplied: true),
    .init(id: 19, name: "모닥불 2", file: "user-fire-2.mp3", symbol: "flame.fill", supplied: true),
    .init(
      id: 20, name: "물속 1", file: "user-underwater.mp3", symbol: "drop.triangle", supplied: true),
    .init(
      id: 33, name: "심우주1", file: "user-deep-space-1.mp3", symbol: "sparkles", supplied: true),
    .init(
      id: 34, name: "심우주2", file: "user-deep-space-2.mp3", symbol: "moon.stars", supplied: true),
    .init(
      id: 32, name: "눈 밟는 소리", file: "snow_step.mp3", symbol: "snowflake", supplied: true),
  ]
}
struct TrackSetting: Codable, Identifiable, Equatable {
  var id: Int
  var enabled: Bool = false
  var volume: Double = 0.45
  var direction: Int? = nil
  var distance: Double? = nil
}

/// Resolves SwiftPM resources both while developing and after the executable is
/// wrapped in a conventional macOS application bundle.
enum AppResources {
  static let bundle: Bundle = {
    if let resourceURL = Bundle.main.resourceURL,
      let installedBundle = Bundle(
        url: resourceURL.appendingPathComponent("Hollow_Hollow.bundle", isDirectory: true))
    {
      return installedBundle
    }
    return Bundle.module
  }()

  static func url(forResource name: String, withExtension extensionName: String? = nil) -> URL? {
    bundle.url(forResource: name, withExtension: extensionName)
  }
}

/// Reads full recordings in bounded chunks. The source files are never modified.
enum SoundLibrary {
  static func resourceURL(for track: ASMRTrack) throws -> URL {
    guard let url = AppResources.url(forResource: track.file) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return url
  }

  static func duration(at url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    guard file.length >= 4, seconds.isFinite, seconds <= 3600 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return seconds
  }

  static func loadResources(into engine: HollowEngine) throws -> [Int: Double] {
    var durations: [Int: Double] = [:]
    for track in ASMRTrack.builtIn {
      guard let url = AppResources.url(forResource: track.file) else {
        throw CocoaError(.fileNoSuchFile)
      }
      durations[track.id] = try load(url: url, slot: track.id, into: engine)
    }
    return durations
  }

  static func load(url: URL, slot: Int, into engine: HollowEngine) throws -> Double {
    try Task.checkCancellation()
    var finished = false
    defer { if !finished { hollow_unload_sound(engine, Int32(slot)) } }
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard file.length >= 4, file.length <= AVAudioFramePosition(format.sampleRate * 3600),
      file.length <= UInt32.max,
      (0..<35).contains(slot),
      hollow_begin_sound(engine, Int32(slot), UInt32(file.length), format.sampleRate) == 1,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536)
    else { throw CocoaError(.fileReadCorruptFile) }
    var loaded: UInt64 = 0
    var stereo = [Float](repeating: 0, count: 65536 * 2)
    while file.framePosition < file.length {
      try Task.checkCancellation()
      try file.read(
        into: buffer,
        frameCount: min(buffer.frameCapacity, UInt32(file.length - file.framePosition)))
      let count = Int(buffer.frameLength)
      guard count > 0, let channels = buffer.floatChannelData, !format.isInterleaved else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let right = min(1, Int(format.channelCount) - 1)
      for i in 0..<count {
        stereo[i * 2] = channels[0][i]
        stereo[i * 2 + 1] = channels[right][i]
      }
      let result = stereo.withUnsafeBufferPointer {
        hollow_append_sound(engine, Int32(slot), $0.baseAddress, UInt32(count))
      }
      guard result == 1 else { throw CocoaError(.fileReadCorruptFile) }
      loaded += UInt64(count)
    }
    guard hollow_finish_sound(engine, Int32(slot)) == 1 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    finished = true
    return Double(loaded) / format.sampleRate
  }
}

/// The private decoder is never rendered. Once awaited, only the main actor
/// transfers its immutable PCM into the live engine, then destroys the decoder.
final class PreparedSound: @unchecked Sendable {
  private let decoder: HollowEngine
  let duration: Double
  let slot: Int

  init(url: URL, slot: Int) throws {
    let engine = hollow_create()!
    do { duration = try SoundLibrary.load(url: url, slot: slot, into: engine) }
    catch { hollow_destroy(engine); throw error }
    decoder = engine
    self.slot = slot
  }

  func install(into engine: HollowEngine) -> Bool {
    hollow_take_sound(engine, decoder, Int32(slot)) == 1
  }

  deinit { hollow_destroy(decoder) }
}

/// Serializes long decodes so selecting many tracks cannot flood the machine
/// with concurrent decoding work or full-recording intermediate buffers.
actor SoundLoader {
  func importRecording(from source: URL, to destination: URL, slot: Int) throws -> Double {
    try Task.checkCancellation()
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: destination)
    do {
      let prepared = try PreparedSound(url: destination, slot: slot)
      try Task.checkCancellation()
      return prepared.duration
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  func prepare(url: URL, slot: Int) throws -> PreparedSound {
    try Task.checkCancellation()
    return try PreparedSound(url: url, slot: slot)
  }

  func metadata(_ urls: [Int: URL]) -> [Int: Double] {
    var values: [Int: Double] = [:]
    for (id, url) in urls {
      if Task.isCancelled { break }
      values[id] = try? SoundLibrary.duration(at: url)
    }
    return values
  }
}
