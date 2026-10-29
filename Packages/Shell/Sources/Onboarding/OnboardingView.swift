import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The onboarding window's content: a page of the onboarding, or a single permission's page (S12–S19, S24).
struct OnboardingView: View {
  let store: StoreOf<OnboardingFeature>
  /// The features' own steps, made once at launch (S17).
  let steps: [FeatureID: OnboardingStep]

  var body: some View {
    Group {
      switch store.presentation {
      case .hidden:
        // Nothing stays mounted while hidden, so the illustration's loop stops (S35: no CPU once settled).
        Color.clear
      case .flow:
        page(store.page)
      case let .single(single):
        SinglePermissionPage(store: store, single: single)
      }
    }
    .frame(width: OnboardingWindowController.windowSize.width, height: OnboardingWindowController.windowSize.height)
    .background(VortexColor.windowBackground)
  }

  @ViewBuilder
  private func page(_ page: OnboardingPage) -> some View {
    switch page {
    case .welcome:
      WelcomePage(store: store)
    case .basics:
      PageScaffold(store: store, title: Text("Basics", bundle: .module)) {
        BasicsContent(store: store)
      }
    case let .permission(permission):
      PageScaffold(store: store, title: Text(permission.title)) {
        HardPermissionContent(store: store, permission: permission, isSingle: false)
      }
    case let .step(feature):
      if let step = steps[feature] {
        PageScaffold(store: store, title: Text(step.title)) {
          step.view
        }
      } else {
        PageScaffold(store: store, title: Text(verbatim: "")) { EmptyView() }
      }
    case .done:
      DonePage(store: store)
    }
  }
}

// MARK: - Scaffold

/// A page with permissions or a feature's step: title on top, content, then Skip and Next at the bottom right.
struct PageScaffold<Content: View>: View {
  let store: StoreOf<OnboardingFeature>
  let title: Text
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      title
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(VortexColor.primaryText)
        .padding(.top, 52)
      content
        .padding(.top, 20)
      Spacer(minLength: 0)
      Hairline()
      footer
        .frame(height: 72)
    }
    .padding(.horizontal, 40)
  }

  private var footer: some View {
    let buttons = store.buttons
    return HStack(spacing: 10) {
      if store.showsRestartNow {
        Button {
          store.send(.restartTapped)
        } label: {
          Text("Restart now", bundle: .module)
        }
        .buttonStyle(QuietLinkStyle())
      }
      Spacer()
      if buttons.skipVisible {
        Button {
          store.send(.skipTapped)
        } label: {
          Text("Skip", bundle: .module)
        }
        .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
      }
      if buttons.nextVisible {
        Button {
          store.send(.nextTapped)
        } label: {
          Text("Next", bundle: .module)
        }
        .buttonStyle(PrimaryCapsuleButtonStyle(height: 36, fontSize: 13))
        .disabled(!buttons.nextEnabled)
        .opacity(buttons.nextEnabled ? 1 : 0.35)
        .keyboardShortcut(.defaultAction)
      }
    }
  }
}

/// A quiet text link: "Restart now", "Restart to check" (S20, S68).
struct QuietLinkStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12.5, weight: .medium))
      .foregroundStyle(VortexColor.secondaryText)
      .underline(configuration.isPressed)
      .frame(minHeight: VortexMetrics.hitTarget)
      .contentShape(Rectangle())
  }
}

// MARK: - Rows

/// The checkbox that shows macOS's real status (S2): empty before the first read (S72), off, on, or on with ↻.
struct PermissionCheckbox: View {
  let state: PermissionRowState
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(isOn ? VortexColor.primaryText : Color.clear)
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(isOn ? Color.clear : VortexColor.dropOutline, lineWidth: 1.5)
        if isOn {
          Image(systemName: state == .afterRestart ? "arrow.clockwise" : "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(VortexColor.windowBackground)
        }
      }
      .frame(width: 22, height: 22)
      .frame(width: VortexMetrics.hitTarget, height: VortexMetrics.hitTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(state == .unknown ? 0 : 1)
    .disabled(state == .unknown)
    .help(isOn ? String(localized: "Turn it off in System Settings.", bundle: .module) : "")
    .accessibilityValue(isOn ? Text("On", bundle: .module) : Text("Off", bundle: .module))
  }

  private var isOn: Bool { state == .on || state == .afterRestart }
}

/// "Required" next to a permission that can't be skipped (S19).
struct RequiredTag: View {
  var body: some View {
    Text("Required", bundle: .module)
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(VortexColor.secondaryText)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .overlay(Capsule().strokeBorder(VortexColor.dropOutline, lineWidth: 1))
  }
}

/// A permission's row: its title, the reasons of every feature that needs it (S62), and the live checkbox.
struct PermissionRowView: View {
  let store: StoreOf<OnboardingFeature>
  let permission: Permission
  let title: Text
  /// A hard page shows the reasons above its illustration already.
  var showsReasons = true

