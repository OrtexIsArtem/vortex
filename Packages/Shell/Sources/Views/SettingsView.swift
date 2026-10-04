import ComposableArchitecture
import FeatureRegistry
import SwiftUI
import VortexCore
import VortexPlatform

/// The settings tab: General, Activation and Features.
struct SettingsView: View {
  @Bindable var store: StoreOf<ShellFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Settings", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: VortexMetrics.headerHeight)
        .padding(.leading, 10)

      SegmentedPicker(selection: $store.settingsSection, options: ShellFeature.SettingsSection.allCases) { section in
        section.title
      }
      .frame(width: 320)
      .padding(.leading, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          switch store.settingsSection {
          case .general: GeneralSettings(store: store)
          case .activation: ActivationSettings(store: store)
          case .features: FeaturesSettings(store: store)
          }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.vertical, 6)
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
      title: Text("Launch at login", bundle: .module),
      caption: store.launchAtLogin == .requiresApproval
        ? Text("Allow Vortex in System Settings › General › Login Items.", bundle: .module)
        : nil
    ) {
      HStack(spacing: 10) {
        if store.launchAtLogin == .requiresApproval {
          Button {
            store.send(.openLoginItemsTapped)
          } label: {
            Text("Open Login Items", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
        Toggle(isOn: Binding(get: { store.launchAtLogin == .enabled }, set: { store.send(.launchAtLoginChanged($0)) })) {
          Text("Launch at login", bundle: .module)
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
  }
}

private struct ActivationSettings: View {
  @Bindable var store: StoreOf<ShellFeature>

  var body: some View {
    SettingsRow(
      title: Text("Open on hover", bundle: .module),
      caption: Text("Hover the notch to open Vortex.", bundle: .module),
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
    if !store.sidebarFeatures.isEmpty {
      Text("Shortcuts that open Vortex right on a tab:", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 14)
        .padding(.bottom, 2)
      ForEach(store.sidebarFeatures) { feature in
        SettingsRow(title: Text(feature.title), symbol: feature.symbol) {
          HotkeyRecorder(.open(feature.id), label: Text(feature.title))
        }
      }
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

private struct FeaturesSettings: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    if store.features.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("No features yet", bundle: .module)
          .font(.system(size: 13, weight: .medium))
        Text("Features appear here as they are added to Vortex.", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
      }
      .padding(.vertical, 14)
    } else {
      Text("Features you turn off disappear from the sidebar. Drag a row onto another to reorder.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.vertical, 10)

      ForEach(store.orderedFeatures) { feature in
        SettingsRow(
          title: Text(feature.title),
          symbol: feature.symbol,
          isOn: Binding(
            get: { !store.settings.disabledFeatures.contains(feature.id) },
            set: { store.send(.featureEnabledChanged(feature.id, isEnabled: $0)) }
          )
        )
        .reorderable(feature.id, in: store)
      }

      ForEach(store.sidebarFeatures) { feature in
        if let settings = FeatureRegistry.module(for: feature.id)?.makeSettings() {
          Text(feature.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VortexColor.secondaryText)
            .padding(.top, 18)
            .padding(.bottom, 4)
          settings
        }
      }
    }
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
    case .system: Text("System", bundle: .module)
    case .light: Text("Light", bundle: .module)
    case .dark: Text("Dark", bundle: .module)
    }
  }
}
