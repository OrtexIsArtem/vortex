# Contracts

## Provides
- `SecretsModule`: id `secrets`, tab, settings; `setEnabled` loads the keys, then starts the MCP server, and stops it.
- An MCP server at http://127.0.0.1:<port>/mcp (Streamable HTTP, JSON answers, no stream of server messages), for clients with the bearer token; requests from a web page (another site's Origin or Host) are refused, both checked on the headers before any body is read. Tools: `keys`, `run`. An unknown session id is taken as a new session; `notifications/cancelled` and a closed connection cancel a waiting call.
- A notch indicator while a request waits: a key and the names, flashing (priority 20).
- Debug builds: distributed notifications `…debug.secretsAdd`, `…secretsDeny`, `…secretsState` (see SecretsModule). None approves a request: «Дозволити» is pressed by a person, in every build.

## Uses
- VortexCore: `FeatureModule`, `DataFolder`, `database`, `@Shared(.fileStorage)`, `@Shared(.notchIndicators)`, design system.
- VortexPlatform: `KeychainClient` (values, token), `AuthenticationClient` (Touch ID to show a value), `CommandClient` (the login shell), `PasteboardClient` (copies, concealed where secret), `NotificationClient` (the request with buttons).
- The network (Network.framework), allowed only in this module by `make check`, and only for the server on the loopback.
