# Contracts

## Provides
- `SecretsModule`: id `secrets`, tab, settings; `setEnabled` loads the keys, then starts the MCP server, and stops it.
- An MCP server at http://127.0.0.1:<port>/mcp (Streamable HTTP, JSON answers, no stream of server messages), for clients with the bearer token; requests from a web page (another site's Origin or Host) are refused, both checked on the headers before any body is read. Tools: `keys`, `run`. An unknown session id is taken as a new session; `notifications/cancelled` and a closed connection cancel a waiting call.
- A notch indicator while a request waits: a key and the names, flashing (priority 20).
- `makeOnboardingStep()`: the Claude Code step; it inserts `secrets` into `@Shared(.onboardingStepsDone)` once done.
- QA mode: `keys press=connect|connectAgain|copyCommand|getClaudeCode|turnOn|restart`, and the `keys` state section (the step's status, never the token or the command).
- `permissionNeeds`: notifications, «Показує запити Claude на ключ, коли вікно закрите.»
- Debug builds outside QA mode: distributed notifications `…debug.secretsAdd`, `…secretsDeny`, `…secretsState` (see SecretsModule); a QA run (VortexPlatform's `QA`) listens to none. None approves a request: «Дозволити» is pressed by a person, in every build.

## Uses
- VortexCore: `FeatureModule`, `DataFolder`, `database`, `databaseIsOnDisk`, `@Shared(.fileStorage)`, `@Shared(.notchIndicators)`, design system (`PermissionRows`); `@SharedReader(.permissionStatuses)` and `permissionPage.open` for the Notifications row.
- VortexPlatform: `PermissionsClient.refresh` when the settings section appears, `SystemClient.relaunch` for "Restart Vortex", `FileClient.open` for claude.com/claude-code.
- VortexPlatform: `KeychainClient` (values, token), `CommandClient` (the user's shell with the terminal's environment), `PasteboardClient` (copies, concealed where secret), `NotificationClient` (a notification per request, its presses by notification id, taken back by id prefix).
- The network (Network.framework), allowed only in this module by `make check`, and only for the server on the loopback.
