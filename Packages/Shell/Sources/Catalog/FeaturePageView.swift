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
      Button {
        store.send(.tabSelected(.catalog))
      } label: {
        HStack(spacing: 2) {
          Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
          Text("Features", bundle: .module)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(VortexColor.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(height: VortexMetrics.headerHeight)
      .padding(.leading, 4)

      HStack(alignment: .top, spacing: 28) {
        FeaturePreviewView(feature: feature)
          .frame(width: 400, height: 250)
        ScrollView {
          details(state)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
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

      needs(isAdded: state.isAdded)

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

      if case let .removed(bytes) = state {
        Button {
          store.send(.eraseTapped(feature.id))
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "trash")
            Text("Erase Data…", bundle: .module)
            // Rows in the database have no size of their own to show.
            if let bytes, bytes > 0 {
              Text(bytes.formatted(.byteCount(style: .file))).foregroundStyle(VortexColor.tertiaryText)
            }
          }
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.secondaryText)
          .padding(.horizontal, 8)
          .frame(height: 28)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -8)
      }
    }
  }

  /// The permissions the feature needs, each with its reason; once added, one that is off can be turned on here.
  @ViewBuilder
  private func needs(isAdded: Bool) -> some View {
    if !feature.permissionNeeds.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Needs", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
        ForEach(feature.permissionNeeds, id: \.permission) { need in
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text(need.permission.title).font(.system(size: 12.5))
              Text(need.reason)
                .font(.system(size: 11.5))
                .foregroundStyle(VortexColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isAdded, PermissionMark(store.permissionStatuses[need.permission]) == .warning {
              Button {
                store.send(.permissionPageRequested(need.permission))
              } label: {
                Text("Turn on", bundle: .module)
              }
              .buttonStyle(.quietCapsule)
              .fixedSize()
            }
          }
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
        primary(Text("Open", bundle: .module)) { store.send(.openFeatureTapped(feature.id)) }
        switch store.state.homeOnPage(feature.id) {
        case .canAdd:
          // A feature added later doesn't go on Home by itself.
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
        Button {
          store.send(.tabSelected(.settings))
          store.send(.binding(.set(\.settingsSection, .features)))
        } label: {
          Text("Settings", bundle: .module)
        }
        .buttonStyle(QuietCapsuleButtonStyle(height: 36, fontSize: 13))
        remove
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

extension ShellFeature.FeaturePageState {
  fileprivate var isAdded: Bool {
    switch self {
    case .added, .stopped, .waitingInSafeMode: true
    case .available, .removed, .paused: false
    }
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
