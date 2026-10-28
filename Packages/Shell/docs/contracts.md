# Contracts

## Provides
- `ShellController` — created by App at launch: `start()`, `receiveFiles(_:)` for files opened with Vortex, and `saveSettings()` when the app quits.
- To feature tabs: `notchCutout` and `isWindowOpen` in the SwiftUI environment.
- Puts the Home widgets of enabled features, in sidebar order, into the environment of the tab content (`homeWidgets`).
- Puts `keyboardCleaning` there too: the action behind Home's keyboard button.
- `@Shared(.permissionStatuses)`: what macOS says, from `PermissionsClient.updates()` at launch on, and re-read each time the window opens (`refresh()`). Only the shell writes it.
- `@Shared(.appBlocked)`: true while a permission that is required and needed reads `notGranted`; false before the first read. `notNeeded` and `grantedAfterRestart` count as on. Only the shell writes it.
- Needed (`PermissionCatalog`): the `permissionNeeds` of enabled features in sidebar order, plus Accessibility for keyboard cleaning while Home (id `home`, which has the button) is on, with the reason «Блокує клавіатуру, поки ти її чистиш.».
- Required: `OnboardingConfig.requiredPermissions`, empty now, copied into the state, where QA mode may change it. It counts only for needed permissions.
- Takes the requests of `PermissionPage` from launch on; for now each one goes to `PermissionsClient.request`.

## Owns
- The notch window, the ears around the notch and the menu bar icon (Window/). Nothing outside the shell opens or closes the window.

## Uses
- FeatureRegistry: every `FeatureModule` — descriptor (with `permissionNeeds`), `makeTab()`, `makeSettings()`, `makeHomeWidget()`, `acceptsFileDrops`, `receiveFiles(_:)`, `setEnabled(_:)`.
- VortexCore: `FeatureModule`, `@Shared(.notchIndicators)`, `Permission`, `PermissionPage`, design system, `AppTheme`, `AppLanguage`.
- VortexPlatform: `HotkeyClient`, `LaunchAtLoginClient`, `SystemClient`, `KeyboardLockClient`, `PermissionsClient`; `OutsideActivity` to keep the window open during drags out of it, Quick Look and the folder picker; `QuickLook`, which the window hands the Quick Look panel to.
