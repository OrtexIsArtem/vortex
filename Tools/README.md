# Tools

- CLI/vortex — the `vortex` command: `vortex shelf add <files>` puts files on the shelf, for example at the end of
  a build script. It opens the files with Vortex (starting it if needed), which hands them to the shelf without
  opening its window. `make install-cli` links it into /opt/homebrew/bin (or `BINDIR=…`).
- MCP/ — local MCP server that lets Claude Code use stored keys by name (stage 5).