  var body: some View {
    let state = store.state.rowState(permission)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 8) {
            title
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(VortexColor.primaryText)
            if store.state.isRequiredMissing(permission) { RequiredTag() }
          }
          if showsReasons {
            Text(reasons)
              .font(.system(size: 12))
              .foregroundStyle(VortexColor.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          if state == .afterRestart {
            Group {
              if store.progress.pendingChecks.contains(permission) {
                Text("Checked after restart", bundle: .module)
              } else {
                Text("Works after restart", bundle: .module)
              }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(VortexColor.tertiaryText)
          }
        }
        Spacer(minLength: 12)
        PermissionCheckbox(state: state) { store.send(.turnOnTapped(permission)) }
      }
      .padding(.vertical, 10)
      Hairline()
    }
  }

  private var reasons: String {
    (store.catalog.entry(for: permission)?.reasons ?? []).map { String(localized: $0) }.joined(separator: " ")
  }
}

// MARK: - Basics

struct BasicsContent: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Hairline()
      if store.state.rows(on: .basics).contains(.notifications) {
        PermissionRowView(store: store, permission: .notifications, title: Text(Permission.notifications.title))
        if store.isNotificationHintVisible {
          Text("Click Allow in the notification at the top right, or in Notification Center.", bundle: .module)
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.secondaryText)
            .padding(.top, 8)
        }
        RecheckHint(store: store, permission: .notifications)
      }
      loginRow
    }
  }

  private var loginRow: some View {
    let showsChoice = store.appliesLoginItem && !store.progress.loginItemApplied
    let isOn = showsChoice ? store.openAtLoginChoice : store.loginItem == .enabled
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Open at login", bundle: .module)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(VortexColor.primaryText)
          if !showsChoice, store.loginItem == .requiresApproval {
            Text("Allow Vortex in System Settings › General › Login Items.", bundle: .module)
              .font(.system(size: 12))
              .foregroundStyle(VortexColor.secondaryText)
          }
        }
        Spacer(minLength: 12)
        if !showsChoice, store.loginItem == .requiresApproval {
          Button {
            store.send(.openLoginItemsTapped)
          } label: {
            Text("Open Login Items", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
        Toggle(isOn: Binding(get: { isOn }, set: { store.send(.loginItemToggled($0)) })) {
          Text("Open at login", bundle: .module)
        }
        .toggleStyle(.vortex)
        .labelsHidden()
      }
      .frame(minHeight: VortexMetrics.hitTarget)
      .padding(.vertical, 10)
      Hairline()
    }
  }
}

// MARK: - Hard permission

/// A page for a permission that needs System Settings (S14, S16, S59): reasons, the illustration and "Turn on".
struct HardPermissionContent: View {
  let store: StoreOf<OnboardingFeature>
  let permission: Permission
  let isSingle: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isSingle || permission == .notifications {
        EmptyView()
      }
      Text(reasons)
        .font(.system(size: 13))
        .foregroundStyle(VortexColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      SettingsIllustration(permission: permission)
        .frame(height: 210)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
      Hairline()
      PermissionRowView(store: store, permission: permission, title: Text("Turn on", bundle: .module), showsReasons: false)
      if permission == .notifications, store.isNotificationHintVisible {
        Text("Click Allow in the notification at the top right, or in Notification Center.", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.secondaryText)
          .padding(.top, 8)
      }
      RecheckHint(store: store, permission: permission)
      notes
        .padding(.top, 10)
    }
  }

  private var reasons: String {
    (store.catalog.entry(for: permission)?.reasons ?? []).map { String(localized: $0) }.joined(separator: " ")
  }

  @ViewBuilder
  private var notes: some View {
    VStack(alignment: .leading, spacing: 4) {
      if permission.needsRelaunch {
        if isSingle {
          Text("You may need to restart Vortex after this.", bundle: .module)
        } else {
          Text("Vortex may need to restart once for this.", bundle: .module)
        }
      }
      if permission == .screenRecording {
        Text("macOS may ask you to confirm this again from time to time.", bundle: .module)
      }
      if permission == .pasteboard, store.progress.pendingChecks.contains(.pasteboard), isSingle || !store.progress.restarted {
        Button {
          store.send(.restartTapped)
        } label: {
          Text("Restart to check", bundle: .module)
        }
        .buttonStyle(QuietLinkStyle())
      }
    }
    .font(.system(size: 11.5))
    .foregroundStyle(VortexColor.tertiaryText)
  }
}

/// "Already on in System Settings? Turn it off and on again." with the pane button (S55, S59).
struct RecheckHint: View {
  let store: StoreOf<OnboardingFeature>
  let permission: Permission

