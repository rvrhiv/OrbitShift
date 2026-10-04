/// The supported physical keys. Printable keys and lock/media keys are deliberately
/// excluded: reserving them would lose text or require emulating system actions.
public enum TriggerKey: UInt16, Codable, CaseIterable, Sendable, Identifiable {
  case fn = 63
  case leftShift = 56
  case rightShift = 60
  case leftControl = 59
  case rightControl = 62
  case leftOption = 58
  case rightOption = 61
  case leftCommand = 55
  case rightCommand = 54
  case f13 = 105
  case f14 = 107
  case f15 = 113
  case f16 = 106
  case f17 = 64
  case f18 = 79
  case f19 = 80

  public var id: UInt16 { rawValue }
  public var isModifier: Bool { modifierMask != nil }

  /// Device-dependent bits from IOKit/hidsystem/IOLLEvent.h distinguish both sides.
  /// The aggregate shift/command flags cannot distinguish left from right.
  public var modifierMask: UInt64? {
    switch self {
    case .fn: 0x0080_0000
    case .leftControl: 0x0000_0001
    case .rightControl: 0x0000_2000
    case .leftShift: 0x0000_0002
    case .rightShift: 0x0000_0004
    case .leftCommand: 0x0000_0008
    case .rightCommand: 0x0000_0010
    case .leftOption: 0x0000_0020
    case .rightOption: 0x0000_0040
    default: nil
    }
  }

  public var symbol: String {
    switch self {
    case .fn: "fn / 🌐"
    case .leftShift, .rightShift: "⇧"
    case .leftControl, .rightControl: "⌃"
    case .leftOption, .rightOption: "⌥"
    case .leftCommand, .rightCommand: "⌘"
    case .f13: "F13"
    case .f14: "F14"
    case .f15: "F15"
    case .f16: "F16"
    case .f17: "F17"
    case .f18: "F18"
    case .f19: "F19"
    }
  }
}
