import Foundation
import IOKit.hid

/// Observes connection changes only. It never opens devices or reads HID input.
@MainActor
final class KeyboardDeviceObserver {
  private var manager: IOHIDManager?
  var onChange: (() -> Void)?

  func start() {
    guard manager == nil else { return }
    let manager = IOHIDManagerCreate(
      kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
    IOHIDManagerSetDeviceMatching(
      manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOHIDDeviceCallback = { context, _, _, _ in
      guard let context else { return }
      MainActor.assumeIsolated {
        Unmanaged<KeyboardDeviceObserver>.fromOpaque(context).takeUnretainedValue().onChange?()
      }
    }
    IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    self.manager = manager
  }

  func stop() {
    guard let manager else { return }
    IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
    IOHIDManagerUnscheduleFromRunLoop(
      manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    self.manager = nil
  }
}
