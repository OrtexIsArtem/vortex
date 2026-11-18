#if DEBUG
  import ComposableArchitecture
  import VortexCore
  import VortexPlatform

  extension HomeModule {
    private static var isRegistered = false

    /// QA mode's `home` command, while the open window shows Home. Each sends what the editor's control sends:
    /// - `edit`, `done`: the pencil and Done;
    /// - `feature id=<feature>`, `back`: a feature's row in the panel, and back to the list;
    /// - `hover [id=<widget>]`: the pointer over a widget in the panel, or off it;
    /// - `resize id=<widget> size=small|medium|wide|large|full`: a size in the widget's switcher;
    /// - `add id=<widget> [size=]`: Add, after choosing the size;
    /// - `remove id=<widget>`: its "−";
    /// - `move id=<widget> column=<0-3> row=<0-1>`: a drag that lands its top left corner on that cell.
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.register(command: "home") { arguments in
        guard QA.isShowing(.tab(id)) else { throw QAError("Home's commands work while the open window shows Home") }
        for action in try qaActions(arguments) {
          store.send(action)
        }
      }
    }

    static func qaActions(_ arguments: [String: String]) throws -> [HomeFeature.Action] {
      let verbs = ["edit", "done", "feature", "back", "hover", "resize", "add", "remove", "move"]
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
