import AppKit
import Foundation
import Observation
import OrbitShiftCore

@MainActor @Observable
final class AppModel {
  var preferences: Preferences
  private(set) var availableSources: [InputSource] = []
  private(set) var currentSource: InputSource?
  private(set) var handlerRunning = false
  private(set) var accessibilityGranted = false
  private(set) var inputMonitoringGranted = false
  private(set) var needsInputMonitoring = false
  private(set) var triggerObserved = false
  private(set) var keyboardIssue: String?
  var errorMessage: String?
  let isDemo: Bool
  let login: LoginController
  let updates: UpdateController
  @ObservationIgnored let keyboard = KeyboardMonitor()
  @ObservationIgnored private let inputs = InputSourceController()
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var preferenceWritesEnabled = true
  @ObservationIgnored var onStatusChange: (() -> Void)?

  init(isDemo: Bool) {
    self.isDemo = isDemo
    defaults = .standard
    // Older local builds already presented setup before this marker existed.
    // Keep their recovery user initiated instead of reopening macOS settings.
    if !isDemo, defaults.bool(forKey: "hasOpenedSettings"),
      defaults.object(forKey: "hasPresentedAccessibilityGuide") == nil
    {
      defaults.set(true, forKey: "hasPresentedAccessibilityGuide")
    }
    login = LoginController(isDemo: isDemo)
    updates = UpdateController(isDemo: isDemo)
    let initial = isDemo ? Self.demoSources : inputs.availableSources()
    preferences = Preferences(sourceIDs: initial.map(\.id))
    if !isDemo, let data = defaults.data(forKey: "preferences.v1") {
      do {
        let stored = try JSONDecoder().decode(Preferences.self, from: data)
        guard stored.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        preferences = stored
      } catch {
        // Preserve unreadable/future preferences instead of overwriting them on startup.
        preferenceWritesEnabled = false
        errorMessage = localized(
          "Не удалось прочитать настройки. Они сохранены без изменений; новые настройки действуют до выхода.",
          "Saved settings could not be read. They are preserved; changes in this session will not be saved."
        )
      }
    }
    availableSources = initial
    currentSource = isDemo ? initial.first : inputs.currentSource()
    rememberSourceNames()
    if isDemo {
      handlerRunning = true
      accessibilityGranted = true
      inputMonitoringGranted = true
      triggerObserved = true
    }
  }

  static let demoSources = [
    InputSource(id: "demo.en", name: "ABC", language: "en"),
    InputSource(id: "demo.ru", name: "Русская", language: "ru"),
    InputSource(id: "demo.de", name: "Deutsch", language: "de"),
  ]

  var cycleSources: [InputSource] {
    var seen = Set<String>()
    return preferences.sourceIDs.filter { seen.insert($0).inserted }.map { id in
      availableSources.first(where: { $0.id == id })
        ?? InputSource(
          id: id, name: preferences.sourceNames[id] ?? id, language: "", isAvailable: false)
    }
  }

  var addableSources: [InputSource] {
    availableSources.filter { !preferences.sourceIDs.contains($0.id) }
  }

  var status: String {
    if isDemo { return localized("Демонстрация", "Preview") }
    if preferences.isPaused { return localized("На паузе", "Paused") }
    if !accessibilityGranted { return localized("Нужно разрешение", "Permission needed") }
    if !handlerRunning { return localized("Переключение недоступно", "Switching unavailable") }
    if cycleSources.filter(\.isAvailable).isEmpty {
      return localized("Добавьте источники", "Add input sources")
    }
    if !triggerObserved {
      return localized("Нажмите выбранную клавишу", "Press your switching key")
    }
    return localized("Готово к переключению", "Ready to switch")
  }

  func start() {
    guard !isDemo else { return }
    inputs.onChange = { [weak self] in self?.refreshSources() }
    keyboard.onRelease = { [weak self] in self?.switchToNextSource() }
    keyboard.onStatusChange = { [weak self] in self?.refreshKeyboardStatus() }
    keyboard.start(trigger: preferences.trigger, enabled: !preferences.isPaused)
    updates.start()
    refreshSources()
  }

  func stop() {
    keyboard.stop()
    inputs.stop()
  }

  func refresh() {
    guard !isDemo else { return }
    refreshSources()
    keyboard.reconcile()
    login.refresh()
  }

  var shouldGuideAccessibility: Bool {
    !keyboard.accessibilityGranted && !defaults.bool(forKey: "hasPresentedAccessibilityGuide")
  }

