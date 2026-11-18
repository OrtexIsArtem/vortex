#!/bin/sh
# A feature's catalog media (its looping preview and its still, in Sources/Resources/Catalog) ship inside every copy of
# Vortex, added or not: together they stay under 1.5 MB per feature.
set -eu
cd "$(dirname "$0")/.."

limit=1572864
status=0
for folder in Packages/Features/*/Sources/Resources/Catalog; do
  [ -d "$folder" ] || continue
  bytes=$(find "$folder" -type f -exec stat -f %z {} + | awk '{ total += $1 } END { print total + 0 }')
  if [ "$bytes" -gt "$limit" ]; then
    echo "error: $folder holds $bytes bytes; a feature's catalog media stay under $limit (1.5 MB)" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "OK: every feature's catalog media are under 1.5 MB"
exit "$status"
