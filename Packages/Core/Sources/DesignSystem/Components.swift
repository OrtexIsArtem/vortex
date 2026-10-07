import SwiftUI

/// A bare switch in the monochrome style: accent track when on, quiet track when off.
/// The label is not drawn — the row around the switch shows the title — but VoiceOver reads it.
public struct VortexToggleStyle: ToggleStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      Capsule()
        .fill(configuration.isOn ? VortexColor.accent : VortexColor.track)
        .frame(width: 34, height: 20)
        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
          Circle()
            .fill(configuration.isOn ? VortexColor.onAccent : VortexColor.primaryText.opacity(0.85))
            .frame(width: 16, height: 16)
            .padding(2)
        }
        .animation(.snappy(duration: 0.18), value: configuration.isOn)
        .frame(minWidth: VortexMetrics.hitTarget, minHeight: VortexMetrics.hitTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }
    }
  }
}

extension ToggleStyle where Self == VortexToggleStyle {
  public static var vortex: VortexToggleStyle { VortexToggleStyle() }
}

/// The one primary action of a screen: a filled capsule. Next to the notch, where the controls are 34 pt, a taller one.
public struct PrimaryCapsuleButtonStyle: ButtonStyle {
  private let height: CGFloat
  private let fontSize: CGFloat

  public init(height: CGFloat = 30, fontSize: CGFloat = 12.5) {
    self.height = height
    self.fontSize = fontSize
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: fontSize, weight: .semibold))
      .padding(.horizontal, 14)
      .frame(height: height)
      .background(Capsule().fill(VortexColor.accent))
      .foregroundStyle(VortexColor.onAccent)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == PrimaryCapsuleButtonStyle {
  public static var primaryCapsule: PrimaryCapsuleButtonStyle { PrimaryCapsuleButtonStyle() }
}

/// Any other action: a quiet capsule that does not compete with the primary one.
public struct QuietCapsuleButtonStyle: ButtonStyle {
  private let height: CGFloat
  private let fontSize: CGFloat

  public init(height: CGFloat = 30, fontSize: CGFloat = 12.5) {
    self.height = height
    self.fontSize = fontSize
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: fontSize, weight: .medium))
      .padding(.horizontal, 14)
      .frame(height: height)
      .background(Capsule().fill(VortexColor.raised))
      .foregroundStyle(VortexColor.primaryText)
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == QuietCapsuleButtonStyle {
  public static var quietCapsule: QuietCapsuleButtonStyle { QuietCapsuleButtonStyle() }
}

/// Segmented control in the monochrome style.
public struct SegmentedPicker<Value: Hashable, Label: View>: View {
  @Binding private var selection: Value
  private let options: [Value]
  private let label: (Value) -> Label

  public init(selection: Binding<Value>, options: [Value], @ViewBuilder label: @escaping (Value) -> Label) {
    _selection = selection
    self.options = options
    self.label = label
  }

  public var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.self) { option in
        let isSelected = option == selection
        Button {
          selection = option
        } label: {
          label(option)
            .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
            // One line: the heavier type of the chosen option would otherwise wrap a long label.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? VortexColor.primaryText : VortexColor.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? VortexColor.track : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 10).fill(VortexColor.raised))
  }
}

/// One-pixel separator in the palette's line color.
public struct Hairline: View {
  public init() {}

  public var body: some View {
    Rectangle()
      .fill(VortexColor.line)
      .frame(height: 1)
  }
}

/// A setting: optional symbol, title and caption on the left, the control on the right, a hairline below.
/// The shell's settings and every feature's own settings use it, so they read as one list.
public struct SettingsRow<Control: View>: View {
  private let title: Text
  private let caption: Text?
  private let symbol: String?
  private let control: Control

  public init(title: Text, caption: Text? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
    self.title = title
    self.caption = caption
    self.symbol = symbol
    self.control = control()
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        if let symbol {
          Image(systemName: symbol)
            .frame(width: 20)
            .foregroundStyle(VortexColor.secondaryText)
        }
        VStack(alignment: .leading, spacing: 2) {
          title
          if let caption {
            caption
              .font(.system(size: 11.5))
              .foregroundStyle(VortexColor.tertiaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 12)
        control
      }
      .frame(minHeight: 48)
      Hairline()
    }
  }
}

extension SettingsRow where Control == Toggle<Text> {
  /// A row whose control is an on/off switch named by the row's title. Needs `.toggleStyle(.vortex)` around it.
  public init(title: Text, caption: Text? = nil, symbol: String? = nil, isOn: Binding<Bool>) {
    self.init(title: title, caption: caption, symbol: symbol) {
      Toggle(isOn: isOn) { title }
    }
  }
}