  var body: some View {
    if store.state.showsRecheckHint(permission) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          if case let .single(single) = store.presentation, single.kind == .lockRefused {
            Text("If the switch is already on, turn it off and on again.", bundle: .module)
          } else {
            Text("Already on in System Settings? Turn it off and on again.", bundle: .module)
          }
          Text("Not in the list? Click + and choose Vortex.", bundle: .module)
        }
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
        Spacer(minLength: 8)
        Button {
          store.send(.openPaneTapped(permission))
        } label: {
          Text("Open System Settings", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }
      .padding(.top, 10)
    }
  }
}

// MARK: - Done

struct DonePage: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("You're all set", bundle: .module)
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(VortexColor.primaryText)
        .padding(.top, 52)
      VStack(spacing: 0) {
        Hairline()
        ForEach(store.state.doneRows, id: \.self) { permission in
          row(permission)
        }
      }
      .padding(.top, 20)
      hint
        .font(.system(size: 13))
        .foregroundStyle(VortexColor.secondaryText)
        .padding(.top, 18)
      Spacer(minLength: 0)
      Hairline()
      HStack {
        Spacer()
        Button {
          store.send(.finishTapped)
        } label: {
          if store.state.finishRestarts {
            Text("Restart and start", bundle: .module)
          } else {
            Text("Start using Vortex", bundle: .module)
          }
        }
        .buttonStyle(PrimaryCapsuleButtonStyle(height: 36, fontSize: 13))
        .disabled(!store.state.finishEnabled)
        .opacity(store.state.finishEnabled ? 1 : 0.35)
        .keyboardShortcut(.defaultAction)
      }
      .frame(height: 72)
    }
    .padding(.horizontal, 40)
  }

  @ViewBuilder
  private func row(_ permission: Permission) -> some View {
    let state = store.state.rowState(permission)
    let content = HStack(spacing: 12) {
      Text(permission.title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(VortexColor.primaryText)
      if store.state.isRequiredMissing(permission) { RequiredTag() }
      Spacer()
      switch state {
      case .on:
        Image(systemName: "checkmark").foregroundStyle(VortexColor.primaryText)
      case .afterRestart:
        Image(systemName: "arrow.clockwise").foregroundStyle(VortexColor.primaryText)
          .help(String(localized: "Works after restart", bundle: .module))
      case .off:
        WarningMark(permission)
      case .unknown:
        EmptyView()
      }
    }
    .frame(minHeight: VortexMetrics.hitTarget)
    .contentShape(Rectangle())
    VStack(spacing: 0) {
      if state == .off {
        Button {
          store.send(.doneRowTapped(permission))
        } label: {
          content
        }
        .buttonStyle(.plain)
      } else {
        content
      }
      Hairline()
    }
  }

  /// Built from the settings and screens (S75).
  private var hint: Text {
    let hint = store.doneHint
    switch (hint.hoverNotch, hint.menuBarIcon) {
    case (true, true):
      return Text("Hover over the notch to open Vortex, or click its icon in the menu bar.", bundle: .module)
    case (true, false):
      return Text("Hover over the notch to open Vortex.", bundle: .module)
    case (false, true):
      return Text("Click Vortex's icon in the menu bar to open it.", bundle: .module)
    case (false, false):
      return Text("Open Vortex with its shortcut, set in Settings.", bundle: .module)
    }
  }
}

// MARK: - Single page

/// One permission's page outside the onboarding (S24, S41, S49, S55): Close instead of Skip and Next.
struct SinglePermissionPage: View {
  let store: StoreOf<OnboardingFeature>
  let single: OnboardingFeature.SinglePage

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(single.permission.title)
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(VortexColor.primaryText)
        .padding(.top, 52)
      HardPermissionContent(store: store, permission: single.permission, isSingle: true)
        .padding(.top, 20)
      Spacer(minLength: 0)
      Hairline()
      HStack(spacing: 10) {
        Spacer()
        if waitsForRelaunch {
          Button {
            store.send(.laterTapped)
          } label: {
            Text("Later", bundle: .module)
          }
          .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
          Button {
            store.send(.restartTapped)
          } label: {
            Text("Restart Vortex", bundle: .module)
          }
          .buttonStyle(PrimaryCapsuleButtonStyle(height: 36, fontSize: 13))
          .keyboardShortcut(.defaultAction)
        } else {
          Button {
            store.send(.closeTapped)
          } label: {
            Text("Close", bundle: .module)
          }
          .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
          .keyboardShortcut(.cancelAction)
        }
      }
      .frame(height: 72)
    }
    .padding(.horizontal, 40)
  }

  /// ✓ with "Restart Vortex" and "Later" (S24, S40).
  private var waitsForRelaunch: Bool {
    store.statuses[single.permission] == .grantedAfterRestart
  }
}
