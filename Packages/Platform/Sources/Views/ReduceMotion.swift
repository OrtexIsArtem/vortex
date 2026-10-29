import AppKit
import SwiftUI
import VortexCore

extension EnvironmentValues {
  /// Whether motion should be reduced: macOS's Reduce Motion, followed as it changes. A QA run started with
  /// `--qa-reduce-motion` has it on whatever macOS says. Animations read this rather than `accessibilityReduceMotion`.
  public var reduceMotion: Bool {
    ReduceMotion.isForced || accessibilityReduceMotion
  }
}

/// The same for AppKit code.
public enum ReduceMotion {
  /// macOS's Reduce Motion, or the QA run's.
  @MainActor
  public static var isOn: Bool {
    isForced || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// A QA run started with `--qa-reduce-motion`.
  static var isForced: Bool {
    #if DEBUG
      QALaunch.current.options?.reduceMotion == true
    #else
      false
    #endif
  }
}
