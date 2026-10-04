import AppKit
import SwiftUI

@main
enum OrbitShiftApp {
  @MainActor
  static func main() {
    if CommandLine.arguments.contains("--diagnostics") {
      Diagnostics.printStatus()
      return
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
  private var model: AppModel!
  private var item: NSStatusItem?
  private var window: NSWindow?
  private var permissionGuideScheduled = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    // A second launch should reveal the existing app, never create a second tap.
    if let identifier = Bundle.main.bundleIdentifier,
      let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
    {
      other.activate(options: [])
      NSApplication.shared.terminate(nil)
      return
    }
    model = AppModel(isDemo: AppIdentity.isDemo || AppIdentity.previewPath != nil)
    if let path = AppIdentity.previewPath {
      Task {
        do { try await PreviewRenderer.render(model: model, to: path) } catch {
          fputs("Preview failed: \(error.localizedDescription)\n", stderr)
          exit(1)
        }
        NSApplication.shared.terminate(nil)
      }
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.imagePosition = .imageOnly
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    self.item = item
    model.onStatusChange = { [weak self] in self?.refreshStatus() }
    configureMainMenu()
    model.start()
    refreshStatus()
    let firstLaunch = !UserDefaults.standard.bool(forKey: "hasOpenedSettings")
    if firstLaunch || model.isDemo || CommandLine.arguments.contains("--settings")
      || !model.accessibilityGranted
    {
      showSettings()
    }
  }

  func applicationWillTerminate(_ notification: Notification) { model?.stop() }

  func windowWillClose(_ notification: Notification) {
    guard let closed = notification.object as? NSWindow, closed === window else { return }
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  private func configureMainMenu() {
    let menu = NSMenu()
    let appMenu = NSMenu(title: AppIdentity.name)
    let applicationItem = NSMenuItem()
    applicationItem.submenu = appMenu
    menu.addItem(applicationItem)
    appMenu.addItem(
      withTitle: localized("Скрыть ", "Hide ") + AppIdentity.name,
      action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: localized("Завершить ", "Quit ") + AppIdentity.name,
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let windowMenu = NSMenu(title: localized("Окно", "Window"))
    let windowItem = NSMenuItem()
    windowItem.submenu = windowMenu
    menu.addItem(windowItem)
    windowMenu.addItem(
      withTitle: localized("Закрыть окно", "Close Window"),
      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowMenu.addItem(
      withTitle: localized("Свернуть", "Minimize"),
      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    NSApplication.shared.mainMenu = menu
    NSApplication.shared.windowsMenu = windowMenu
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showSettings()
    return true
  }

  func applicationDidBecomeActive(_ notification: Notification) { model?.refresh() }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let model else { return }
    model.refresh()
    menu.removeAllItems()
    if model.availableSources.isEmpty {
      menu.addItem(
        NSMenuItem(
          title: localized("Нет доступных источников ввода", "No input sources available"),
          action: nil, keyEquivalent: ""))
    }
    for source in model.availableSources {
      let entry = NSMenuItem(
        title: source.name, action: #selector(selectSource(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = source.id
      entry.image = InputSourceIndicator.image(for: source)
      entry.state = source.id == model.currentSource?.id ? .on : .off
      menu.addItem(entry)
    }
    menu.addItem(.separator())
    add(menu, localized("Настройки…", "Settings…"), #selector(showSettings), key: ",")
    add(
      menu,
      model.preferences.isPaused
        ? localized("Продолжить переключение", "Resume switching")
        : localized("Приостановить", "Pause switching"), #selector(togglePause))
    menu.addItem(.separator())
    add(menu, localized("Завершить ", "Quit ") + AppIdentity.name, #selector(quit), key: "q")
  }

  private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
    let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
    entry.target = self
    menu.addItem(entry)
  }

  private func refreshStatus() {
    let image = InputSourceIndicator.image(for: model.currentSource)
    if item?.button?.image !== image { item?.button?.image = image }
    item?.button?.setAccessibilityLabel(
      "\(AppIdentity.name): \(model.currentSource?.name ?? localized("Источник неизвестен", "Unknown input source"))"
    )
    item?.button?.setAccessibilityValue(model.status)
    item?.button?.toolTip =
      "\(AppIdentity.name) · \(model.status) · \(model.currentSource?.name ?? "—")"
    item?.button?.appearsDisabled = model.preferences.isPaused || !model.handlerRunning
    for entry in item?.menu?.items ?? [] {
      guard let id = entry.representedObject as? String else { continue }
      entry.state = id == model.currentSource?.id ? .on : .off
    }
    guard !model.isDemo, !permissionGuideScheduled else { return }
    permissionGuideScheduled = true
    // Leave the monitor's reconcile callback before requesting OS permissions.
    DispatchQueue.main.async { [weak self] in
      self?.permissionGuideScheduled = false
      self?.guidePermissionsIfNeeded()
    }
  }

  private func guidePermissionsIfNeeded() {
    guard let model, !model.isDemo, !model.preferences.isPaused else { return }
    // Recheck the live permission before presenting anything. A queued status
    // callback may predate the user's approval in System Settings.
    if !model.keyboard.accessibilityGranted {
      guard model.shouldGuideAccessibility else { return }
      presentSettings(page: .system)
      model.requestAccessibility()
      return
    }
    // Active event taps can work with Accessibility alone. Ask for Input Monitoring
    // only when macOS actually prevents the handler from starting without it.
    if model.needsInputMonitoring && model.shouldGuideInputMonitoring {
      presentSettings(page: .system)
      model.requestInputMonitoring()
    }
  }

  @objc private func selectSource(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    model.selectSource(id: id)
    if model.errorMessage != nil { showSettings() }
  }

  @objc private func togglePause() { model.setPaused(!model.preferences.isPaused) }
  @objc private func quit() { NSApplication.shared.terminate(nil) }

  @objc func showSettings() { presentSettings() }

  private func presentSettings(page: SettingsPage? = nil) {
    guard let model else { return }
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 840, height: 740),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = AppIdentity.name
      window.delegate = self
      window.contentView = NSHostingView(
        rootView: SettingsView(model: model, initialPage: page ?? .switching))
      window.minSize = NSSize(width: 800, height: 690)
      window.isReleasedWhenClosed = false
      window.hidesOnDeactivate = false
      window.setFrameAutosaveName("OrbitShiftSettings")
      window.center()
      self.window = window
    } else if let page {
      window?.contentView = NSHostingView(rootView: SettingsView(model: model, initialPage: page))
    }
    if !model.isDemo { UserDefaults.standard.set(true, forKey: "hasOpenedSettings") }
    // A regular settings window participates in macOS's normal window ordering.
    // Keep the background utility accessory-only after the user closes it.
    if NSApplication.shared.activationPolicy() != .regular {
      NSApplication.shared.setActivationPolicy(.regular)
    }
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
