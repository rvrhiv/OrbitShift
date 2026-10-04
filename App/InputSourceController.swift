import Carbon
import Foundation
import OrbitShiftCore

@MainActor
final class InputSourceController: NSObject {
  var onChange: (() -> Void)?

  override init() {
    super.init()
    for name in [
      kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged,
    ] {
      // AppKit suspends ordinary distributed notifications while the app is inactive.
      // A menu bar indicator must keep following the input source in the background.
      DistributedNotificationCenter.default().addObserver(
        self, selector: #selector(inputSourcesDidChange(_:)),
        name: Notification.Name(name! as String), object: nil,
        suspensionBehavior: .deliverImmediately)
    }
  }

  @objc nonisolated private func inputSourcesDidChange(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in self?.onChange?() }
  }

  func stop() {
    DistributedNotificationCenter.default().removeObserver(self)
  }

  private func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }

  private func boolean(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
  }

  private func systemSources() -> [TISInputSource] {
    guard let list = TISCreateInputSourceList(nil, false) else { return [] }
    return list.takeRetainedValue() as! [TISInputSource]
  }

  private func describe(_ source: TISInputSource) -> InputSource? {
    guard let id = string(source, kTISPropertyInputSourceID),
      let name = string(source, kTISPropertyLocalizedName)
    else { return nil }
    var language = ""
    if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
      let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as! [String]
      language = languages.first ?? ""
    }
    return InputSource(id: id, name: name, language: language)
  }

  func availableSources() -> [InputSource] {
    var seen = Set<String>()
    return systemSources().compactMap { source in
      guard boolean(source, kTISPropertyInputSourceIsEnabled),
        boolean(source, kTISPropertyInputSourceIsSelectCapable),
        string(source, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource
          as String,
        let item = describe(source), seen.insert(item.id).inserted
      else { return nil }
      return item
    }
  }

  func currentSource() -> InputSource? {
    guard let source = TISCopyCurrentKeyboardInputSource() else { return nil }
    return describe(source.takeRetainedValue())
  }

  func select(id: String) throws {
    guard
      let source = systemSources().first(where: {
        string($0, kTISPropertyInputSourceID) == id
          && boolean($0, kTISPropertyInputSourceIsEnabled)
          && boolean($0, kTISPropertyInputSourceIsSelectCapable)
      })
    else {
      throw InputSelectionError.unavailable
    }
    let result = TISSelectInputSource(source)
    guard result == noErr else { throw InputSelectionError.rejected(result) }
    // The system notification refreshes the UI as well. Never advance an internal index.
    onChange?()
  }
}

enum InputSelectionError: LocalizedError {
  case unavailable
  case rejected(OSStatus)
  var errorDescription: String? {
    switch self {
    case .unavailable:
      localized(
        "Источник ввода больше недоступен. Обновите список.",
        "This input source is no longer available. Refresh the list.")
    case .rejected(let code):
      localized("macOS не переключила источник ввода", "macOS could not select the input source")
        + " (\(code))."
    }
  }
}
