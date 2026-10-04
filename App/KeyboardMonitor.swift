import AppKit
import ApplicationServices
import Carbon
import OrbitShiftCore

@MainActor
final class KeyboardMonitor {
  var onRelease: (() -> Void)?
  var onStatusChange: (() -> Void)?
  private(set) var isRunning = false
  private(set) var lastIssue: String?
  private(set) var observedTrigger = false
  private(set) var needsInputMonitoring = false
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var state = KeyPressState(trigger: .fn)
  private var reservedKeys = Set<UInt16>()
  private var suspended = false
  private var desired = false
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private let devices = KeyboardDeviceObserver()

  var accessibilityGranted: Bool { AXIsProcessTrusted() }
  var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
  var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

  func start(trigger: TriggerKey, enabled: Bool) {
    state.reset(trigger: trigger)
    desired = enabled
    if timer == nil {
      devices.onChange = { [weak self] in
        self?.state.reset()
        self?.reservedKeys.removeAll()
        self?.onStatusChange?()
      }
      devices.start()
      timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.reconcile() }
      }
      let center = NSWorkspace.shared.notificationCenter
      for name in [
        NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
      ] {
        observers.append(
          center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.suspended = true
              self?.removeTap()
            }
          })
      }
      for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
      {
        observers.append(
          center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.suspended = false
              self?.state.reset()
              self?.reconcile()
            }
          })
      }
    }
    reconcile()
  }

  func configure(trigger: TriggerKey, enabled: Bool) {
    if state.trigger != trigger { observedTrigger = false }
    state.reset(trigger: trigger)
    desired = enabled
    reconcile()
  }

  func stop() {
    devices.stop()
    desired = false
    timer?.invalidate()
    timer = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observers.removeAll()
    removeTap()
  }

  func requestAccessibility() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    reconcile()
  }

  func requestInputMonitoring() {
    _ = CGRequestListenEventAccess()
    reconcile()
  }

  func reconcile() {
    needsInputMonitoring = false
    defer { onStatusChange?() }
    guard desired, !suspended, accessibilityGranted, !secureInputEnabled else {
      removeTap()
      lastIssue =
        secureInputEnabled
        ? localized(
          "macOS защищает ввод. Переключение возобновится после выхода из защищённого поля.",
          "macOS Secure Input is active. Switching resumes after leaving the secure field.") : nil
      return
    }
    if let tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) {
      isRunning = true
      return
    }
    removeTap()
    let types: [CGEventType] = [
      .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    // Media/function combinations arrive as systemDefined events (NSEvent type 14).
    mask |= CGEventMask(1) << 14
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let created = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, context in
          guard let context else { return Unmanaged.passUnretained(event) }
          let passThrough = MainActor.assumeIsolated {
            Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
          }
          return passThrough ? Unmanaged.passUnretained(event) : nil
        }, userInfo: context
      )
    else {
      needsInputMonitoring = !inputMonitoringGranted
      lastIssue = localized(
        "Не удалось включить обработчик. Проверьте разрешения и перезапустите приложение.",
        "The keyboard handler could not start. Check permissions and reopen the app.")
      return
    }
    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
      CFMachPortInvalidate(created)
      return
    }
    tap = created
    source = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: created, enable: true)
    isRunning = CGEvent.tapIsEnabled(tap: created)
    lastIssue = nil
  }

  private func removeTap() {
    state.reset()
    reservedKeys.removeAll()
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
    isRunning = false
  }

  private func anotherKeyIsDown(excluding code: UInt16, flags: CGEventFlags) -> Bool {
    // Snapshot physical state at the start, including keys held before tap creation
    // and keys whose release was lost during a keyboard disconnect.
    for other in UInt16(0)..<128 where other != code && other != 57 {
      if CGEventSource.keyState(.combinedSessionState, key: other) { return true }
    }
    return TriggerKey.allCases.contains {
      $0 != .fn && $0.rawValue != code && $0.modifierMask.map { flags.rawValue & $0 != 0 } == true
    }
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      state.reset()
      reservedKeys.removeAll()
      isRunning = false
      // Reconcile on the next run-loop turn, outside the event-tap callback.
      DispatchQueue.main.async { [weak self] in self?.reconcile() }
      return true
    }
    guard desired, !suspended else { return true }
    guard !secureInputEnabled else {
      state.reset()
      return true
    }
    if type.rawValue == 14 || type == .leftMouseDown || type == .rightMouseDown
      || type == .otherMouseDown
    {
      state.cancelPress()
      return true
    }
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let down: Bool
    if type == .flagsChanged {
      guard let key = TriggerKey(rawValue: code), let mask = key.modifierMask else {
        state.cancelPress()
        return true
      }
      down = event.flags.rawValue & mask != 0
    } else {
      down = type == .keyDown
    }
    if code == state.trigger.rawValue { observedTrigger = true }
    if down {
      state.keyDown(
        code, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        anotherKeyIsDown: code == state.trigger.rawValue
          && anotherKeyIsDown(excluding: code, flags: event.flags))
    } else if state.keyUp(code) {
      // Synchronous selection before returning the release to the event stream.
      onRelease?()
    }
    // Modifier events stay untouched, preserving Fn+Delete and ordinary shortcuts.
    if code == state.trigger.rawValue && !state.trigger.isModifier {
      if down { reservedKeys.insert(code) } else { reservedKeys.remove(code) }
      return false
    }
    if !down && reservedKeys.remove(code) != nil { return false }
    return true
  }
}
