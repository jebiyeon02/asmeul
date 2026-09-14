import AppKit
import QuartzCore
import SwiftUI

private struct MotionVisibleKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var motionVisible: Bool {
    get { self[MotionVisibleKey.self] }
    set { self[MotionVisibleKey.self] = newValue }
  }
}

struct MotionTimeline<Content: View>: View {
  let isRunning: Bool
  var framesPerSecond: Double = 30
  @ViewBuilder let content: (TimeInterval) -> Content
  @Environment(\.motionVisible) private var visible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var clock = AnimationClock()

  private var advancing: Bool { isRunning && visible && !reduceMotion }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / framesPerSecond, paused: !advancing)) { _ in
      content(clock.time(at: ProcessInfo.processInfo.systemUptime))
    }
    .onChange(of: advancing, initial: true) { _, running in
      clock.setRunning(running, at: ProcessInfo.processInfo.systemUptime)
    }
  }
}

struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow) -> Void
  let onVisibilityChange: (Bool) -> Void

  func makeNSView(context: Context) -> WindowObserverView {
    let view = WindowObserverView()
    view.onResolve = onResolve
    view.onVisibilityChange = onVisibilityChange
    return view
  }

  func updateNSView(_ view: WindowObserverView, context: Context) {
    view.onResolve = onResolve
    view.onVisibilityChange = onVisibilityChange
  }

  final class WindowObserverView: NSView {
    var onResolve: ((NSWindow) -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?
    private var token: NSObjectProtocol?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let token { NotificationCenter.default.removeObserver(token) }
      guard let window else { return }
      token = NotificationCenter.default.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in self?.reportVisibility() }
      }
      DispatchQueue.main.async { [weak self, weak window] in
        guard let self, let window else { return }
        self.onResolve?(window)
        self.reportVisibility()
      }
    }

    private func reportVisibility() {
      onVisibilityChange?(window?.occlusionState.contains(.visible) == true)
    }

    deinit {
      if let token { NotificationCenter.default.removeObserver(token) }
    }
  }
}

/// The photo remains a decoded layer texture; only its transform animates in the compositor.
struct CompositedPhoto: NSViewRepresentable {
  let image: CGImage
  let isAnimating: Bool

  func makeNSView(context: Context) -> PhotoLayerView { PhotoLayerView() }

  func updateNSView(_ view: PhotoLayerView, context: Context) {
    view.update(image: image, isAnimating: isAnimating)
  }

  final class PhotoLayerView: NSView {
    private let photoLayer = CALayer()
    private var currentImage: CGImage?
    private var moving = false

    override init(frame: NSRect) {
      super.init(frame: frame)
      wantsLayer = true
      layer?.masksToBounds = true
      photoLayer.contentsGravity = .resizeAspectFill
      photoLayer.transform = CATransform3DMakeScale(1.04, 1.04, 1)
      layer?.addSublayer(photoLayer)
      animate("transform.scale", from: 1.032, to: 1.048, duration: 85)
      animate("transform.translation.x", from: -8, to: 8, duration: 110)
      animate("transform.translation.y", from: -5, to: 5, duration: 140)
      photoLayer.speed = 0
      photoLayer.timeOffset = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
      super.layout()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      photoLayer.bounds = CGRect(origin: .zero, size: bounds.size)
      photoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
      CATransaction.commit()
    }

    func update(image: CGImage, isAnimating: Bool) {
      if currentImage !== image {
        currentImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        photoLayer.contents = image
        CATransaction.commit()
      }
      guard moving != isAnimating else { return }
      moving = isAnimating
      if isAnimating {
        let pausedAt = photoLayer.timeOffset
        photoLayer.speed = 1
        photoLayer.timeOffset = 0
        photoLayer.beginTime = 0
        photoLayer.beginTime = photoLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
      } else {
        let pausedAt = photoLayer.convertTime(CACurrentMediaTime(), from: nil)
        photoLayer.speed = 0
        photoLayer.timeOffset = pausedAt
      }
    }

    private func animate(_ key: String, from: Double, to: Double, duration: Double) {
      let animation = CABasicAnimation(keyPath: key)
      animation.fromValue = from
      animation.toValue = to
      animation.duration = duration
      animation.autoreverses = true
      animation.repeatCount = .infinity
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      photoLayer.add(animation, forKey: key)
    }
  }
}
