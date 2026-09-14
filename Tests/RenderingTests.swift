import Combine
import Foundation

@main struct RenderingTests {
  @MainActor static func main() async throws {
    var clock = AnimationClock()
    precondition(clock.time(at: 100) == 0)
    clock.setRunning(true, at: 100)
    precondition(clock.time(at: 103) == 3)
    clock.setRunning(true, at: 102)  // An unrelated view update must not restart motion.
    precondition(clock.time(at: 103) == 3)
    clock.setRunning(false, at: 103)
    precondition(clock.time(at: 600) == 3)
    clock.setRunning(false, at: 600)
    clock.setRunning(true, at: 700)
    precondition(clock.time(at: 704) == 7)
    precondition(clock.time(at: 2000) == 1303)  // No phase wrap at ten minutes.
    print("PASS: motion freezes while paused/hidden and resumes without a phase jump")

    let meter = AudioMeter()
    var notifications = 0
    let subscription = meter.objectWillChange.sink { notifications += 1 }
    for _ in 0..<20 { meter.update(peak: 0.5) }
    precondition(meter.litBars == 5 && notifications == 1)
    meter.update(peak: 0)
    precondition(meter.litBars == 5 && notifications == 1)
    meter.update(peak: 0)
    precondition(meter.litBars == 4 && notifications == 2)
    meter.reset()
    meter.reset()
    precondition(meter.litBars == 0 && notifications == 3)
    withExtendedLifetime(subscription) {}
    print("PASS: meter publishes only visible bar changes, including decay and reset")

    let store = EnvironmentImageStore()
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix("environment-") && $0.pathExtension == "jpg" }
    precondition(files.count == 5)
    for file in files {
      guard let small = await store.image(at: file, maxPixelSize: 512),
        let cached = await store.image(at: file, maxPixelSize: 512),
        let large = await store.image(at: file, maxPixelSize: 2560)
      else { fatalError("Could not decode \(file.lastPathComponent)") }
      precondition(small === cached)
      precondition(max(small.width, small.height) <= 512)
      precondition(max(large.width, large.height) <= 2560)
      precondition(small !== large)
      precondition(small.bytesPerRow * small.height < 2 * 1024 * 1024)
    }
    let invalid = await store.image(
      at: root.appendingPathComponent("missing.jpg"), maxPixelSize: 512)
    precondition(invalid == nil)
    print("PASS: all five photos decode at bounded sizes; thumbnails reuse cached images")
  }
}
