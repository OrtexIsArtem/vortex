import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The settings tab: General, Activation and Features. Features lists the running features; each opens its own page.
struct SettingsView: View {
  @Bindable var store: StoreOf<ShellFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen

  var body: some View {
    Group {
      if store.settingsSection == .features, let feature = store.settingsPage {
        FeatureSettingsPage(store: store, feature: feature)
          .id(feature.id)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          Text("Settings", bundle: .module)
            .font(.system(size: 13, weight: .semibold))
            .frame(height: VortexMetrics.headerHeight)
            .padding(.leading, 10)

          SegmentedPicker(
            selection: $store.settingsSection,
            options: ShellFeature.SettingsSection.allCases
          ) { section in
            section.title
          }
          .frame(width: 320)
          .padding(.leading, 10)

          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              switch store.settingsSection {
              case .general: GeneralSettings(store: store)
              case .activation: ActivationSettings(store: store)
              case .features: FeatureList(store: store)
              }
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 6)
          }
        }
      }
    }
    .toggleStyle(.vortex)
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.settingsShown) }
    }
  }
}

private struct GeneralSettings: View {
  @Bindable var store: StoreOf<ShellFeature>

  var body: some View {
    SettingsRow(
      title: Text("Open at login", bundle: .module),
      caption: store.launchAtLogin == .requiresApproval
        ? Text("Allow Vortex in System Settings › General › Login Items & Extensions.", bundle: .module)
        : nil
    ) {
      HStack(spacing: 10) {
        if store.launchAtLogin == .requiresApproval {
          Button {
            store.send(.openLoginItemsTapped)
          } label: {
            Text("Open System Settings", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
        Toggle(isOn: Binding(get: { store.launchAtLogin == .enabled }, set: { store.send(.launchAtLoginChanged($0)) })) {
          Text("Open at login", bundle: .module)
        }
      }
    }

    SettingsRow(
      title: Text("Language", bundle: .module),
      caption: store.needsRestartForLanguage ? Text("Restart Vortex to apply the language.", bundle: .module) : nil
    ) {
      HStack(spacing: 10) {
        if store.needsRestartForLanguage {
          Button {
            store.send(.restartButtonTapped)
          } label: {
            Text("Restart", bundle: .module)
          }
          .buttonStyle(.primaryCapsule)
        }
        Picker(selection: $store.language) {
          Text("System", bundle: .module).tag(AppLanguage.system)
          Text(verbatim: "Українська").tag(AppLanguage.ukrainian)
          Text(verbatim: "English").tag(AppLanguage.english)
        } label: {
          Text("Language", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
      }
    }

    SettingsRow(title: Text("Theme", bundle: .module)) {
      SegmentedPicker(selection: $store.settings.theme, options: AppTheme.allCases) { theme in
        theme.title
      }
      .frame(width: 240)
    }

    SettingsRow(title: Text("Quit Vortex", bundle: .module)) {
      Button {
        store.send(.quitButtonTapped)
      } label: {
        Text("Quit", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
    }

    SettingsRow(
      title: Text("Version", bundle: .module),
      caption: Text("Opens the latest release in your browser. Vortex itself never goes online.", bundle: .module)
    ) {
      HStack(spacing: 10) {
        Text(verbatim: store.appVersion.short)
          .font(.system(size: 12).monospacedDigit())
          .foregroundStyle(VortexColor.secondaryText)
        Button {
          store.send(.checkForUpdatesTapped)
        } label: {
          Text("Check for Updates", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        // Its whole label; the caption beside it wraps instead.
        .fixedSize()
      }
    }
  }
}

private struct ActivationSettings: View {
  @Bindable var store: StoreOf<ShellFeature>

  var body: some View {
    SettingsRow(
      title: Text("Open on hover", bundle: .module),
      caption: Text("Hover over the notch to open Vortex.", bundle: .module),
      isOn: $store.settings.openOnHover
    )
    if store.settings.openOnHover {
      SettingsRow(title: Text("Delay", bundle: .module)) {
        DelaySlider(value: $store.settings.hoverDelay)
      }
    }

    SettingsRow(
      title: Text("Open on click", bundle: .module),
      caption: Text("Click the notch to open Vortex.", bundle: .module),
      isOn: $store.settings.openOnClick
    )

    SettingsRow(
      title: Text("Keyboard shortcut", bundle: .module),
      caption: Text("Opens and closes Vortex from anywhere.", bundle: .module)
    ) {
      HotkeyRecorder(.openVortex, label: Text("Keyboard shortcut", bundle: .module))
    }

    SettingsRow(title: Text("Close on click outside", bundle: .module), isOn: $store.settings.closeOnClickOutside)

    SettingsRow(
      title: Text("Close when the pointer leaves", bundle: .module),
      caption: Text("Only when Vortex opened as the pointer passed the notch.", bundle: .module),
      isOn: $store.settings.closeOnPointerLeave
    )
    if store.settings.closeOnPointerLeave {
      SettingsRow(title: Text("Delay", bundle: .module)) {
        DelaySlider(value: $store.settings.pointerLeaveDelay)
      }
    }

    SettingsRow(
      title: Text("Menu bar icon", bundle: .module),
      caption: store.isMenuBarIconRequired
        ? Text("Stays on while a display has no notch or the notch can’t open Vortex.", bundle: .module)
        : nil,
      isOn: Binding(
        get: { store.isMenuBarIconVisible },
        set: { store.send(.binding(.set(\.settings.showMenuBarIcon, $0))) }
      )
    )
    .disabled(store.isMenuBarIconRequired)
  }
}

/// The running features with something to set, in sidebar order, each a row onto its own page. Features are added and
/// removed in the catalog.
private struct FeatureList: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    let features = store.settingsFeatures
    if features.isEmpty {
      Text("Features you add with settings show them here", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.vertical, 14)
    } else {
      ForEach(features) { feature in
        FeatureRow(feature: feature, warning: store.state.permissionOff(for: feature)) {
          store.send(.settingsRowTapped(feature.id))
        }
      }
    }
  }
}

/// A feature in Settings › Features: its symbol, its name and a chevron, the whole row a button onto its page.
private struct FeatureRow: View {
  let feature: FeatureDescriptor
  /// A permission the feature needs is off: the yellow dot of its sidebar icon, with the same tooltip.
  let warning: Permission?
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          FeatureSymbol(symbol: feature.symbol)
            .overlay(alignment: .topTrailing) {
              if let warning {
                WarningMark(warning, style: .dot).offset(x: 3, y: -3)
              }
            }
          Text(feature.title)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(VortexColor.tertiaryText)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        Hairline()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A feature's page in Settings › Features: back to the list, the feature's name, the shortcut that opens Vortex on its
/// tab (none for a feature without a tab), then the feature's own settings with their permission rows, as the feature
/// makes them.
private struct FeatureSettingsPage: View {
  let store: StoreOf<ShellFeature>
  let feature: FeatureDescriptor

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      BackButton(title: Text("Features", bundle: .module)) { store.send(.settingsBackTapped) }

      HStack(spacing: 10) {
        FeatureSymbol(symbol: feature.symbol)
        Text(feature.title)
          .font(.system(size: 13, weight: .semibold))
          .accessibilityAddTraits(.isHeader)
      }
      // As tall as the segments of the list, so the first row starts where the list's first row does.
      .frame(height: 32)
      .padding(.leading, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if let shortcut = store.state.tabShortcut(feature.id) {
            SettingsRow(
              title: Text("Keyboard shortcut", bundle: .module),
              caption: Text("Opens Vortex right on the \(Text(feature.title)) tab.", bundle: .module)
            ) {
              HotkeyRecorder(shortcut, label: Text("Keyboard shortcut", bundle: .module))
            }
          }
          if let settings = FeatureViews.shared.settings(feature.id) {
            settings
          }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.vertical, 6)
      }
    }
  }
}

/// A feature's symbol on a small raised tile, as in the rows of Home's editor.
private struct FeatureSymbol: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 13))
      .foregroundStyle(VortexColor.primaryText)
      .frame(width: 28, height: 28)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
      .accessibilityHidden(true)
  }
}

/// Delay from 0 to 2 seconds in 0.1-second steps.
private struct DelaySlider: View {
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 10) {
      Slider(value: $value, in: ShellSettings.delayRange, step: 0.1)
        .controlSize(.small)
        .tint(VortexColor.accent)
        .frame(width: 160)
      Text("\(value.formatted(.number.precision(.fractionLength(1)))) s", bundle: .module)
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(VortexColor.secondaryText)
        .frame(width: 44, alignment: .trailing)
    }
  }
}

extension ShellFeature.SettingsSection {
  var title: Text {
    switch self {
    case .general: Text("General", bundle: .module)
    case .activation: Text("Activation", bundle: .module)
    case .features: Text("Features", bundle: .module)
    }
  }
}

extension AppTheme {
  var title: Text {
    switch self {
    // A key of its own, apart from the language's "System": Ukrainian agrees it with «тема», «Системна» as «Світла».
    case .system: Text(String(localized: "System (theme)", defaultValue: "System", bundle: .module, comment: "Theme: follows macOS's light or dark appearance"))
    case .light: Text("Light", bundle: .module)
    case .dark: Text("Dark", bundle: .module)
    }
  }
}
