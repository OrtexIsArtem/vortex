# Keys

Docs are in docs/: read docs/README.md, then only the file your change touches (see "Feature docs" in the root CLAUDE.md).
The logic lives in SecretsFeature and is covered by SecretsFeatureTests — change them together. The MCP server is in
MCP/: the protocol in MCPProtocol (pure, tested), the HTTP side in MCPServer. This is the only module allowed to use
the network (`make check`), and only for the local MCP server.
