# Contracts

## Provides
- `ShellController` — created by App at launch: `start()`, `receiveFiles(_:)` for files opened with Vortex, and `saveSettings()` when the app quits.
- To feature tabs: `notchCutout` and `isWindowOpen` in the SwiftUI environment.
- Puts the Home widgets of enabled features, in sidebar order, into the environment of the tab content (`homeWidgets`).
- Puts `keyboardCleaning` there too: the action behind Home's keyboard button.

## Owns
- The notch window, the ears around the notch and the menu bar icon (Window/). Nothing outside the shell opens or closes the window.

## Uses
- FeatureRegistry: every `FeatureModule` — descriptor, `makeTab()`, `makeSettings()`, `makeHomeWidget()`, `acceptsFileDrops`, `receiveFiles(_:)`, `setEnabled(_:)`.
- VortexCore: `FeatureModule`, `@Shared(.notchIndicators)`, design system, `AppTheme`, `AppLanguage`.
- VortexPlatform: `HotkeyClient`, `LaunchAtLoginClient`, `SystemClient`, `KeyboardLockClient`; `OutsideActivity` to keep the window open during drags out of it, Quick Look and the folder picker; `QuickLook`, which the window hands the Quick Look panel to.

## QA mode (debug builds)
- Gives App `ShellController.prepareQA()`, called first in main.swift, and `isSameQARun(pid:)`, so one instance runs per QA run.
- Registers with VortexPlatform's `QA`: the window `notch` (mode: why it is open), the state section `shell`, and the commands `entry`, `tab`, `keyboard`, `screens` and `indicator` (QA/ShellQA.swift).
- The menu bar menu's items have identifiers (open, settings, quit), which `entry kind=menu item=` names; a new item needs one too.
- In a QA run the window opens off the displays without animation and never takes the keyboard or the front; there are no ears, no menu bar icon and no click monitor, and the displays are `QA.screens`.
- A QA run listens to no `…debug.*` notification.
