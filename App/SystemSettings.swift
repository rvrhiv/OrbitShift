import AppKit

@MainActor
enum SystemSettings {
  static func revealApplication() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  static func keyboard() { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
  static func accessibility() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }
  static func inputMonitoring() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
  }
  private static func open(_ string: String) {
    if let url = URL(string: string) { NSWorkspace.shared.open(url) }
  }
}
