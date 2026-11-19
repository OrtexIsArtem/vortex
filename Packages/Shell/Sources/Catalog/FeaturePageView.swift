import AVFoundation
import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// A feature's page in the catalog: its preview, what it does and needs, what it keeps and who made it, and what the
/// user can do with it now. A feature whose own setup isn't done shows the setup right here.
struct FeaturePageView: View {
  let store: StoreOf<ShellFeature>
  let feature: FeatureDescriptor

  var body: some View {
    let state = store.state.pageState(feature.id) ?? .available
    VStack(alignment: .leading, spacing: 0) {
      BackButton(title: Text("Features", bundle: .module)) { store.send(.tabSelected(.catalog)) }

      HStack(alignment: .top, spacing: 28) {
        FeaturePreviewView(feature: feature)
          .frame(width: 400, height: 250)
        ScrollViewReader { proxy in
          ScrollView {
            details(state)
              .padding(.bottom, 18)
              // Erase Data's fill reaches past the text's left edge, and a scroll view clips what lies outside: the
              // details get that room here and the scroll view takes it back below, so nothing moves.
              .padding(.leading, EraseDataButton.inset)
          }
          .scrollBounceBehavior(.basedOnSize)
          .padding(.leading, -EraseDataButton.inset)
          // Where the buttons take two rows, as in Ukrainian, "No room on Home" lands at the bottom edge: it scrolls
          // into view as it comes.
          .onChange(of: store.state.homeOnPage(feature.id) == .noRoom) { _, isNoRoom in
            guard isNoRoom else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(NoRoomOnHome.id, anchor: .bottom) }
          }
        }
      }
      .padding(.leading, 10)
      .padding(.trailing, 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: feature.id) { store.send(.featurePageShown(feature.id)) }
  }

