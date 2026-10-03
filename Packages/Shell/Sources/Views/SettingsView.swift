import ComposableArchitecture
import FeatureRegistry
import SwiftUI
import VortexCore
import VortexPlatform

/// The settings tab: General, Activation and Features.
struct SettingsView: View {
  @Bindable var store: StoreOf<ShellFeature>

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
  }
}

private struct GeneralSettings: View {
  @Bindable var store: StoreOf<ShellFeature>

  var body: some View {
    SettingsRow(title: Text("Launch at login", bundle: .module)) {
      SwitchToggle(
        isOn: Binding(get: { store.launchAtLogin }, set: { store.send(.launchAtLoginChanged($0)) }),
        label: Text("Launch at login", bundle: .module)
      )
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
        Picker(selection: $store.settings.language) {
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
  }
}

private struct ActivationSettings: View {
  @Bindable var store: StoreOf<ShellFeature>

  var body: some View {
    SettingsRow(
      title: Text("Open on hover", bundle: .module),
      caption: Text("Hover the notch to open Vortex.", bundle: .module)
    ) {
      SwitchToggle(isOn: $store.settings.openOnHover, label: Text("Open on hover", bundle: .module))
    }
    if store.settings.openOnHover {
      SettingsRow(title: Text("Delay", bundle: .module)) {
        DelaySlider(value: $store.settings.hoverDelay)
      }
    }

    SettingsRow(
      title: Text("Open on click", bundle: .module),
      caption: Text("Click the notch to open Vortex.", bundle: .module)
    ) {
      SwitchToggle(isOn: $store.settings.openOnClick, label: Text("Open on click", bundle: .module))
    }

    SettingsRow(
      title: Text("Keyboard shortcut", bundle: .module),
      caption: Text("Opens and closes Vortex from anywhere.", bundle: .module)
    ) {
      HotkeyRecorder(.openVortex)
    }

    SettingsRow(title: Text("Close on click outside", bundle: .module)) {
      SwitchToggle(isOn: $store.settings.closeOnClickOutside, label: Text("Close on click outside", bundle: .module))
    }

    SettingsRow(
      title: Text("Close when the pointer leaves", bundle: .module),
      caption: Text("Only when Vortex was opened by hover.", bundle: .module)
    ) {
      SwitchToggle(isOn: $store.settings.closeOnPointerLeave, label: Text("Close when the pointer leaves", bundle: .module))
    }
    if store.settings.closeOnPointerLeave {
      SettingsRow(title: Text("Delay", bundle: .module)) {
        DelaySlider(value: $store.settings.pointerLeaveDelay)
      }
    }

    SettingsRow(
      title: Text("Menu bar icon", bundle: .module),
      caption: store.hasNotchedScreen ? nil : Text("Always shown on displays without a notch.", bundle: .module)
    ) {
      SwitchToggle(
        isOn: Binding(
          get: { store.isMenuBarIconVisible },
          set: { store.send(.binding(.set(\.settings.showMenuBarIcon, $0))) }
        ),
        label: Text("Menu bar icon", bundle: .module)
      )
      .disabled(!store.hasNotchedScreen)
    }
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
      Text("Features you turn off disappear from the sidebar. Drag to reorder.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.vertical, 10)

      List {
        ForEach(store.orderedFeatures) { feature in
          HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
              .foregroundStyle(VortexColor.tertiaryText)
            Image(systemName: feature.symbol)
              .frame(width: 20)
            Text(feature.title)
            Spacer()
            SwitchToggle(
              isOn: Binding(
                get: { !store.settings.disabledFeatures.contains(feature.id) },
                set: { store.send(.featureEnabledChanged(feature.id, isEnabled: $0)) }
              ),
              label: Text(feature.title)
            )
          }
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }
        .onMove { source, destination in
          store.send(.featuresMoved(fromOffsets: source, toOffset: destination))
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .scrollDisabled(true)
      .frame(height: CGFloat(store.features.count) * VortexMetrics.hitTarget + 8)

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

/// A setting: title and optional caption on the left, the control on the right, a hairline below.
private struct SettingsRow<Control: View>: View {
  let title: Text
  var caption: Text?
  @ViewBuilder let control: Control

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          title
          if let caption {
            caption
              .font(.system(size: 11.5))
              .foregroundStyle(VortexColor.tertiaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 12)
        control
      }
      .frame(minHeight: 48)
      Hairline()
    }
  }
}

private struct SwitchToggle: View {
  @Binding var isOn: Bool
  let label: Text

  var body: some View {
    Toggle(isOn: $isOn) { label }
      .toggleStyle(.vortex)
      .labelsHidden()
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
