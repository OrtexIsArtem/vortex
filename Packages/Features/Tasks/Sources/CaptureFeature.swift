import ComposableArchitecture
import Foundation
import VortexPlatform

/// What a capture becomes once the user saves it: the frozen screen, the framed part and the fields.
public struct TaskDraft: Equatable, Sendable {
  public var screenshot: Screenshot
  /// The framed part, in points from the screen's top left corner.
  public var frame: CGRect
  public var source: FrontWindow
  public var capturedAt: Date
  public var number: Int
  public var title: String
  public var priority: TaskItem.Priority
  /// Text already recognized in the frame, so it is not read twice.
  public var frameText: String?
}

/// One capture, from the frozen screen to the fields: draw a frame, then name the task, pick its priority and save.
/// Esc cancels at any step; the retake button draws the frame again on the same frozen screen.
@Reducer
public struct CaptureFeature: Sendable {
  /// A smaller frame is taken for a click and ignored.
  static let smallestFrame: CGFloat = 8

  @ObservableState
  public struct State: Equatable {
    let screenshot: Screenshot
    let source: FrontWindow
    let capturedAt: Date
    let number: Int
    /// The frame being drawn, or drawn, in points from the screen's top left corner.
    var frame: CGRect?
    /// The frame is drawn: the part has moved aside and the fields show.
    var isFramed = false
    var title: String
    var priority = TaskItem.Priority.low
    /// The text recognized in the frame; its first line is offered as the title.
    var frameText: String?

    init(screenshot: Screenshot, source: FrontWindow, capturedAt: Date, number: Int) {
      self.screenshot = screenshot
      self.source = source
      self.capturedAt = capturedAt
      self.number = number
      title = TaskItem.defaultTitle(number: number)
    }

    var defaultTitle: String { TaskItem.defaultTitle(number: number) }

    /// The first line of the frame's text, offered as the title.
    var suggestion: String? {
      frameText?
        .split(whereSeparator: \.isNewline)
        .lazy
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .first { $0.count >= 2 }
    }
  }

  public enum Action: Equatable, Sendable {
    case frameChanged(CGRect)
    case frameEnded(CGRect)
    case frameTextRecognized(String)
    case titleChanged(String)
    case suggestionTapped
    case priorityChosen(TaskItem.Priority)
    /// Save, or Return.
    case saveTapped
    /// Cancel, or Esc.
    case cancelTapped
    case retakeTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case save(TaskDraft)
      case cancel
    }
  }

  @Dependency(\.textRecognitionClient) var textRecognition

  private enum CancelID {
    case recognition
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .frameChanged(frame):
        guard !state.isFramed else { return .none }
        state.frame = frame
        return .none

      case let .frameEnded(frame):
        guard !state.isFramed else { return .none }
        let bounds = CGRect(origin: .zero, size: state.screenshot.image.size)
        let frame = frame.standardized.intersection(bounds)
        guard frame.width >= Self.smallestFrame, frame.height >= Self.smallestFrame else {
          state.frame = nil
          return .none
        }
        state.frame = frame
        state.isFramed = true
        guard let part = state.screenshot.image.cropped(to: frame) else { return .none }
        return .run { send in
          // Without text the title just has no suggestion.
          await send(.frameTextRecognized((try? await textRecognition.recognize(part)) ?? ""))
        }
        .cancellable(id: CancelID.recognition, cancelInFlight: true)

      case let .frameTextRecognized(text):
        state.frameText = text
        return .none

      case let .titleChanged(title):
        state.title = title
        return .none

      case .suggestionTapped:
        guard let suggestion = state.suggestion else { return .none }
        state.title = suggestion
        return .none

      case let .priorityChosen(priority):
        state.priority = priority
        return .none

      case .saveTapped:
        guard state.isFramed, let frame = state.frame else { return .none }
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return .send(.delegate(.save(TaskDraft(
          screenshot: state.screenshot,
          frame: frame,
          source: state.source,
          capturedAt: state.capturedAt,
          number: state.number,
          title: title.isEmpty ? state.defaultTitle : title,
          priority: state.priority,
          frameText: state.frameText
        ))))

      case .cancelTapped:
        return .merge(.cancel(id: CancelID.recognition), .send(.delegate(.cancel)))

      case .retakeTapped:
        state.frame = nil
        state.isFramed = false
        state.frameText = nil
        return .cancel(id: CancelID.recognition)

      case .delegate:
        return .none
      }
    }
  }
}
