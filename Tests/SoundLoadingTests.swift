import Foundation
import AudioCore

extension Bundle {
  static var module: Bundle { Bundle(path: CommandLine.arguments[1])! }
}

@main struct SoundLoadingTests {
  @MainActor static func main() async throws {
    let loader = SoundLoader()
    let engine = asmeul_create()!
    defer { asmeul_destroy(engine) }
    let urls = try Dictionary(uniqueKeysWithValues: ASMRTrack.builtIn.map {
      ($0.id, try SoundLibrary.resourceURL(for: $0))
    })
    let metadata = await loader.metadata(urls)
    assert(metadata.count == 25 && metadata[1, default: 0] > 930)
    assert(asmeul_sound_bytes(engine) == 0)
    print("PASS: duration metadata for all 25 recordings without retaining PCM")

    var totalBytes: UInt64 = 0
    var maxBytes: UInt64 = 0
    for track in ASMRTrack.builtIn {
      let prepared = try await loader.prepare(url: urls[track.id]!, slot: track.id)
      assert(prepared.duration > 0 && prepared.install(into: engine))
      let bytes = asmeul_sound_bytes(engine)
      assert(bytes > 0)
      totalBytes += bytes
      maxBytes = max(maxBytes, bytes)
      // An already-transferred recording cannot be published twice.
      assert(!prepared.install(into: engine))
      asmeul_track_gain(engine, Int32(track.id), 0.45)
      var output = [Float](repeating: 0, count: 4096)
      output.withUnsafeMutableBufferPointer {
        asmeul_render_offline(engine, $0.baseAddress, 2048, 48000)
      }
      assert(output.allSatisfy { $0.isFinite && abs($0) <= 0.95001 })
      asmeul_unload_sound(engine, Int32(track.id))
      asmeul_collect_sounds(engine)
      assert(asmeul_sound_bytes(engine) == 0)
    }
    print("PASS: all 25 full recordings decode, transfer, render and release independently; total PCM \(totalBytes) bytes, largest \(maxBytes) bytes")

    // Main-actor work runs while a lengthy recording decodes on the serial actor.
    let decoding = Task(priority: .utility) { try await loader.prepare(url: urls[1]!, slot: 1) }
    let start = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(10))
    let responsiveness = start.duration(to: .now)
    decoding.cancel()
    do {
      _ = try await decoding.value
      assertionFailure("long decode should observe cancellation")
    } catch is CancellationError { }
    print("PASS: cancellation during long decode; main-actor 10ms heartbeat elapsed \(responsiveness)")

    let cancelled = Task(priority: .utility) { try await loader.prepare(url: urls[0]!, slot: 0) }
    cancelled.cancel()
    do { _ = try await cancelled.value; assertionFailure("cancelled load succeeded") }
    catch is CancellationError { }
    do { _ = try await loader.prepare(url: URL(fileURLWithPath: "/nonexistent-asmeul-test.mp3"), slot: 0); assertionFailure("missing file succeeded") }
    catch { }
    let recovered = try await loader.prepare(url: urls[33]!, slot: 33)
    assert(recovered.install(into: engine))
    asmeul_unload_sound(engine, 33)
    assert(asmeul_sound_bytes(engine) == 0)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let imported = folder.appendingPathComponent("custom.mp3")
    let duration = try await loader.importRecording(from: urls[33]!, to: imported, slot: 21)
    assert(duration > 0 && FileManager.default.fileExists(atPath: imported.path))
    let custom = try await loader.prepare(url: imported, slot: 21)
    assert(custom.install(into: engine))
    asmeul_unload_sound(engine, 21)
    assert(asmeul_sound_bytes(engine) == 0)
    print("PASS: cancellation, invalid file recovery, asynchronous custom MP3 import and later playback")
  }
}
