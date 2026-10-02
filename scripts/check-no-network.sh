#!/bin/sh
# Vortex never goes online by itself. Network APIs are allowed only in the Secrets feature,
# where Claude asks the app to reach a database or an API with a stored key.
set -eu
cd "$(dirname "$0")/.."

pattern='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|WebSocket'

matches=$(grep -rEn "$pattern" --include='*.swift' \
  --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=Secrets \
  App Packages Tools 2>/dev/null || true)

if [ -n "$matches" ]; then
  echo "error: network APIs are allowed only in Packages/Features/Secrets:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "OK: no network APIs outside Secrets"
