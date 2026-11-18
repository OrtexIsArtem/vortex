#if DEBUG
  import ComposableArchitecture
  import VortexCore
  import VortexPlatform

  extension HomeModule {
    private static var isRegistered = false

    /// QA mode's `home` command, while the open window shows Home. Each sends what the editor's control sends:
    /// - `edit`, `done`, `cancel`: the pencil, Done and Cancel;
    /// - `feature id=<feature>`, `back`: a feature's row in the panel, and back to the list;
    /// - `hover [id=<widget>]`: the pointer over a widget in the panel, or off it;
    /// - `resize id=<widget> size=small|medium|wide|large|full`: a size in the widget's switcher;
    /// - `add id=<widget> [size=]`: Add, after choosing the size;
    /// - `remove id=<widget>`: its "−";
    /// - `move id=<widget> column=<0-3> row=<0-1>`: a drag that lands its top left corner on that cell.
    /// The state section `home` tells the layout, the editor's draft, what shows, the editor and the copy (`QAState`).
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.registerState(section: "home") { QAState(store.state) }
      QA.register(command: "home") { arguments in
        guard QA.isShowing(.tab(id)) else { throw QAError("Home's commands work while the open window shows Home") }
        for action in try qaActions(arguments) {
          store.send(action)
        }
      }
    }

    /// Home in the state dump, as plain words: a place is "<widget> <size> (<column>,<row>)", with "away" while its
    /// feature doesn't run.
    struct QAState: Encodable, Equatable {
      var notchRow: String?
      /// Every place in home.json, in its order.
      var placed: [String]
      /// The editor's draft, which only Done keeps in home.json; nil outside the editor.
      var draft: Layout?
      /// The widgets on the grid now: the draft's in the editor.
      var visible: [String]
      /// The running features' widgets, as the shell told them.
      var widgets: [String]
      var isEditing: Bool
      /// "features", or "feature:<id>" for one feature's widgets.
      var panel: String
      var search: String
      /// The copy of the widget under the pointer in the panel: "<widget> <size> (<column>,<row>)", "notchRow <widget>"
      /// or "noRoom <widget>".
      var preview: String?
      var chosenSizes: [String: String]
      var addRequests: [String]
      var featuresOnHome: [String]

      /// A layout as plain words: its notch row, and its places in their order.
      struct Layout: Encodable, Equatable {
        var notchRow: String?
        var placed: [String]
      }

      init(_ state: HomeFeature.State) {
        func words(_ placement: Placement) -> String {
          "\(placement.widget) \(placement.size.rawValue) (\(placement.column),\(placement.row))"
            + (placement.isAway ? " away" : "")
        }
        notchRow = state.saved?.notchRow
        placed = (state.saved?.placed ?? []).map(words)
        draft = state.isEditing
          ? Layout(notchRow: state.draft?.notchRow, placed: (state.draft?.placed ?? []).map(words))
          : nil
        visible = state.visible.map(\.widget)
        widgets = state.widgets.map(\.id)
        isEditing = state.isEditing
        panel = switch state.panel {
        case .features: "features"
        case let .feature(id): "feature:\(id)"
        }
        search = state.search
        preview = state.preview.map { preview in
          switch preview {
          case let .at(placement): words(placement)
          case let .notchRow(id): "notchRow \(id)"
          case let .noRoom(id): "noRoom \(id)"
          }
        }
        chosenSizes = state.chosenSizes.mapValues(\.rawValue)
        addRequests = state.addRequests
        featuresOnHome = state.featuresOnHome.sorted()
      }
    }

    static func qaActions(_ arguments: [String: String]) throws -> [HomeFeature.Action] {
      let verbs = ["edit", "done", "cancel", "feature", "back", "hover", "resize", "add", "remove", "move"]
      let named = verbs.filter { arguments[$0] == "" }
      guard named.count == 1, let verb = named.first else {
        throw QAError("home takes one of \(verbs.joined(separator: ", "))")
      }
      func widget() throws -> String {
        guard let id = arguments["id"], !id.isEmpty else { throw QAError("\(verb) takes id=<widget>") }
        return id
      }
      func size() throws -> HomeWidgetSize? {
        guard let value = arguments["size"] else { return nil }
        guard let size = HomeWidgetSize(rawValue: value) else {
          throw QAError("size= takes \(HomeWidgetSize.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return size
      }
      switch verb {
      case "edit":
        return [.editTapped]
      case "done":
        return [.doneTapped]
      case "cancel":
        return [.cancelTapped]
      case "feature":
        guard let feature = arguments["id"], !feature.isEmpty else { throw QAError("feature takes id=<feature>") }
        return [.featureTapped(FeatureID(feature))]
      case "back":
        return [.backTapped]
      case "hover":
        return [.hovered(arguments["id"].flatMap { $0.isEmpty ? nil : $0 })]
      case "resize":
        guard let size = try size() else { throw QAError("resize takes size=") }
        return [.sizeTapped(try widget(), size)]
      case "add":
        let id = try widget()
        return (try size().map { [.sizeTapped(id, $0)] } ?? []) + [.addTapped(id)]
      case "remove":
        return [.removeTapped(try widget())]
      default:
        guard let column = Int(arguments["column"] ?? ""), let row = Int(arguments["row"] ?? "") else {
          throw QAError("move takes column=<0-3> row=<0-1>")
        }
        return [.dropped(try widget(), column: column, row: row)]
      }
    }
  }
#endif
