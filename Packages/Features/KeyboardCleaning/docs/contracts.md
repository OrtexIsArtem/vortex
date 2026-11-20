# Contracts

## Provides
- `KeyboardCleaningModule`: id `keyboard`, a utility (`UtilityModule`, no tab), recommended; settings; `setEnabled(false)` ends a lock under way.
- The catalog's description: one line, details, author; keeps nothing; media in Resources/Catalog: a still of the lock screen and a 2 s clip of it, temporary, until the rig records the lock at work.
- One utility action, `keyboard.lock` ("Lock Keyboard", help "Lock the keyboard for cleaning", `keyboard`): window `.open`, permission Accessibility, shortcut `lockKeyboard`; it sends `startTapped`.
- Its cover, `makeWindowCover()`: the lock screen. It puts `WindowCover(feature: "keyboard", holdsKeyboard: true)` in `@Shared(.windowCover)` as the lock starts and takes it down as the lock ends, however it ends.
- Its own shortcut `Hotkey.lockKeyboard`, which the shell records on its settings page and listens for, through the utility action.
- `permissionNeeds`: Accessibility, "Locks the keyboard while you clean it."; the onboarding asks for it only while the utility is added.
- QA mode (debug builds, KeyboardCleaningQA.swift): the command `keyboard press=start|stop|turnOn|restart|key=<name>` (`start` presses its shortcut, which the shell runs as the action) and the state section `keyboard` (whether it is locked, the board, each pressed key's wash).

## Uses
- VortexCore: `FeatureModule`, `UtilityAction`, `WindowCover` and `@Shared(.windowCover)`, `@SharedReader(.permissionStatuses)` (its loss ends the lock), `permissionPage.open(.accessibility)` and `openRefused(.accessibility)` instead of asking macOS, design system (`SettingsRow`, `PermissionRows`, `PrimaryCapsuleButtonStyle`).
- VortexPlatform:
  - `KeyboardLockClient`: `lock`, `unlock`, `presses` (the keys it holds back, and those that got past it, which the shell hands over with `reportPassed`), `layout` (the board to draw, read at each lock);
  - `PermissionsClient.refresh`, `SystemClient.relaunch`, `QA` in debug builds.
- The shell, through the cover: the window kept open, Vortex in front holding the keyboard, the window closed as the cover goes.
