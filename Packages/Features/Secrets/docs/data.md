# Data

Tables are created by the feature's migrator (`secrets.v1`) before its first query.

| What | Where | How long |
| --- | --- | --- |
| A key: id, name, kind, note, when added, when it expires, when last used | table `secrets_key` | until deleted or expired |
| A key's value | login keychain, service `io.github.ortexisartem.vortex.keys`, account = the key's id, label «Vortex: name» | as long as its key |
| A use: when, which keys by name, who, the command as written, how it ended, exit code | table `secrets_use` | 30 days; the log shows the latest 200 |
| The MCP server's token | login keychain, service `io.github.ortexisartem.vortex.mcp`, account `token` | always |
| Port, whether Claude Code connected once | DataFolder/secrets.json | always |

- Values never reach the database, the log or a file; a command's text holds placeholders, the output is cleaned before Claude or the log gets it.
- The value is saved before the row; at launch, values without a row are deleted (Vortex stopped between them, or while a deletion could still be taken back).
- A deleted key's row goes at once, its value once the deletion can't be taken back (5 s, or the next change).
- Rows this version can't read (written by a newer Vortex) are skipped and kept, their values too.
- Sessions and what was allowed in them live only in memory; past 50 sessions the least recently used one is let go (Claude Code never ends its own).
