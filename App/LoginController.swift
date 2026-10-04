import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class LoginController {
  private(set) var isEnabled = false
  private(set) var needsApproval = false
  private(set) var message: String?
  private(set) var isChanging = false
  let isDemo: Bool

  init(isDemo: Bool) {
    self.isDemo = isDemo
    refresh()
  }

  func refresh() {
    guard !isDemo else { return }
    isEnabled = SMAppService.mainApp.status == .enabled
    needsApproval = SMAppService.mainApp.status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
    guard !isDemo, !isChanging else { return }
    isChanging = true
    message = nil
    Task {
      defer {
        isChanging = false
        refresh()
      }
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try await SMAppService.mainApp.unregister()
        }
      } catch { message = error.localizedDescription }
    }
  }

  func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
