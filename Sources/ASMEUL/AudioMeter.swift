import Combine
import Foundation

/// Meter ticks invalidate only the eight bars, never the mixer or background.
@MainActor final class AudioMeter: ObservableObject {
  @Published private(set) var litBars = 0
  private var peak: Float = 0

  func update(peak input: Float) {
    peak = max(input.isFinite ? input : 0, peak * 0.85)
    publish()
  }

  func reset() {
    peak = 0
    publish()
  }

  private func publish() {
    let next = min(8, max(0, Int(ceil(Double(peak) * 10))))
    if next != litBars { litBars = next }
  }
}
