# Vortex — rules for Claude

Personal macOS utility that lives in the notch and the menu bar.
Product spec: docs/spec.ru.md (Russian). Plan and progress: docs/plan.md. Module map: docs/README.md.

## Stack
- Swift 6 language mode with strict concurrency. SwiftUI + The Composable Architecture 1.x (pinned; do not move to 2.0 until it is stable).
- macOS 14+, Apple silicon only. Offline by design: no analytics, no auto-updates, no network.
- XcodeGen: project.yml is the source of truth for Vortex.xcodeproj. Never hand-edit the .xcodeproj — change project.yml, run `make project`, commit both.
- All modules live in the local package Packages/ (VortexKit, see Packages/Package.swift).

## Commands
- `make project` — regenerate Vortex.xcodeproj from project.yml
- `make build` — compile the app without signing (for checks)
- `make test` — run package tests
- `make check` — no-network rule (also runs as a build phase)
- `make open` — regenerate and open in Xcode

## Architecture
1. A feature never imports another feature. Features talk only through contracts in VortexCore or through the app shell.
2. A feature brings everything of its own: sidebar tab, settings, Home widget, database tables prefixed with its id, their migrations, its docs.
3. New feature: copy Features/_Template to Features/<Name>, rename the module and types, add "<Name>" to `features` in Packages/Package.swift and one line to Features/Registry. Removing a feature = deleting its folder and those two lines; everything else must still build.
4. If nobody fulfils a contract, the caller hides the control (e.g. "Make key" disappears without Secrets).
5. System APIs (pasteboard, screenshots, files, Keychain, notch, hotkeys) only through clients in VortexPlatform, so every feature can be tested with substituted clients.

## Working rules
- One task = one feature. Don't touch other modules.
- Network code only in Features/Secrets; `make check` fails the build otherwise.
- After every change: build and run the tests of the module you touched.
- Nothing heavy on the main thread: OCR, database and previews run in the background. Track the cursor near the notch with system events, never by polling.
- Library versions are pinned in Package.resolved. Update them only when explicitly asked.
- UI strings in Ukrainian and English (String Catalog). Code, comments and docs in English.
- Design reference: the canvas linked in docs/README.md. Monochrome by default, minimal, large click targets.

## Signing
- Bundle id: io.github.ortexisartem.vortex.

## Git
- Commits are authored by the repository owner only. Never add Co-Authored-By trailers or "Generated with" lines to commits or pull requests.
- Branch `main`; small commits with a clear message in English.

## Feature docs
Each feature keeps short docs next to its code: docs/README.md (map, ≤15 lines), behavior.md, settings.md, data.md, contracts.md (≤60 lines each). Plain language, one checkable rule per line. Core, Platform and App have docs/README.md too.

Read docs only when the change touches them:

| Change | Read | Update |
| --- | --- | --- |
| Colors, spacing, fonts, icons, label text | nothing | nothing |
| Behavior: what happens after an action | README, then behavior.md | behavior.md |
| Settings: new, removed or default value | README, then settings.md | settings.md |
| Storage: table, field, retention | README, then data.md | data.md |
| Link to another feature or the system | README, then contracts.md | contracts.md |
| New feature | — | copy docs from _Template and fill them |
| Removed feature | — | nothing, docs go with the folder |

Read a file once per session. After a change ask two questions: does the change contradict the docs (fix that line)? Is there a new rule worth knowing (add one line)? If both answers are no, leave the docs alone. docs/README.md at the root is read only when a change spans several modules.
