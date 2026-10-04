import AppKit
import SwiftUI

@MainActor
enum PreviewRenderer {
  /// Renders only our own synthetic settings view; does not capture the desktop.
  static func render(model: AppModel, to path: String) async throws {
    let size = NSSize(width: 840, height: 780)
    let page =
      CommandLine.arguments.firstIndex(of: "--page").flatMap { index in
        CommandLine.arguments.indices.contains(index + 1)
          ? SettingsPage(rawValue: CommandLine.arguments[index + 1]) : nil
      } ?? .switching
    let view = NSHostingView(rootView: SettingsView(model: model, initialPage: page))
    view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.appearance = NSAppearance(
      named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(250))
    window.display()
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    window.orderOut(nil)
  }
}
