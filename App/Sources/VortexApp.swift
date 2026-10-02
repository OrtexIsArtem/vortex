import FeatureRegistry
import SwiftUI

@main
struct VortexApp: App {
  var body: some Scene {
    MenuBarExtra("Vortex", systemImage: "tornado") {
      Text("Features: \(FeatureRegistry.all.count)")
      Divider()
      Button("Quit Vortex") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
