import OrbitShiftCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
  case switching, system, updates
  var id: Self { self }
  var title: String {
    switch self {
    case .switching: localized("Переключение", "Switching")
    case .system: localized("Система", "System")
    case .updates: localized("Обновления", "Updates")
    }
  }
  var icon: String {
    switch self {
    case .switching: "globe"
    case .system: "slider.horizontal.3"
    case .updates: "arrow.down.circle"
    }
  }
}

struct SettingsView: View {
  @Bindable var model: AppModel
  @State private var page: SettingsPage = .switching
  init(model: AppModel, initialPage: SettingsPage = .switching) {
    self.model = model
    _page = State(initialValue: initialPage)
  }

  private let accent = Color(red: 0.47, green: 0.38, blue: 0.91)

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header
          if let error = model.errorMessage {
            notice(error, icon: "exclamationmark.triangle", tint: .orange)
          }
          switch page {
          case .switching: switching
          case .system: system
          case .updates: updates
          }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .tint(accent)
    .frame(minWidth: 780, idealWidth: 840, minHeight: 650, idealHeight: 720)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 10) {
        OrbitMark().frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 3) {
          Text("OrbitShift").font(.system(size: 17, weight: .semibold))
          Text(AppIdentity.isDevelopment ? "DEVELOPMENT" : "YOUR LANGUAGES. ONE KEY.")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.8).foregroundStyle(.secondary)
        }
      }
      VStack(spacing: 5) {
        ForEach(SettingsPage.allCases) { item in
          Button {
            page = item
          } label: {
            Label(item.title, systemImage: item.icon)
              .font(.system(size: 13, weight: page == item ? .semibold : .regular))
              .frame(maxWidth: .infinity, alignment: .leading).padding(10)
              .background(
                page == item ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8)
              )
              .foregroundStyle(page == item ? accent : .primary)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(page == item ? [.isSelected] : [])
        }
      }
      Spacer()
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Circle().fill(
            model.handlerRunning && !model.preferences.isPaused ? Color.green : Color.orange
          )
          .frame(width: 6, height: 6)
          Text(model.status).font(.system(size: 11))
        }
        Text(AppIdentity.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(
          .tertiary)
      }
    }
    .padding(18).frame(width: 194)
    .background(.regularMaterial)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(page.title).font(.system(size: 26, weight: .semibold))
      Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
    }
  }

  private var subtitle: String {
    switch page {
    case .switching:
      localized(
        "Ваши языки. Одна клавиша. Без лишней паузы.", "Your languages. One key. Keep your flow.")
    case .system:
      localized(
        "Разрешения и запуск вместе с вашим Mac.", "Permissions and a smooth start with your Mac.")
    case .updates: localized("Новые версии — когда вы готовы.", "New versions, when you’re ready.")
    }
  }

  private var switching: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 16) {
        Image(systemName: "globe").font(.system(size: 25)).foregroundStyle(accent)
          .frame(width: 50, height: 50).background(
            accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 4) {
          Text(localized("СЕЙЧАС В macOS", "CURRENT IN macOS"))
            .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
          Text(model.currentSource?.name ?? "—").font(.system(size: 21, weight: .medium))
        }
        Spacer()
        Toggle(
          localized("Пауза", "Pause"),
          isOn: Binding(
            get: { model.preferences.isPaused }, set: { model.setPaused($0) })
        )
        .toggleStyle(.switch).fixedSize()
      }.card()

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(localized("Клавиша переключения", "Switching key"), systemImage: "keyboard").font(
            .headline)
          Spacer()
          Menu {
            ForEach(TriggerKey.allCases) { key in
              Button {
                model.setTrigger(key)
              } label: {
                if model.preferences.trigger == key {
                  Label(key.title, systemImage: "checkmark")
                } else {
                  Text(key.title)
                }
              }
            }
          } label: {
            Text(model.preferences.trigger.title).frame(maxWidth: .infinity)
          }
          .frame(width: 188)
          .accessibilityLabel(localized("Клавиша переключения", "Switching key"))
          .accessibilityValue(model.preferences.trigger.title)
        }
        Text(
          localized(
            "Нажмите и отпустите клавишу отдельно. Сочетания с другими клавишами не переключают язык.",
            "Press and release the key on its own. Keyboard combinations won’t switch the input source."
          )
        )
        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
        if model.preferences.trigger == .fn {
          Divider()
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 7) {
              Text(
                localized(
                  "В настройках клавиатуры выберите «Нажать 🌐 для: Ничего не делать».",
                  "In Keyboard settings, set “Press 🌐 key to” to “Do Nothing”.")
              )
              .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
              Button(localized("Настройки клавиатуры ↗", "Open Keyboard settings ↗")) {
                SystemSettings.keyboard()
              }
              .buttonStyle(.link).font(.system(size: 12))
            }
          }
        } else if !model.preferences.trigger.isModifier {
          Text(
            localized(
              "Эта клавиша резервируется для OrbitShift; её обычное действие и сочетания не передаются приложениям.",
              "This key is reserved for OrbitShift; its usual action and shortcuts are not sent to other apps."
            )
          )
          .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        if model.handlerRunning && !model.triggerObserved && !model.isDemo {
          Text(
            localized(
              "Нажмите выбранную клавишу для проверки: её события ещё не получены.",
              "Press the selected key to verify detection: no events from it have been received yet."
            )
          )
          .font(.system(size: 11)).foregroundStyle(.orange)
        }
      }.card()

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(
            localized("Порядок языков", "Your input cycle"),
            systemImage: "arrow.triangle.2.circlepath"
          ).font(.headline)
          Spacer()
          Menu {
            ForEach(model.addableSources) { source in
              Button(source.name) { model.addSource(source) }
            }
            if !model.addableSources.isEmpty { Divider() }
            Button(localized("Добавить язык в macOS…", "Add a language in macOS…")) {
              SystemSettings.keyboard()
            }
            Button(localized("Обновить список", "Refresh sources")) { model.refresh() }
          } label: {
            Label(localized("Добавить", "Add"), systemImage: "plus")
          }
          .fixedSize()
        }
        if model.cycleSources.isEmpty {
          Text(
            localized(
              "Добавьте хотя бы два источника для переключения по кругу.",
              "Add at least two input sources to cycle between them.")
          )
          .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
        }
        VStack(spacing: 0) {
          ForEach(Array(model.cycleSources.enumerated()), id: \.element.id) { index, source in
            sourceRow(source, index: index)
            if index < model.cycleSources.count - 1 { Divider().padding(.leading, 47) }
          }
        }
        Text(
          localized(
            "После последнего — снова первый. Внешние изменения языка учитываются автоматически.",
            "After the last source, back to the first. Changes made in macOS are picked up automatically."
          )
        )
        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }.card()

      if !model.accessibilityGranted || model.keyboardIssue != nil {
        Button {
          page = .system
        } label: {
          Label(
            localized("Завершить настройку разрешений", "Finish permission setup"),
            systemImage: "hand.raised"
          )
          .frame(maxWidth: .infinity)
        }.controlSize(.large)
      }
      if model.isDemo {
        notice(
          localized(
            "Демонстрация: клавиатура, системные настройки и обновления не изменяются.",
            "Preview mode: keyboard handling, system settings and updates are inactive."),
          icon: "eye", tint: accent)
      }
    }
  }

  private func sourceRow(_ source: InputSource, index: Int) -> some View {
    HStack(spacing: 12) {
      Text(source.language.isEmpty ? "—" : String(source.language.prefix(2)).uppercased())
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .frame(width: 34, height: 28).background(
          accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 2) {
        Text(source.name).font(.system(size: 13, weight: .medium))
        if !source.isAvailable {
          Text(localized("Недоступен — пропускается", "Unavailable — skipped")).font(
            .system(size: 10)
          ).foregroundStyle(.orange)
        }
      }
      if source.id == model.currentSource?.id {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(accent)
          .accessibilityLabel(localized("Текущий источник macOS", "Current macOS input source"))
      }
      Spacer()
      Button {
        model.moveSource(source.id, by: -1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .disabled(index == 0).help(localized("Выше", "Move up"))
      .accessibilityLabel(localized("Выше: ", "Move up: ") + source.name)
      Button {
        model.moveSource(source.id, by: 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .disabled(index == model.cycleSources.count - 1).help(localized("Ниже", "Move down"))
      .accessibilityLabel(localized("Ниже: ", "Move down: ") + source.name)
      Button {
        model.removeSource(source.id)
      } label: {
        Image(systemName: "minus.circle")
      }
      .help(localized("Убрать из цикла", "Remove from cycle"))
      .accessibilityLabel(localized("Убрать: ", "Remove: ") + source.name)
    }.buttonStyle(.borderless).padding(.vertical, 9)
  }

  private var system: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 16) {
        Label(localized("Доступ к клавиатуре", "Keyboard access"), systemImage: "hand.raised").font(
          .headline)
        permissionRow(
          title: localized("Универсальный доступ", "Accessibility"),
          granted: model.accessibilityGranted
        ) {
          model.requestAccessibility()
        }
        if model.needsInputMonitoring || model.inputMonitoringGranted {
          Divider()
          permissionRow(
            title: localized("Мониторинг ввода", "Input Monitoring"),
            granted: model.inputMonitoringGranted
          ) {
            model.requestInputMonitoring()
          }
        }
        if !model.accessibilityGranted {
          notice(
            localized(
              "Нажмите «Разрешить…». В системном запросе перейдите к настройкам и включите переключатель справа от «\(AppIdentity.name).app». Путь: Конфиденциальность и безопасность → Универсальный доступ. Если приложения нет в списке, нажмите + и выберите его. После разрешения OrbitShift включит обработчик автоматически.",
              "Choose “Allow…”, open settings from the macOS prompt, and turn on the switch next to “\(AppIdentity.name).app”. Path: Privacy & Security → Accessibility. If the app is missing, use + to add it. OrbitShift will start keyboard handling after access is granted."
            ),
            icon: "hand.raised", tint: .orange)
          Text(
            localized(
              "При переходе с версии со старой подписью доступ нужно выдать заново один раз. Если переключатель уже включён, а доступа нет, удалите старую запись кнопкой − и добавьте текущую копию кнопкой +. Следующие сборки с тем же сертификатом сохраняют разрешение.",
              "When upgrading from the old signing method, grant access once more. If the switch is already on but access is missing, remove the old entry with − and add the current copy with +. Later builds signed with the same certificate keep the permission."
            )
          )
          .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
          Button(localized("Показать приложение в Finder", "Show app in Finder")) {
            SystemSettings.revealApplication()
          }
          .buttonStyle(.link).disabled(model.isDemo)
        }
        Text(
          localized(
            "Универсальный доступ нужен обработчику клавиш. Если macOS дополнительно запросит мониторинг ввода, разрешите его и перезапустите приложение. Текст не сохраняется.",
            "Accessibility enables keyboard handling. If macOS also asks for Input Monitoring, grant it and reopen the app. Typed text is never stored."
          )
        )
        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
        if let issue = model.keyboardIssue { notice(issue, icon: "info.circle", tint: .orange) }
        HStack {
          Label(
            model.handlerRunning
              ? localized("Обработчик включён", "Keyboard handler is active")
              : localized("Обработчик выключен", "Keyboard handler is inactive"),
            systemImage: model.handlerRunning ? "checkmark.circle.fill" : "circle.dashed"
          )
          .font(.system(size: 12)).foregroundStyle(model.handlerRunning ? .green : .secondary)
          Spacer()
          Button(localized("Проверить снова", "Check again")) { model.refresh() }
        }
      }.card()
      VStack(alignment: .leading, spacing: 12) {
        Toggle(isOn: Binding(get: { model.login.isEnabled }, set: { model.login.setEnabled($0) })) {
          Label(localized("Запускать при входе", "Launch at login"), systemImage: "power").font(
            .headline)
        }.toggleStyle(.switch).disabled(model.isDemo || model.login.isChanging)
        Text(
          localized(
            "OrbitShift будет готов после входа в учётную запись macOS.",
            "OrbitShift will be ready when you sign in to your Mac.")
        )
        .font(.system(size: 12)).foregroundStyle(.secondary)
        if model.login.needsApproval {
          Button(localized("Подтвердить в настройках macOS…", "Approve in macOS settings…")) {
            model.login.openSettings()
          }
        }
        if let message = model.login.message {
          Text(message).font(.system(size: 12)).foregroundStyle(.orange)
        }
      }.card()
      notice(
        localized(
          "Если Fn / Globe не определяется, сначала отключите её штатное действие в настройках клавиатуры. Проверка нажатия не записывает вводимый текст.",
          "If Fn / Globe is not detected, first disable its built-in action in Keyboard settings. Key detection does not record typed text."
        ), icon: "keyboard", tint: accent)
    }
  }

  private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void)
    -> some View
  {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "lock.circle").foregroundStyle(
        granted ? .green : .orange)
      Text(title).font(.system(size: 13))
      Spacer()
      if granted {
        Text(localized("Разрешено", "Allowed")).font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        Button(localized("Разрешить…", "Allow…"), action: action).disabled(model.isDemo)
      }
    }
  }

  private var updates: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 14) {
          OrbitMark().frame(width: 56, height: 56)
          VStack(alignment: .leading, spacing: 5) {
            Text(AppIdentity.name).font(.system(size: 19, weight: .semibold))
            Text(AppIdentity.version).font(.system(size: 12, design: .monospaced)).foregroundStyle(
              .secondary)
          }
        }
        Divider()
        Text(model.updates.status).font(.headline)
        if let version = model.updates.availableVersion {
          Text(localized("Новая версия: ", "New version: ") + version).font(.system(size: 13))
        }
        if let progress = model.updates.progress {
          ProgressView(value: progress)
        } else if model.updates.isBusy {
          ProgressView().controlSize(.small)
        }
        if let message = model.updates.message {
          Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        if AppIdentity.isDevelopment {
          Text(
            localized(
              "Dev-сборки обновляются локальной сборкой. Официальный релиз не заменит эту версию; настройки Dev хранятся отдельно.",
              "Development builds are updated locally. Official releases won’t replace this app; Dev settings are stored separately."
            )
          )
          .font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
          Toggle(
            localized("Проверять автоматически", "Automatically check for updates"),
            isOn: Binding(
              get: { model.updates.automaticChecks }, set: { model.updates.setAutomaticChecks($0) })
          )
          .disabled(model.updates.phase == .disabled || model.isDemo)
          HStack {
            Button(localized("Проверить обновления", "Check for updates")) { model.updates.check() }
              .disabled(!model.updates.canCheck || model.updates.isBusy)
            if model.updates.canInstall {
              Button(localized("Установить и перезапустить", "Install and relaunch")) {
                model.updates.install()
              }
              .buttonStyle(.borderedProminent)
            }
            if model.updates.canCancel {
              Button(localized("Отменить", "Cancel")) { model.updates.cancel() }
            }
          }
        }
        Link(
          localized("Релизы на GitHub ↗", "Releases on GitHub ↗"),
          destination: UpdateController.releases
        )
        .font(.system(size: 12))
      }.card()
      notice(
        localized(
          "Проверка обновлений не перезапускает приложение. Установка подписанного обновления начинается только после подтверждения.",
          "Checking for updates never restarts the app. A signed update is installed only after your confirmation."
        ), icon: "checkmark.shield", tint: accent)
    }
  }

  private func notice(_ text: String, icon: String, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon).foregroundStyle(tint)
      Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
  }
}

extension View {
  fileprivate func card() -> some View {
    self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
      .overlay(
        RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
  }
}

struct OrbitMark: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12)
        .fill(
          LinearGradient(
            colors: [
              Color(red: 0.50, green: 0.41, blue: 0.93), Color(red: 0.28, green: 0.24, blue: 0.66),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
      Image(systemName: "globe").font(.system(size: 24, weight: .light)).foregroundStyle(.white)
      Circle().fill(.white).frame(width: 6, height: 6).offset(x: 12, y: -12)
    }.accessibilityHidden(true)
  }
}
