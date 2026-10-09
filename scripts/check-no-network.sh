#!/bin/sh
# Vortex never goes online by itself. Network APIs are allowed only in the Secrets feature,
# where Claude asks the app to reach a database or an API with a stored key.
set -eu
cd "$(dirname "$0")/.."

# Web views and link previews load pages too.
pattern='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|WebSocket|AsyncImage|LinkPresentation|LPMetadataProvider|WebKit|WKWebView'

matches=$(grep -rEn "$pattern" --include='*.swift' \
  --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=Secrets \
  App Packages Tools 2>/dev/null || true)

if [ -n "$matches" ]; then
  echo "error: network APIs are allowed only in Packages/Features/Secrets:" >&2
  echo "$matches" >&2
  exit 1
fi

# A command can reach the network (curl), so processes start only in the two Platform clients made for it, and
# commands run only in Secrets.
processes=$(grep -rEn 'Process\(|NSTask|posix_spawn|commandClient' --include='*.swift' \
  --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=Secrets \
  --exclude=CommandClient.swift --exclude=SystemClient.swift \
  App Packages Tools 2>/dev/null || true)

if [ -n "$processes" ]; then
  echo "error: processes start only in Platform's CommandClient and SystemClient, and commands run only in Packages/Features/Secrets:" >&2
  echo "$processes" >&2
  exit 1
fi

echo "OK: no network APIs or commands outside Secrets"
