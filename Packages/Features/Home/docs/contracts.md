# Contracts

## Provides
- `HomeModule`: id `home`, the Home tab; no settings, no background work.
- Built in (`isBuiltIn`): always added and running, never in the catalog, never stopped after a crash; it keeps nothing.

## Uses
- VortexCore:
  - `HomeWidget` and `HomeSlot`;
  - the environment value `homeWidgets`, filled by the shell from enabled features in sidebar order;
  - the environment value `keyboardCleaning`, the shell's action behind the keyboard button;
  - `notchCutout`, which the header widget reads itself;
  - `@SharedReader(.permissionStatuses)`, written by the shell: Accessibility's warning on the keyboard button;
  - the design system (`VortexColor.dock`, `WarningMark`, `PermissionMark`).
