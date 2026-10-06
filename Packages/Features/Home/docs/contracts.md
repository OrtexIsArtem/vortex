# Contracts

## Provides
- `HomeModule`: id `home`, the Home tab; no settings, no background work.

## Uses
- VortexCore:
  - `HomeWidget` and `HomeSlot`;
  - the environment value `homeWidgets`, filled by the shell from enabled features in sidebar order;
  - `notchCutout`, which the header widget reads itself;
  - the design system (`VortexColor.dock`).
