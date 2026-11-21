#if DEBUG
  import ComposableArchitecture
  import CoreGraphics
  import VortexCore
  import VortexPlatform

  extension HomeModule {
    private static var isRegistered = false

    /// QA mode's `home` command, while the open window shows Home. Each sends what the editor's control sends:
    /// - `edit`, `done`, `cancel`: the pencil, Done and Cancel;
    /// - `feature id=<feature>`, `back`: a feature's row in the panel, and back to the list;
    /// - `search [text=<query>]`: what the panel's search field holds, typed in, or emptied without `text=`;
    /// - `hover [id=<widget>]`: the pointer over a widget in the panel, or off it;
    /// - `resize id=<widget> size=small|medium|wide|large|full`: a size in the widget's switcher;
    /// - `add id=<widget> [size=]`: Add, after choosing the size;
    /// - `remove id=<widget>`: its "−";
    /// - `move id=<widget> column=<0-3> row=<0-1>`: a drag that lands its top left corner on that cell;
    /// - `button x=<points> y=<points>`: a drag that drops the utilities button with its center there, from the top
    ///   left of Home's column as a snapshot shows it; `button slot`, one that drops it on its slot.
    /// The state section `home` tells the layout, the editor's draft, what shows, the editor and the copy (`QAState`).
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.registerState(section: "home") { QAState(store.state) }
      QA.register(command: "home") { arguments in
        guard QA.isShowing(.tab(id)) else { throw QAError("Home's commands work while the open window shows Home") }
        for action in try qaActions(arguments, notch: store.state.notch) {
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
      /// The utilities button's place in home.json: [x, y] of its center, from the middle of Home's column and from its
      /// top; nil in its slot.
      var button: CGPoint?
      /// The editor's draft, which only Done keeps in home.json; nil outside the editor.
      var draft: Layout?
      /// Where the button's center shows now, at the draft's place in the editor: [x, y] from the top left of Home's
      /// column.
      var buttonShows: CGPoint
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
      /// The features whose request found no room, as their pages say.
      var noRoomOnHome: [String]

      /// A layout as plain words: its notch row, its places in their order, and the utilities button's place.
      struct Layout: Encodable, Equatable {
        var notchRow: String?
        var placed: [String]
        var button: CGPoint?
      }

      init(_ state: HomeFeature.State) {
        func words(_ placement: Placement) -> String {
          "\(placement.widget) \(placement.size.rawValue) (\(placement.column),\(placement.row))"
            + (placement.isAway ? " away" : "")
        }
        notchRow = state.saved?.notchRow
        placed = (state.saved?.placed ?? []).map(words)
        button = state.saved?.button
        draft = state.isEditing
          ? Layout(
            notchRow: state.draft?.notchRow, placed: (state.draft?.placed ?? []).map(words), button: state.draft?.button
          )
          : nil
        buttonShows = HomeLayout.buttonCenter(state.layout?.button, notch: state.notch)
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
        noRoomOnHome = state.noRoomOnHome.sorted()
      }
    }

    /// What the command sends; `notch` is where the notch cuts into Home's column, for the button's slot.
    static func qaActions(_ arguments: [String: String], notch: CGRect? = nil) throws -> [HomeFeature.Action] {
      let verbs = [
        "edit", "done", "cancel", "feature", "back", "search", "hover", "resize", "add", "remove", "move", "button",
      ]
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
      case "search":
        return [.searchChanged(arguments["text"] ?? "")]
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
      case "button":
        if arguments["slot"] == "" { return [.buttonDropped(HomeLayout.buttonSlot(notch: notch))] }
        guard let x = Double(arguments["x"] ?? ""), let y = Double(arguments["y"] ?? "") else {
          throw QAError("button takes x=<points> y=<points>, or slot")
        }
        return [.buttonDropped(CGPoint(x: x, y: y))]
      default:
        guard let column = Int(arguments["column"] ?? ""), let row = Int(arguments["row"] ?? "") else {
          throw QAError("move takes column=<0-3> row=<0-1>")
        }
        return [.dropped(try widget(), column: column, row: row)]
      }
    }
  }
#endif
