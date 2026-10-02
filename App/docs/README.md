# App

macOS app shell: the entry point, the menu bar item and, from stage 1, the notch window, hotkeys and settings window.
It reads features only through FeatureRegistry and the FeatureModule contract, never by importing a feature directly.
Target settings (bundle id, signing, Info.plist keys) live in project.yml.
