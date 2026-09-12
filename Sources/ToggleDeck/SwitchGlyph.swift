import AppKit

/// The app's mark: two stacked switches, the top one on and the bottom one off.
///
/// Drawn rather than shipped as an asset so the menu bar template, the SwiftUI
/// header and the app icon are all the same geometry at any size.
@MainActor
enum SwitchGlyph {

  /// Proportions, expressed against the glyph's bounding box so one routine
  /// serves a 15pt menu bar item and a 1024pt icon.
  private enum P {
    static let capsuleHeight: CGFloat = 0.406  // of total height
    static let knobRadius: CGFloat = 0.62  // of capsule radius
    static let strokeWidth: CGFloat = 0.115  // of capsule height
  }

  /// Transparent image containing both switches in `color`.
  ///
  /// The "on" switch is a solid capsule with its knob punched out via an
  /// even-odd fill, so composited over the icon gradient the knob shows the
  /// background through rather than a flat approximation of it.
  static func image(size: NSSize, color: NSColor) -> NSImage {
    let image = NSImage(size: size, flipped: false) { _ in
      draw(in: NSRect(origin: .zero, size: size), color: color)
      return true
    }
    return image
  }

  /// Menu bar version: a template image, so macOS tints it for the light or
  /// dark menu bar and for the highlighted state.
  static func statusItemImage() -> NSImage {
    let image = self.image(size: NSSize(width: 16, height: 15), color: .black)
    image.isTemplate = true
    return image
  }

  static func draw(in rect: NSRect, color: NSColor) {
    let w = rect.width
    let h = rect.height
    let capH = h * P.capsuleHeight
    let radius = capH / 2
    let knobR = radius * P.knobRadius
    let stroke = max(capH * P.strokeWidth, 0.9)

    color.setFill()
    color.setStroke()

    // Top: on. Solid capsule, knob to the right, knocked out.
    let topRect = NSRect(x: rect.minX, y: rect.maxY - capH, width: w, height: capH)
    let on = NSBezierPath(roundedRect: topRect, xRadius: radius, yRadius: radius)
    let onKnob = NSBezierPath(
      ovalIn: NSRect(
        x: topRect.maxX - radius - knobR,
        y: topRect.midY - knobR,
        width: knobR * 2, height: knobR * 2))
    on.append(onKnob)
    on.windingRule = .evenOdd
    on.fill()

    // Bottom: off. Outlined capsule, solid knob to the left.
    let botRect = NSRect(x: rect.minX, y: rect.minY, width: w, height: capH)
      .insetBy(dx: stroke / 2, dy: stroke / 2)
    let off = NSBezierPath(
      roundedRect: botRect,
      xRadius: botRect.height / 2, yRadius: botRect.height / 2)
    off.lineWidth = stroke
    off.stroke()

    let offKnobCenter = NSPoint(x: botRect.minX + botRect.height / 2, y: botRect.midY)
    NSBezierPath(
      ovalIn: NSRect(
        x: offKnobCenter.x - knobR, y: offKnobCenter.y - knobR,
        width: knobR * 2, height: knobR * 2)
    ).fill()
  }
}
