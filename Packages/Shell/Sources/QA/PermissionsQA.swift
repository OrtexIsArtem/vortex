#if DEBUG
  import ComposableArchitecture
  import Foundation
  import VortexCore
  import VortexPlatform

  /// The simulated macOS permissions in a QA run (VortexPlatform's `QAPermissions`): the `perm` command, the required
  /// set of this run, and the `permissions` section of the state with each feature's marks.
  @MainActor
  enum PermissionsQA {
    /// The required set of the run (S30), kept in DataFolder/.qa/required.json so a relaunch keeps it.
    static var requiredFile: URL { DataFolder.url.appending(path: ".qa/required.json") }

    static func install(store: StoreOf<ShellFeature>) {
      if let data = try? Data(contentsOf: requiredFile),
         let required = try? JSONDecoder().decode(Set<Permission>.self, from: data) {
        store.send(.binding(.set(\.requiredPermissions, required)))
      }
      QA.isShowing = { place in
        guard store.isOpen else { return false }
        switch place {
        case let .tab(id): return store.selectedTab == .feature(id)
        case .featureSettings: return store.selectedTab == .settings && store.settingsSection == .features
        }
      }
      QA.registerState(section: "permissions") { State(store: store) }
      QA.register(command: "perm") { arguments in
        try perform(arguments, store: store)
      }
    }

    /// `perm` as `QAPermissions.apply` takes it, plus `required=<p>,<p>|` (empty: none) and `quitReopen`, System
    /// Settings' own «Quit & Reopen»: the run relaunches and then sees what System Settings holds.
    static func perform(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      var required: Set<Permission>?
      if let text = arguments["required"] {
        let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let permissions = names.compactMap(Permission.init(rawValue:))
        guard permissions.count == names.count else {
          throw QAError("required= takes a comma list of \(Permission.allCases.map(\.rawValue).joined(separator: ", ")), or nothing")
        }
        required = Set(permissions)
      }
      try QAPermissions.apply(arguments)
      if let required {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try? encoder.encode(required.sorted { $0.rawValue < $1.rawValue }).write(to: requiredFile, options: .atomic)
        store.send(.binding(.set(\.requiredPermissions, required)))
      }
      if arguments["quitReopen"] != nil {
        QA.relaunch()
      }
    }

    /// Where a permission shows in a feature (S22): the control (Home's keyboard button, Tasks' «+»), the sidebar
    /// dot, and the settings rows.
    struct Marks: Encodable, Equatable {
      /// `warning` or nil: only the controls S22.1 names have one.
      var control: PermissionMark?
      /// The permission the dot names, or nil.
      var sidebar: Permission?
      /// One per permission that isn't working yet: `warning` ("Turn on") or `afterRestart` ("Restart Vortex").
      var settings: [Permission: PermissionMark]
    }

    /// The controls of S22.1, by feature, with the permission each can't work without.
    nonisolated static let controls: [FeatureID: Permission] = ["home": .accessibility, "tasks": .screenRecording]

    nonisolated static func marks(of feature: FeatureDescriptor, _ statuses: [Permission: PermissionStatus]) -> Marks {
      let control = controls[feature.id].flatMap { PermissionMark(statuses[$0]) == .warning ? PermissionMark.warning : nil }
      var settings: [Permission: PermissionMark] = [:]
      for need in feature.permissionNeeds {
        settings[need.permission] = PermissionMark(statuses[need.permission])
      }
      return Marks(control: control, sidebar: feature.permissionNeeds.firstOff(in: statuses), settings: settings)
    }

    struct State: Encodable {
      var required: [Permission]
      var blocked: Bool
      var appBlocked: Bool
      /// What the shell read; empty before the first read.
      var read: [Permission: PermissionStatus]
      var simulation: QAPermissions.Snapshot
      /// Enabled features only, by id.
      var marks: [FeatureID: Marks]

      @MainActor init(store: StoreOf<ShellFeature>) {
        let statuses = store.permissionStatuses
        required = store.requiredPermissions.sorted { $0.rawValue < $1.rawValue }
        blocked = store.isBlocked
        appBlocked = store.appBlocked
        read = statuses
        simulation = QAPermissions.snapshot
        marks = Dictionary(uniqueKeysWithValues: store.sidebarFeatures.map { ($0.id, PermissionsQA.marks(of: $0, statuses)) })
      }
    }
  }
#endif
