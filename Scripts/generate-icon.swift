import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = destination.deletingLastPathComponent().appendingPathComponent("OrbitShift.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(
      roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
    NSGradient(
      starting: NSColor(red: 0.29, green: 0.24, blue: 0.68, alpha: 1),
      ending: NSColor(red: 0.58, green: 0.48, blue: 0.98, alpha: 1))!.draw(
        in: background, angle: 65)
    NSColor.white.withAlphaComponent(0.94).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 244, y: 244, width: 536, height: 536))
    ring.lineWidth = 23
    ring.stroke()
    let meridian = NSBezierPath(ovalIn: NSRect(x: 380, y: 244, width: 264, height: 536))
    meridian.lineWidth = 20
    meridian.stroke()
    for y in [CGFloat(412), CGFloat(612)] {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: 264, y: y))
      line.line(to: NSPoint(x: 760, y: y))
      line.lineWidth = 20
      line.stroke()
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 712, y: 698, width: 100, height: 100)).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent(name))
  }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", destination.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
