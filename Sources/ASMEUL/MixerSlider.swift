import AppKit
import SwiftUI

/// Keep AppKit's tracking, keyboard and accessibility behavior, with a painted
/// thumb that does not create a Liquid Glass backdrop for every mixer control.
struct MixerSlider: NSViewRepresentable {
  @Binding var value: Double
  private let range: ClosedRange<Double>
  @Environment(\.isEnabled) private var isEnabled

  init(value: Binding<Double>, in range: ClosedRange<Double>) {
    _value = value
    self.range = range
  }

  func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

  func makeNSView(context: Context) -> NSSlider {
    let slider = NSSlider()
    slider.cell = MixerSliderCell()
    slider.isContinuous = true
    slider.target = context.coordinator
    slider.action = #selector(Coordinator.changed(_:))
    slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return slider
  }

  func updateNSView(_ slider: NSSlider, context: Context) {
    context.coordinator.value = $value
    slider.minValue = range.lowerBound
    slider.maxValue = range.upperBound
    slider.isEnabled = isEnabled
    if slider.doubleValue != value { slider.doubleValue = value }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 120, height: 16)
  }

  final class Coordinator: NSObject {
    var value: Binding<Double>
    init(value: Binding<Double>) { self.value = value }

    @objc func changed(_ sender: NSSlider) {
      if value.wrappedValue != sender.doubleValue { value.wrappedValue = sender.doubleValue }
    }
  }
}

final class MixerSliderCell: NSSliderCell {
  override func drawBar(inside rect: NSRect, flipped: Bool) {
    let bar = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
    NSColor.white.withAlphaComponent(isEnabled ? 0.12 : 0.06).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()

    let thumb = knobRect(flipped: flipped)
    let fill = NSRect(x: bar.minX, y: bar.minY, width: max(0, thumb.midX - bar.minX), height: bar.height)
    NSColor(calibratedRed: 0.93, green: 0.79, blue: 0.55, alpha: isEnabled ? 1 : 0.4).setFill()
    NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
  }

  override func drawKnob(_ knobRect: NSRect) {
    let thumb = NSRect(x: knobRect.midX - 9, y: knobRect.midY - 7, width: 18, height: 14)
    NSColor(white: isHighlighted ? 0.78 : 0.9, alpha: isEnabled ? 1 : 0.45).setFill()
    NSBezierPath(roundedRect: thumb, xRadius: 7, yRadius: 7).fill()
  }
}
