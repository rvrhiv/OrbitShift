import Foundation

@MainActor
enum Diagnostics {
  static func printStatus() {
    let inputs = InputSourceController()
    let keyboard = KeyboardMonitor()
    defer { inputs.stop() }
    let report: [String: Any] = [
      "app": AppIdentity.name,
      "version": AppIdentity.version,
      "development": AppIdentity.isDevelopment,
      "accessibility": keyboard.accessibilityGranted,
      "inputMonitoring": keyboard.inputMonitoringGranted,
      "secureInput": keyboard.secureInputEnabled,
      "currentSource": inputs.currentSource()?.id ?? NSNull(),
      "sources": inputs.availableSources().map {
        ["id": $0.id, "name": $0.name, "language": $0.language]
      },
      "updatesEnabled": !AppIdentity.isDevelopment
        && (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap {
          Data(base64Encoded: $0)
        }?.count == 32,
    ]
    do {
      let data = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      print(String(decoding: data, as: UTF8.self))
    } catch {
      fputs("Diagnostics failed: \(error.localizedDescription)\n", stderr)
    }
  }
}
