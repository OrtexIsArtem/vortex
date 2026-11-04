import Foundation

/// A system sound's name as System Settings › Sound shows it, in the app's language. The settings keep the file name
/// ("Glass"), which System Settings doesn't show.
enum SoundName {
  /// What the Sound picker shows: System Settings' name, else the file name, as for a sound macOS adds later.
  static func shown(_ file: String) -> String {
    renamed(file) ?? file
  }

  /// The names macOS 26 gives the files in /System/Library/Sounds in System Settings (Sound.appex,
  /// AlertSounds.loctable).
  static func renamed(_ file: String) -> String? {
    switch file {
    case "Basso": String(localized: "Mezzo", bundle: .module, comment: "The system sound Basso, as System Settings › Sound names it")
    case "Blow": String(localized: "Breeze", bundle: .module, comment: "The system sound Blow, as System Settings › Sound names it")
    case "Bottle": String(localized: "Pebble", bundle: .module, comment: "The system sound Bottle, as System Settings › Sound names it")
    case "Frog": String(localized: "Jump", bundle: .module, comment: "The system sound Frog, as System Settings › Sound names it")
    case "Funk": String(localized: "Funky", bundle: .module, comment: "The system sound Funk, as System Settings › Sound names it")
    case "Glass": String(localized: "Crystal", bundle: .module, comment: "The system sound Glass, as System Settings › Sound names it")
    case "Hero": String(localized: "Heroine", bundle: .module, comment: "The system sound Hero, as System Settings › Sound names it")
    case "Morse": String(localized: "Pong", bundle: .module, comment: "The system sound Morse, as System Settings › Sound names it")
    case "Ping": String(localized: "Sonar", bundle: .module, comment: "The system sound Ping, as System Settings › Sound names it")
    case "Pop": String(localized: "Bubble", bundle: .module, comment: "The system sound Pop, as System Settings › Sound names it")
    case "Purr": String(localized: "Pluck", bundle: .module, comment: "The system sound Purr, as System Settings › Sound names it")
    case "Sosumi": String(localized: "Sonumi", bundle: .module, comment: "The system sound Sosumi, as System Settings › Sound names it")
    case "Submarine": String(localized: "Submerge", bundle: .module, comment: "The system sound Submarine, as System Settings › Sound names it")
    case "Tink": String(localized: "Boop", bundle: .module, comment: "The system sound Tink, as System Settings › Sound names it")
    default: nil
    }
  }
}