  var shouldGuideInputMonitoring: Bool {
    !keyboard.inputMonitoringGranted && !defaults.bool(forKey: "hasPresentedInputMonitoringGuide")
  }

  func requestAccessibility() {
    guard !isDemo else { return }
    defaults.set(true, forKey: "hasPresentedAccessibilityGuide")
    guard !keyboard.accessibilityGranted else {
      keyboard.reconcile()
      return
    }
    // The native request registers this app in macOS's permission list.
    // Its own button opens System Settings; opening that URL here would duplicate it.
    keyboard.requestAccessibility()
  }

  func requestInputMonitoring() {
    guard !isDemo else { return }
    defaults.set(true, forKey: "hasPresentedInputMonitoringGuide")
    guard !keyboard.inputMonitoringGranted else {
      keyboard.reconcile()
      return
    }
    keyboard.requestInputMonitoring()
  }

  func setTrigger(_ trigger: TriggerKey) {
    preferences.trigger = trigger
    if !isDemo { keyboard.configure(trigger: trigger, enabled: !preferences.isPaused) }
    persist()
  }

  func setPaused(_ paused: Bool) {
    preferences.isPaused = paused
    if !isDemo { keyboard.configure(trigger: preferences.trigger, enabled: !paused) }
    persist()
  }

  func addSource(_ source: InputSource) {
    guard !preferences.sourceIDs.contains(source.id) else { return }
    preferences.sourceIDs.append(source.id)
    preferences.sourceNames[source.id] = source.name
    persist()
  }

  func removeSource(_ id: String) {
    preferences.sourceIDs.removeAll { $0 == id }
    persist()
  }

  func moveSource(_ id: String, by offset: Int) {
    guard let index = preferences.sourceIDs.firstIndex(of: id),
      preferences.sourceIDs.indices.contains(index + offset)
    else { return }
    preferences.sourceIDs.swapAt(index, index + offset)
    persist()
  }

  func switchToNextSource() {
    guard !preferences.isPaused else { return }
    if isDemo {
      if let next = InputSourceCycle.next(
        currentID: currentSource?.id,
        orderedIDs: preferences.sourceIDs, availableIDs: Set(availableSources.map(\.id)))
      {
        currentSource = availableSources.first { $0.id == next }
      }
      return
    }
    // Re-read both lists at release time; notifications may still be in the queue.
    let available = inputs.availableSources()
    let current = inputs.currentSource()
    guard
      let next = InputSourceCycle.next(
        currentID: current?.id,
        orderedIDs: preferences.sourceIDs, availableIDs: Set(available.map(\.id)))
    else { return }
    do {
      try inputs.select(id: next)
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
    refreshSources()
  }

  private func refreshSources() {
    availableSources = inputs.availableSources()
    currentSource = inputs.currentSource()
    rememberSourceNames()
    onStatusChange?()
  }

  private func rememberSourceNames() {
    var changed = false
    for source in availableSources where preferences.sourceIDs.contains(source.id) {
      if preferences.sourceNames[source.id] != source.name {
        preferences.sourceNames[source.id] = source.name
        changed = true
      }
    }
    if changed { persist() }
  }

  private func refreshKeyboardStatus() {
    handlerRunning = keyboard.isRunning
    accessibilityGranted = keyboard.accessibilityGranted
    inputMonitoringGranted = keyboard.inputMonitoringGranted
    needsInputMonitoring = keyboard.needsInputMonitoring
    triggerObserved = keyboard.observedTrigger
    keyboardIssue = keyboard.lastIssue
    // Once access has been granted or guidance shown, recovery is user initiated.
    // In particular, rebuilding an ad-hoc signed Dev app must not open macOS
    // settings on every launch while its old permission record is still visible.
    if accessibilityGranted && !defaults.bool(forKey: "hasPresentedAccessibilityGuide") {
      defaults.set(true, forKey: "hasPresentedAccessibilityGuide")
    }
    if inputMonitoringGranted && !defaults.bool(forKey: "hasPresentedInputMonitoringGuide") {
      defaults.set(true, forKey: "hasPresentedInputMonitoringGuide")
    }
    onStatusChange?()
  }

  private func persist() {
    guard !isDemo, preferenceWritesEnabled else { return }
    do { defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences.v1") } catch {
      errorMessage = error.localizedDescription
    }
    onStatusChange?()
  }
}
