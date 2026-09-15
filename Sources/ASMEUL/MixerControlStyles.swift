import SwiftUI

/// A switch surface that does not sample the animated scene behind the mixer.
/// Keep Toggle's binding and accessibility semantics, and Button's keyboard action.
struct MixerSwitchStyle: ToggleStyle {
  var showsLabel = true
  @Environment(\.controlSize) private var controlSize
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let height: CGFloat = controlSize == .mini ? 15 : 18
    let width: CGFloat = controlSize == .mini ? 27 : 32

    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 6) {
        if showsLabel { configuration.label }
        Capsule()
          .fill(configuration.isOn ? accent : Color.white.opacity(0.18))
          .overlay(alignment: configuration.isOn ? .trailing : .leading) {
            Circle()
              .fill(Color(white: 0.92))
              .frame(width: height - 4, height: height - 4)
              .padding(2)
          }
          .frame(width: width, height: height)
      }
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Toggle(configuration).toggleStyle(.switch)
    }
  }
}

extension View {
  /// Only the closed menu label uses this style. The open menu stays native.
  func mixerMenuStyle() -> some View {
    menuStyle(.button)
      .buttonStyle(.plain)
  }
}
