import Foundation
import OrbitShiftCore

enum AppIdentity {
  static var isDevelopment: Bool {
    Bundle.main.object(forInfoDictionaryKey: "OrbitShiftBuildFlavor") as? String != "distribution"
  }
  static var name: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "OrbitShift Dev"
  }
  static var version: String {
    let base =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    guard isDevelopment else { return base }
    let number =
      Bundle.main.object(forInfoDictionaryKey: "OrbitShiftDevelopmentBuild") as? String ?? "local"
    return "\(base)-dev.\(number)"
  }
  static var isDemo: Bool { CommandLine.arguments.contains("--demo") }
  static var previewPath: String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
      CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
  }
  static var usesRussian: Bool {
    if let index = CommandLine.arguments.firstIndex(of: "--language"),
      CommandLine.arguments.indices.contains(index + 1)
    {
      return CommandLine.arguments[index + 1] == "ru"
    }
    return Locale.preferredLanguages.first?.hasPrefix("ru") == true
  }
}

func localized(_ russian: String, _ english: String) -> String {
  AppIdentity.usesRussian ? russian : english
}

extension TriggerKey {
  var title: String {
    switch self {
    case .fn: "Fn / Globe"
    case .leftShift: localized("Левый Shift  ⇧", "Left Shift  ⇧")
    case .rightShift: localized("Правый Shift  ⇧", "Right Shift  ⇧")
    case .leftControl: localized("Левый Control  ⌃", "Left Control  ⌃")
    case .rightControl: localized("Правый Control  ⌃", "Right Control  ⌃")
    case .leftOption: localized("Левый Option  ⌥", "Left Option  ⌥")
    case .rightOption: localized("Правый Option  ⌥", "Right Option  ⌥")
    case .leftCommand: localized("Левый Command  ⌘", "Left Command  ⌘")
    case .rightCommand: localized("Правый Command  ⌘", "Right Command  ⌘")
    default: symbol
    }
  }
}