  private func details(_ state: ShellFeature.FeaturePageState) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: feature.symbol)
          .font(.system(size: 18))
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VortexColor.raised))
        VStack(alignment: .leading, spacing: 4) {
          Text(feature.title).font(.system(size: 13, weight: .semibold))
          if feature.isBeta {
            Text("Beta", bundle: .module)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(VortexColor.tertiaryText)
          }
        }
      }

      Text(feature.details)
        .font(.system(size: 12.5))
        .foregroundStyle(VortexColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

      if let notice = notice(state) {
        VStack(alignment: .leading, spacing: 3) {
          notice.title.font(.system(size: 12.5, weight: .semibold))
          notice.text
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VortexColor.raised))
      }

      if case .added(needsSetup: true) = state, let step = FeatureViews.shared.onboardingStep(feature.id) {
        step.view
      }

      needs

      VStack(alignment: .leading, spacing: 6) {
        if let keeps = feature.keeps {
          Label { Text(keeps) } icon: { Image(systemName: "internaldrive") }
        }
        if !feature.author.isEmpty {
          Label { Text("By \(feature.author)", bundle: .module) } icon: { Image(systemName: "person") }
        }
      }
      .font(.system(size: 12))
      .foregroundStyle(VortexColor.tertiaryText)

      buttons(state)
        .padding(.top, 2)

      if store.state.homeOnPage(feature.id) == .noRoom {
        NoRoomOnHome()
          .id(NoRoomOnHome.id)
      }

      if case let .removed(bytes) = state {
        EraseDataButton(bytes: bytes) { store.send(.eraseTapped(feature.id)) }
          // The bin lines up with the text above it; the fill under the pointer reaches past it.
          .padding(.leading, -EraseDataButton.inset)
      }
    }
  }

  /// The permissions the feature needs, each with its reason; once added, one that isn't working yet shows as on the
  /// feature's settings page (`PermissionRows`): off, with the yellow mark and "Turn on"; granted for the next launch,
  /// with "Works after restart" and "Restart Vortex".
  @ViewBuilder
  private var needs: some View {
    if !feature.permissionNeeds.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Needs", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
        ForEach(feature.permissionNeeds, id: \.permission) { need in
          let mark = store.state.permissionMark(need.permission, onPageOf: feature.id)
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              need.title(mark).font(.system(size: 12.5))
              need.caption(mark)
                .font(.system(size: 11.5))
                .foregroundStyle(VortexColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let mark {
              PermissionButton(need.permission, mark: mark) { permission in
                store.send(.permissionPageRequested(permission))
              } restart: {
                store.send(.restartButtonTapped)
              }
              .fixedSize()
            }
          }
          .permissionHelp(need, mark)
        }
      }
    }
  }

  @ViewBuilder
  private func buttons(_ state: ShellFeature.FeaturePageState) -> some View {
    HStack(spacing: 8) {
      switch state {
      case .available, .removed:
        primary(Text("Add", bundle: .module)) { store.send(.featureAdded(feature.id)) }
      case .added:
        // One row where the buttons fit; where they don't (Ukrainian), Home's on a row of its own.
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            primary(Text("Open", bundle: .module)) { store.send(.openFeatureTapped(feature.id)) }
            home
            settings
            remove
          }
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              primary(Text("Open", bundle: .module)) { store.send(.openFeatureTapped(feature.id)) }
              settings
              remove
            }
            home
          }
        }
      case .paused:
        Text("Temporarily Unavailable", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(VortexColor.tertiaryText)
          .padding(.horizontal, 18)
          .frame(height: 36)
          .background(Capsule().fill(VortexColor.raised))
      case .stopped:
        primary(Text("Try Again", bundle: .module)) { store.send(.tryAgainTapped(feature.id)) }
        remove
      case .waitingInSafeMode:
        primary(Text("Start", bundle: .module)) { store.send(.startFeatureTapped(feature.id)) }
      }
    }
  }

  /// "Add to Home" while none of the feature's widgets is on Home, "On Home" once one is; nothing without widgets.
  @ViewBuilder
  private var home: some View {
    switch store.state.homeOnPage(feature.id) {
    case .canAdd, .noRoom:
      // A feature added later doesn't go on Home by itself. Without room the button stays, to try again.
      Button {
        store.send(.addToHomeTapped(feature.id))
      } label: {
        Text("Add to Home", bundle: .module)
      }
      .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
    case .onHome:
      Label {
        Text("On Home", bundle: .module)
      } icon: {
        Image(systemName: "checkmark")
      }
      .font(.system(size: 13))
      .foregroundStyle(VortexColor.secondaryText)
      .padding(.horizontal, 12)
      .frame(height: 36)
    case nil:
      EmptyView()
    }
  }

  /// The feature's own page in Settings › Features; hidden while it has none, as before the feature runs.
  @ViewBuilder
  private var settings: some View {
    if store.state.hasSettingsPage(feature.id) {
      Button {
        store.send(.featureSettingsTapped(feature.id))
      } label: {
        Text("Settings", bundle: .module)
      }
      .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
    }
  }

  private func primary(_ title: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) { title }
      .buttonStyle(PrimaryCapsuleButtonStyle(height: 36, fontSize: 13))
  }

  private var remove: some View {
    Button {
      store.send(.featureRemoved(feature.id))
    } label: {
      Text("Remove", bundle: .module)
        .font(.system(size: 13))
        .foregroundStyle(VortexColor.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func notice(_ state: ShellFeature.FeaturePageState) -> (title: Text, text: Text)? {
    switch state {
    case let .paused(reason):
      (Text("Paused by the maintainer", bundle: .module), Text(reason))
    case .stopped:
      (
        Text("Stopped after a crash", bundle: .module),
        Text("Vortex quit while it was starting this feature, so it stays off until you try again.", bundle: .module)
      )
    case .waitingInSafeMode:
      (
        Text("Not started in safe mode", bundle: .module),
        Text("Vortex quit right after it started, so features wait until you start them.", bundle: .module)
      )
    case .available, .removed:
      // Files given to Vortex wait for the feature that takes them.
      feature.acceptsFileDrops && !store.pendingFiles.isEmpty
        ? (Text("Files are waiting", bundle: .module), Text("Add \(Text(feature.title)) to keep files", bundle: .module))
        : nil
    case .added:
      nil
    }
  }
}

/// Under the buttons once "Add to Home" found no room: why nothing happened, and what to do about it in Home's editor.
private struct NoRoomOnHome: View {
  /// Where the page scrolls to as the line comes.
  static let id = "noRoomOnHome"

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("No room on Home", bundle: .module)
        .font(.system(size: 12.5))
      Text("Remove a widget or choose a smaller size in Home's editor.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Erase Data under a removed feature's buttons: the bin, its words and the size of what the feature keeps. Under the
/// pointer it lights up as the app's other quiet controls do, its words brightened on a rounded fill, and pressed it
/// dims; the pointer stays the arrow, as on every button in the app.
private struct EraseDataButton: View {
  /// How far the fill reaches past the label on each side.
  static let inset: CGFloat = 8
  /// What the feature keeps on disk, if known.
  let bytes: Int64?
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "trash")
        Text("Erase Data…", bundle: .module)
        // Rows in the database have no size of their own to show.
        if let bytes, bytes > 0 {
          Text(bytes.formatted(.byteCount(style: .file)))
            .foregroundStyle(isHovered ? VortexColor.secondaryText : VortexColor.tertiaryText)
        }
      }
      .font(.system(size: 12))
      .foregroundStyle(isHovered ? VortexColor.primaryText : VortexColor.secondaryText)
      .padding(.horizontal, Self.inset)
      .frame(height: 28)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isHovered ? VortexColor.raised : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(DimmedWhilePressed())
    .onHover { isHovered = $0 }
  }
}

/// A button drawn by its label alone that dims while pressed, as the capsule buttons do.
private struct DimmedWhilePressed: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// The feature's looping preview, without sound, paused while the window is closed; its still with Reduce Motion, and
/// its symbol when it has neither.
private struct FeaturePreviewView: View {
  let feature: FeatureDescriptor
  @Environment(\.isWindowOpen) private var isWindowOpen
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VortexColor.card)
      if let video = feature.preview?.video, !reduceMotion {
        LoopingVideo(url: video, isPlaying: isWindowOpen)
      } else if let still = feature.preview?.still, let image = NSImage(contentsOf: still) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: feature.symbol)
          .font(.system(size: 44))
          .foregroundStyle(VortexColor.tertiaryText)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// A muted video that loops, playing only while `isPlaying`.
private struct LoopingVideo: NSViewRepresentable {
  let url: URL
  let isPlaying: Bool

  func makeNSView(context: Context) -> PlayerView {
    PlayerView(url: url)
  }

  func updateNSView(_ view: PlayerView, context: Context) {
    if isPlaying { view.player.play() } else { view.player.pause() }
  }

  final class PlayerView: NSView {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
      super.init(frame: .zero)
      player.isMuted = true
      looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
      let layer = AVPlayerLayer(player: player)
      layer.videoGravity = .resizeAspectFill
      self.layer = layer
      wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  }
}
