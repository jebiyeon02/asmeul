import SwiftUI

/// Bake the expensive blur when the light's style changes, not on animation ticks.
struct CachedFogLight: View {
  struct Style: Hashable {
    let color: Color
    let opacity: Double
    let size: CGFloat
    let blur: CGFloat

    // Leave room for the blur's transparent tail before applying the moving transform.
    var padding: CGFloat { ceil(blur * 3) }
    var extent: CGFloat { size + padding * 2 }
  }

  let style: Style
  let breathing: Double
  let scale: Double
  @Environment(\.colorScheme) private var colorScheme
  @State private var textures: Textures?

  private struct RenderKey: Hashable {
    let style: Style
    let colorScheme: ColorScheme
  }

  private var renderKey: RenderKey { RenderKey(style: style, colorScheme: colorScheme) }

  private struct Textures {
    let key: RenderKey
    let dim: CGImage
    let bright: CGImage
  }

  var body: some View {
    Group {
      if let textures, textures.key == renderKey {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
          let amount = min(1, max(0, (breathing - 0.7) / 0.3))
          let rect = CGRect(origin: .zero, size: size)
          // Interpolate premultiplied pixels. Ordinary source-over crossfading would
          // darken the overlap; scaling one texture would also pulse the fixed outer stop.
          context.blendMode = .plusLighter
          context.opacity = 1 - amount
          context.draw(Image(decorative: textures.dim, scale: 1), in: rect)
          context.opacity = amount
          context.draw(Image(decorative: textures.bright, scale: 1), in: rect)
        }
      } else {
        source(breathing: breathing)
      }
    }
    .frame(width: style.extent, height: style.extent)
    .scaleEffect(scale)
    .frame(width: style.size, height: style.size)
    .task(id: renderKey) { @MainActor in
      guard textures?.key != renderKey else { return }
      // These soft lights need no Retina-sized texture. Keep all six bitmaps bounded
      // to their logical sizes and retain them across timeline updates and pauses.
      guard let dim = render(breathing: 0.7), let bright = render(breathing: 1) else { return }
      textures = Textures(key: renderKey, dim: dim, bright: bright)
    }
  }

  private func source(breathing: Double) -> some View {
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: style.color.opacity(style.opacity * breathing), location: 0),
            .init(color: style.color.opacity(style.opacity * breathing * 0.42), location: 0.34),
            .init(color: style.color.opacity(style.opacity * 0.08), location: 0.7),
            .init(color: .clear, location: 1),
          ],
          center: .center, startRadius: 0, endRadius: style.size * 0.5)
      )
      .frame(width: style.size, height: style.size)
      .blur(radius: style.blur)
      .padding(style.padding)
  }

  @MainActor private func render(breathing: Double) -> CGImage? {
    let renderer = ImageRenderer(
      content: source(breathing: breathing).environment(\.colorScheme, colorScheme))
    renderer.scale = 1
    renderer.colorMode = .nonLinear
    renderer.proposedSize = ProposedViewSize(width: style.extent, height: style.extent)
    return renderer.cgImage
  }
}
