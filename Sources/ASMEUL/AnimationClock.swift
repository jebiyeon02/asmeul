import Foundation

/// Only elapsed, visible playback time advances the effects. Pausing never jumps phase.
struct AnimationClock {
  private var elapsed: TimeInterval = 0
  private var resumedAt: TimeInterval?

  func time(at now: TimeInterval) -> TimeInterval {
    elapsed + (resumedAt.map { max(0, now - $0) } ?? 0)
  }

  mutating func setRunning(_ running: Bool, at now: TimeInterval) {
    if running, resumedAt == nil {
      resumedAt = now
    } else if !running, let start = resumedAt {
      elapsed += max(0, now - start)
      resumedAt = nil
    }
  }
}
