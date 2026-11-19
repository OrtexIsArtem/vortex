#if DEBUG
  import ComposableArchitecture
  import Foundation
  import VortexCore
  import VortexPlatform

  extension ShelfModule {
    private static var isRegistered = false

    /// QA mode's `shelf` command, while the shelf's files show in the open window, in its tab or on Home's Shelf widget:
    /// - `rest n=<place>`: the pointer resting on the file at that place, 1-based in the shelf's order, which both show,
    ///   for `ShelfFeature.hoverDwell`, as a user who has seen it: its dot goes, and with the last dot the notch's tray.
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.register(command: "shelf") { arguments in
        guard ShelfOnScreen.isShowing else {
          throw QAError("the shelf's files show in its tab or on Home's Shelf widget, in the open window")
        }
        store.send(try qaAction(arguments, items: Array(store.items)))
      }
    }

    /// What `shelf` sends for its arguments, given the files in the shelf's order.
    static func qaAction(_ arguments: [String: String], items: [ShelfItem]) throws -> ShelfFeature.Action {
      guard arguments["rest"] == "", arguments.keys.allSatisfy({ ["rest", "n"].contains($0) }) else {
        throw QAError("shelf takes rest n=<1-based place among the shelf's files>")
      }
      guard let place = Int(arguments["n"] ?? ""), items.indices.contains(place - 1) else {
        throw QAError("rest takes n=<1…\(items.count)>, a place among the shelf's files")
      }
      return .itemHoverRested(items[place - 1].id)
    }
  }

  /// The shelf's views in the open window now, its tab or Home's widget, as `ShelfVisibilityTracking` reports them: QA's
  /// `shelf` command acts only on files a user could point at.
  @MainActor
  enum ShelfOnScreen {
    static var views: Set<UUID> = []
    static var isShowing: Bool { !views.isEmpty }
  }
#endif
