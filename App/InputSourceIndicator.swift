import AppKit
import CoreText
import OrbitShiftCore

@MainActor
enum InputSourceIndicator {
  private static let size = NSSize(width: 18, height: 18)
  private static var images: [String: NSImage] = [:]

  static func image(for source: InputSource?) -> NSImage? {
    let flag = source.flatMap(flag)
    let key = flag ?? "globe"
    if let cached = images[key] { return cached }

    let image: NSImage?
    if let flag {
      image = NSImage(size: size, flipped: false) { rect in
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont(name: "Apple Color Emoji", size: 16) ?? NSFont.systemFont(ofSize: 16)
        ]
        let line = CTLineCreateWithAttributedString(
          NSAttributedString(string: flag, attributes: attributes))
        let bounds = CTLineGetImageBounds(line, nil)
        guard let context = NSGraphicsContext.current?.cgContext,
          bounds.width > 0, bounds.height > 0
        else { return false }
        // Fit the glyph itself; text line spacing makes emoji look undersized.
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        context.saveGState()
        context.translateBy(
          x: rect.midX - bounds.midX * scale,
          y: rect.midY - bounds.midY * scale)
        context.scaleBy(x: scale, y: scale)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        return true
      }
      image?.isTemplate = false
    } else {
      image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
      image?.size = size
      image?.isTemplate = true
    }
    images[key] = image
    return image
  }

  private static func flag(for source: InputSource) -> String? {
    // Some Apple layouts share a language tag (for example US and British use "en").
    // Their layout identifier supplies the region before the locale fallback.
    let layoutRegions = [
      "Australian": "AU", "Austrian": "AT", "Belgian": "BE", "Brazilian": "BR",
      "British": "GB", "Canadian": "CA", "Irish": "IE", "Italian": "IT",
      "NewZealand": "NZ", "Portuguese": "PT", "Swiss": "CH", "Turkish": "TR",
    ]
    let layoutRegion = layoutRegions.first {
      source.id.hasPrefix("com.apple.keylayout." + $0.key)
    }?.value
    let language = source.language.replacingOccurrences(of: "_", with: "-")
    let code = language.split(separator: "-").first?.lowercased() ?? ""
    guard
      let region = layoutRegion
        ?? (!code.isEmpty && !["und", "mul", "zxx"].contains(code)
          ? Locale(identifier: Locale.Language(identifier: language).maximalIdentifier)
            .region?.identifier : nil)
    else { return nil }
    let letters = region.uppercased().unicodeScalars
    // World/continental regions such as 001 and 419 do not have country flags.
    guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else {
      return nil
    }
    return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar($0.value + 127397) }))
  }
}
