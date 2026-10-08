# Tools

- CLI/vortex — the `vortex` command: `vortex shelf add <files>` puts files on the shelf, for example at the end of
  a build script. It opens the files with Vortex (starting it if needed), which hands them to the shelf without
  opening its window. `make install-cli` links it into /opt/homebrew/bin (or `BINDIR=…`).
- The MCP server Claude Code uses keys through runs inside the app (Packages/Features/Secrets), not here.
