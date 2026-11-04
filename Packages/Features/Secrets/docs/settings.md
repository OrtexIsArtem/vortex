# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Port | 47823 | Where the MCP server listens, on 127.0.0.1 only; 1024–65535. After a change Claude Code is connected again with the new command. |
| Claude Code | — | "Copy the connect command": `claude mcp remove --scope user vortex >/dev/null 2>&1; claude mcp add --transport http --scope user vortex http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`, copied concealed. Claude Code keeps the token in ~/.claude.json. |

- Stored in DataFolder/secrets.json, with whether Claude Code has connected once (the tab then stops showing how).
- The status line says whether the server runs, starts, or why it could not: the port taken, an unexpected error (the system's words go only to the log), or no token from the keychain.
- Notifications off: a row "⚠ Notifications · Shows Claude's key requests when the window is closed." with "Turn on", which opens the shell's page; ↻ shows "Works after restart" with "Restart Vortex"; otherwise no row.
- The section re-reads the statuses when it appears (`PermissionsClient.refresh`).
- `addedToClaudeCode` in secrets.json: the onboarding's Connect worked once, so the step stays done after a relaunch.
