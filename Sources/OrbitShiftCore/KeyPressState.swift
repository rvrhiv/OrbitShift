/// A physical press is eligible only if it starts alone and remains alone.
/// This type never receives text, characters, or application information.
public struct KeyPressState: Sendable {
  public private(set) var trigger: TriggerKey
  private var triggerIsDown = false
  private var eligible = false

  public init(trigger: TriggerKey) { self.trigger = trigger }

  public mutating func reset(trigger: TriggerKey? = nil) {
    if let trigger { self.trigger = trigger }
    triggerIsDown = false
    eligible = false
  }

  public mutating func keyDown(_ code: UInt16, isRepeat: Bool, anotherKeyIsDown: Bool) {
    guard code == trigger.rawValue else {
      eligible = false
      return
    }
    guard !triggerIsDown else {
      if !isRepeat { eligible = false }
      return
    }
    triggerIsDown = true
    eligible = !isRepeat && !anotherKeyIsDown
  }

  public mutating func keyUp(_ code: UInt16) -> Bool {
    guard code == trigger.rawValue else { return false }
    let shouldSwitch = triggerIsDown && eligible
    triggerIsDown = false
    eligible = false
    return shouldSwitch
  }

  public mutating func cancelPress() { eligible = false }
}
