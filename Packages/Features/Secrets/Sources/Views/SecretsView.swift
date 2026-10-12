import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The Keys tab: New next to the notch; Claude's requests first, then the keys or the form.
struct SecretsView: View {
  @Bindable var store: StoreOf<SecretsFeature>
  @Environment(\.notchCutout) private var cutout
  @Environment(\.isWindowOpen) private var isWindowOpen

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .frame(height: VortexMetrics.headerHeight)
      if !store.approvals.isEmpty {
        // As tall as the requests, up to the tab less room for the form or the undo toast: more than fit scroll, each
        // command kept to a few lines while another waits too, so every answer stays in reach. The rest gets what is
        // left.
        ScrollView {
          VStack(spacing: 10) {
            ForEach(store.approvals) { approval in
              ApprovalCard(approval: approval, commandHeight: store.approvals.count > 1 ? 64 : 150) {
                store.send(.denyTapped(approval.id))
              } allow: {
                store.send(.approveTapped(approval.id))
              }
              .transition(.move(edge: .top).combined(with: .opacity))
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 10)
        }
        .frame(maxHeight: VortexMetrics.windowSize.height - VortexMetrics.headerHeight - roomBelowRequests)
        .fixedSize(horizontal: false, vertical: true)
      }
      if let draft = store.draft {
        KeyFormView(draft: draft, store: store)
          .transition(.opacity)
      } else {
        KeysList(store: store)
          .transition(.opacity)
      }
      // Under the list rather than over it: laid over a scrolling list, a toast gets no clicks.
      if store.deleted != nil {
        DeletedToast { store.send(.undoTapped, animation: .snappy(duration: 0.22)) }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.22), value: store.approvals.map(\.id))
    .animation(.snappy(duration: 0.22), value: store.deleted)
    // A value shown, here or in the form, stays out of sight once the window closes or another tab shows.
    .onChange(of: isWindowOpen) { _, isOpen in
      if !isOpen { store.send(.windowClosed) }
    }
    .onDisappear { store.send(.windowClosed) }
    .animation(.snappy(duration: 0.2), value: store.draft == nil)
  }

  /// Room the requests leave for the form's Save or the undo toast.
  private var roomBelowRequests: CGFloat {
    (store.draft != nil ? 120 : 0) + (store.deleted != nil ? 58 : 0)
  }

  /// The title left of the notch; New right of it.
  @ViewBuilder
  private var header: some View {
    let title = Text("Keys", bundle: .module)
      .font(.system(size: 13, weight: .semibold))
      .padding(.leading, 10)
    let tools = HStack(spacing: 6) {
      Button {
        store.send(.addTapped, animation: .snappy(duration: 0.2))
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 30, height: 30)
          .background(Circle().fill(VortexColor.raised))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(Text("New key", bundle: .module))
      .accessibilityLabel(Text("New key", bundle: .module))
    }
    if let cutout {
      HStack(spacing: 0) {
        title
          .frame(width: max(cutout.minX - 12, 0), alignment: .leading)
        Color.clear
          .frame(width: cutout.width + 24)
        tools
          .padding(.trailing, 12)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    } else {
      HStack {
        title
        Spacer()
        tools
          .padding(.trailing, 12)
      }
    }
  }
}

/// The keys, with how to connect Claude Code above them until it has connected once.
private struct KeysList: View {
  let store: StoreOf<SecretsFeature>

  var body: some View {
    TimelineView(.everyMinute) { context in
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if !store.settings.hasConnected || store.server.isFailed {
            ConnectCard(store: store)
              .padding(.horizontal, 6)
              .padding(.bottom, 10)
          }
          if store.isLoaded, store.keys.isEmpty {
            EmptyKeys()
          }
          ForEach(store.keys) { key in
            KeyRow(
              key: key,
              revealed: store.revealed?.id == key.id ? store.revealed?.value : nil,
              now: context.date,
              send: { store.send($0) }
            )
          }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 40)
      }
      .scrollIndicators(.never)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension SecretsFeature.ServerStatus {
  var isFailed: Bool {
    if case .failed = self { true } else { false }
  }
}

private struct EmptyKeys: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "key.horizontal")
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(VortexColor.tertiaryText)
      Text("No keys yet", bundle: .module)
        .font(.system(size: 13, weight: .medium))
      Text("Add one with +: Claude uses it by its name and never sees its value.", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 50)
  }
}

/// "Key deleted · Undo" for a few seconds after a key is deleted.
private struct DeletedToast: View {
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Text("Key deleted", bundle: .module)
        .foregroundStyle(VortexColor.secondaryText)
      Button(action: undo) {
        Text("Undo", bundle: .module)
          .fontWeight(.semibold)
      }
      .buttonStyle(.plain)
      .foregroundStyle(VortexColor.primaryText)
    }
    .font(.system(size: 12.5))
    .padding(.horizontal, 16)
    .frame(height: 34)
    .background(Capsule().fill(VortexColor.raised))
    // Only drawn: laid over «Скасувати», an outline takes its clicks.
    .overlay(Capsule().strokeBorder(VortexColor.line).allowsHitTesting(false))
    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
  }
}
