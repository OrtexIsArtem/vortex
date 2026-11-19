# Contracts

## Provides
- `HomeModule`: id `home`, the Home tab; built in (`isBuiltIn`): always added and running, never in the catalog, never stopped after a crash.
- `setEnabled(true)` starts following `@Shared(.runningHomeWidgets)` and `@Shared(.homeAddRequests)`, and `setEnabled(false)` stops it.
- `@Shared(.featuresOnHome)`: the features with a widget on Home as saved, the editor's edits counted once Done keeps them; only Home writes it.
- Takes each feature out of `homeAddRequests` once it has put its first widget on Home or found no room; a request that comes while the editor is open waits for it to end.
- `@Shared(.noRoomOnHome)`: Home puts in each feature whose request found no room, and takes it out once a widget of the feature is on Home, however it got there; the shell empties it as the tab changes.
- QA mode (debug builds, HomeQA.swift), while the open window shows Home: the command `home edit|done|cancel|feature id=|back|search [text=]|hover [id=]|resize id= size=|add id= [size=]|remove id=|move id= column= row=`, each what the editor's control sends (`search` what the panel's search field holds), and the state section `home`: the layout, the editor's draft, what shows, the editor, the copy, the requests and those that found no room.

## Uses
- VortexCore:
  - `HomeWidget`, `HomeWidgetSize`, `HomeGrid`, `HomeWidgetPlace`, `HomeWidgetInfo`, `View.homeWidgetCard(size:)`;
  - the environment values `homeWidgets` (the views of the running features' widgets), `windowRequest` (the editor's large window with the focus), `showCatalog` ("More widgets in Features"), `keyboardCleaning` (the action behind the keyboard button), `isWindowOpen` (closing ends the editor as Cancel does) and `notchCutout` (the notch row widget reads it);
  - `@SharedReader(.permissionStatuses)`, written by the shell: Accessibility's warning on the keyboard button;
  - the design system (`VortexColor.dock`, `.panel`, `WarningMark`, `PermissionMark`, the capsule button styles).
- VortexPlatform: `QA`, in debug builds.
