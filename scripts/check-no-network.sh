#!/bin/sh
# Vortex never goes online by itself. Network APIs are allowed only in the Secrets feature,
# where Claude asks the app to reach a database or an API with a stored key.
set -eu
cd "$(dirname "$0")/.."

# Lines of Swift matching $1 outside Secrets, comments left out.
search() {
  grep -rEn "$1" --include='*.swift' --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=Secrets \
    App Packages Tools 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

# Web views and link previews load pages too.
matches=$(search 'URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|WebSocket|AsyncImage|LinkPresentation|LPMetadataProvider|WebKit|WKWebView')

if [ -n "$matches" ]; then
  echo "error: network APIs are allowed only in Packages/Features/Secrets:" >&2
  echo "$matches" >&2
  exit 1
fi

# A command can reach the network (curl), so processes start only in the two Platform clients made for it, and
# commands run only in Secrets.
processes=$(search '(^|[^A-Za-z0-9_])(Process(\(|\.run)|NSTask|posix_spawn)' |
  grep -vE '^Packages/Platform/(Sources/Clients/(CommandClient|SystemClient)|Tests/CommandClientTests)\.swift:' || true)
# QA mode's stand-in for the command client runs nothing; it may name the client, and the line above still holds there.
commands=$(search '(^|[^A-Za-z0-9_])(commandClient|CommandClient([^A-Za-z0-9_]|$))' |
  grep -vE '^Packages/Platform/(Sources/Clients/(CommandClient|SystemClient)|Sources/QA/QAClients|Tests/CommandClientTests)\.swift:' || true)

if [ -n "$processes$commands" ]; then
  echo "error: processes start only in Platform's CommandClient and SystemClient, and commands run only in Packages/Features/Secrets:" >&2
  printf '%s\n' "$processes" "$commands" | grep -v '^$' >&2
  exit 1
fi

echo "OK: no network APIs or commands outside Secrets"
