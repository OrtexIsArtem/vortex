import SwiftUI

/// Switch drawn in the monochrome style: accent track when on, quiet track when off.
public struct VortexToggleStyle: ToggleStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 10) {
        configuration.label
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
      }
      .frame(minHeight: VortexMetrics.hitTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(Text(configuration.isOn ? "1" : "0"))
  }
}

extension ToggleStyle where Self == VortexToggleStyle {
  public static var vortex: VortexToggleStyle { VortexToggleStyle() }
}

/// The one primary action of a screen: a filled capsule.
public struct PrimaryCapsuleButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12.5, weight: .semibold))
      .padding(.horizontal, 14)
      .frame(height: 30)
      .background(Capsule().fill(VortexColor.accent))
      .foregroundStyle(VortexColor.onAccent)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == PrimaryCapsuleButtonStyle {
  public static var primaryCapsule: PrimaryCapsuleButtonStyle { PrimaryCapsuleButtonStyle() }
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
