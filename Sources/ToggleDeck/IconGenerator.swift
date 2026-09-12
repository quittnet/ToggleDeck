import AppKit

/// Packages the source artwork into every macOS icon size.
/// Invoked by install.sh: `ToggleDeck --make-icon <path>.icns`.
@MainActor
enum IconGenerator {

  /// Big Sur onward: the rounded square occupies 824 of the 1024pt canvas
  /// with a 185.4pt corner radius. Everything here is expressed as a fraction
  /// of the canvas so each iconset size comes out identical.
  private enum Tile {
    static let inset: CGFloat = 100.0 / 1024.0
    static let corner: CGFloat = 185.4 / 1024.0
  }

  static func run(output: String) -> Int32 {
    let sourceURL = URL(fileURLWithPath: output).deletingLastPathComponent()
      .appendingPathComponent("AppIcon.png")
    let source =
      NSImage(contentsOf: sourceURL)
      ?? Bundle.main.url(forResource: "AppIconSource", withExtension: "png")
      .flatMap { NSImage(contentsOf: $0) }
    let sizes: [(px: Int, name: String)] = [
      (16, "icon_16x16"), (32, "icon_16x16@2x"),
      (32, "icon_32x32"), (64, "icon_32x32@2x"),
      (128, "icon_128x128"), (256, "icon_128x128@2x"),
      (256, "icon_256x256"), (512, "icon_256x256@2x"),
      (512, "icon_512x512"), (1024, "icon_512x512@2x"),
    ]

    let fm = FileManager.default
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("ToggleDeckIcon-\(getpid()).iconset")
    try? fm.removeItem(at: iconset)
    do {
      try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    } catch {
      FileHandle.standardError.write(Data("could not create iconset dir\n".utf8))
      return 1
    }

    for (px, name) in sizes {
      guard let data = png(size: px, source: source) else {
        FileHandle.standardError.write(Data("render failed at \(px)px\n".utf8))
        return 1
      }
      try? data.write(to: iconset.appendingPathComponent("\(name).png"))
    }

    let result = Shell.run(
      "/usr/bin/iconutil -c icns \(Shell.quote(iconset.path)) -o \(Shell.quote(output))",
      timeout: 60)
    try? fm.removeItem(at: iconset)

    if !result.ok {
      FileHandle.standardError.write(Data("iconutil failed: \(result.message)\n".utf8))
      return 1
    }
    print("wrote \(output)")
    return 0
  }

  private static func png(size: Int, source: NSImage?) -> Data? {
    let s = CGFloat(size)
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill()
    canvas.fill()

    if let source {
      NSGraphicsContext.current?.imageInterpolation = .high
      let tile = canvas.insetBy(dx: s * Tile.inset, dy: s * Tile.inset)
      NSBezierPath(roundedRect: tile, xRadius: s * Tile.corner, yRadius: s * Tile.corner).addClip()
      source.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
      return rep.representation(using: .png, properties: [:])
    }

    let inset = s * Tile.inset
    let tile = canvas.insetBy(dx: inset, dy: inset)
    let corner = s * Tile.corner
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner)

    // Blue-to-indigo, lit from the top the way macOS icons are.
    let gradient = NSGradient(colors: [
      NSColor(srgbRed: 0.353, green: 0.596, blue: 0.996, alpha: 1),
      NSColor(srgbRed: 0.216, green: 0.325, blue: 0.882, alpha: 1),
    ])
    tilePath.addClip()
    gradient?.draw(in: tile, angle: -90)

    // Gloss across the top third.
    let gloss = NSGradient(colors: [
      NSColor(white: 1, alpha: 0.20),
      NSColor(white: 1, alpha: 0.0),
    ])
    gloss?.draw(
      in: NSRect(
        x: tile.minX, y: tile.midY,
        width: tile.width, height: tile.height / 2), angle: -90)

    NSGraphicsContext.current?.cgContext.resetClip()

    // Glyph centred in the tile. Its "on" knob is punched through, so the
    // gradient shows in the knob rather than a flat stand-in colour.
    let glyphWidth = tile.width * 0.50
    let glyphHeight = glyphWidth * 0.94
    let glyphRect = NSRect(
      x: tile.midX - glyphWidth / 2,
      y: tile.midY - glyphHeight / 2,
      width: glyphWidth, height: glyphHeight)
    let glyph = SwitchGlyph.image(size: glyphRect.size, color: .white)
    glyph.draw(in: glyphRect)

    // Hairline rim so the tile keeps an edge on a white background.
    NSColor(white: 0, alpha: 0.10).setStroke()
    let rim = NSBezierPath(
      roundedRect: tile.insetBy(dx: 0.5, dy: 0.5),
      xRadius: corner, yRadius: corner)
    rim.lineWidth = max(1, s / 512)
    rim.stroke()

    return rep.representation(using: .png, properties: [:])
  }
}
