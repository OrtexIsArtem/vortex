import ComposableArchitecture
import SwiftUI
import VortexCore

/// A new key: the value (what it is shows as it is pasted), the name Claude writes, a note and how long it lives.
struct KeyFormView: View {
  let draft: KeyDraft
  let store: StoreOf<SecretsFeature>
  @FocusState private var focus: Field?
  /// The value in plain text, to check what was pasted.
  @State private var showsValue = false

  private enum Field {
    case value
    case name
    case note
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("New key", bundle: .module)
        .font(.system(size: 17, weight: .semibold))
        .padding(.bottom, 14)

      row(Text("Value", bundle: .module)) {
        HStack(spacing: 6) {
          Group {
            if showsValue {
              TextField(text: binding(\.value)) { valuePrompt }
                .font(.system(size: 12.5, design: .monospaced))
            } else {
              SecureField(text: binding(\.value)) { valuePrompt }
            }
          }
          .focused($focus, equals: .value)
          .onSubmit { focus = .name }
          Button {
            showsValue.toggle()
            focus = .value
          } label: {
            Image(systemName: showsValue ? "eye.slash" : "eye")
              .font(.system(size: 12))
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(VortexColor.secondaryText)
          .help(showsValue ? Text("Hide the value", bundle: .module) : Text("Show the value", bundle: .module))
          .accessibilityLabel(showsValue ? Text("Hide the value", bundle: .module) : Text("Show the value", bundle: .module))
        }
      } caption: {
        if !draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("Looks like: \(draft.kind.title)", bundle: .module)
        } else {
          Text("Kept in the keychain; Claude never sees it.", bundle: .module)
        }
      }

      row(Text("Name", bundle: .module)) {
        TextField(text: binding(\.name)) {
          Text(verbatim: draft.kind.suggestedName)
        }
        .font(.system(size: 13, design: .monospaced))
        .focused($focus, equals: .name)
        .onSubmit { store.send(.saveTapped) }
      } caption: {
        Text("Claude writes it as {{\(draft.name.isEmpty ? draft.kind.suggestedName : draft.name)}}", bundle: .module)
      }

      row(Text("Note", bundle: .module)) {
        TextField(text: binding(\.note)) {
          Text("What it is for; Claude reads it", bundle: .module)
        }
        .focused($focus, equals: .note)
        .onSubmit { store.send(.saveTapped) }
      } caption: {
        EmptyView()
      }

      row(Text("Lives", bundle: .module)) {
        SegmentedPicker(selection: binding(\.lifetime), options: KeyLifetime.allCases) { lifetime in
          switch lifetime {
          case .hour: Text("1 hour", bundle: .module)
          case .endOfDay: Text("Until the end of the day", bundle: .module)
          case .forever: Text("For good", bundle: .module)
          }
        }
        .frame(width: 380)
      } caption: {
        EmptyView()
      }

      HStack(spacing: 8) {
        if let problem = draft.problem {
          Label {
            message(problem)
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.primaryText)
        }
        Spacer()
        Button {
          store.send(.cancelTapped, animation: .snappy(duration: 0.2))
        } label: {
          Text("Cancel", bundle: .module)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        Button {
          store.send(.saveTapped, animation: .snappy(duration: 0.2))
        } label: {
          Text("Save", bundle: .module)
        }
        .buttonStyle(.primaryCapsule)
        .disabled(draft.isSaving)
      }
      .padding(.top, 6)
    }
    .textFieldStyle(.plain)
    .font(.system(size: 13))
    .padding(.horizontal, 22)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      // The window may still be opening: asked again until the field has the keyboard.
      for _ in 0..<10 where focus == nil && !Task.isCancelled {
        focus = .value
        try? await Task.sleep(for: .milliseconds(30))
      }
    }
  }

  private var valuePrompt: Text {
    Text("Token, password or connection URL", bundle: .module)
  }

  private func row<Field: View, Caption: View>(
    _ title: Text,
    @ViewBuilder field: () -> Field,
    @ViewBuilder caption: () -> Caption
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      title
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.tertiaryText)
        .frame(width: 70, alignment: .leading)
      VStack(alignment: .leading, spacing: 5) {
        field()
          .padding(.horizontal, 10)
          .frame(height: 32)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
        caption()
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
      }
    }
    .padding(.bottom, 12)
  }

  private func message(_ problem: KeyDraft.Problem) -> Text {
    switch problem {
    case .noValue: Text("Paste the value first.", bundle: .module)
    case .badName: Text("A name has letters, digits, dots, dashes or underscores, and no spaces.", bundle: .module)
    case .nameTaken: Text("A key by this name is there already.", bundle: .module)
    case .notSaved: Text("The keychain did not take it. Try again.", bundle: .module)
    }
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<KeyDraft, Value>) -> Binding<Value> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { value in
        var changed = store.draft ?? draft
        changed[keyPath: keyPath] = value
        store.send(.draftChanged(changed))
      }
    )
  }
}
