#!/bin/sh
# Installs Vortex, or updates it, from its latest GitHub release:
#
#   curl -fsSL https://vortex-notch.web.app/install.sh | sh
#
# Downloaded by curl, the app carries no quarantine, so macOS opens it without the "Open Anyway" step. Before it
# touches Applications, the script checks that the download is Vortex signed with the project's certificate, the one
# that keeps Vortex's permissions across updates (scripts/sign-release.sh in the repository pins the same one).
set -eu

repo=OrtexIsArtem/vortex
bundle_id=io.github.ortexisartem.vortex
certificate_sha1=e33103feda938ec4b07b8a797c75728577155110
app=/Applications/Vortex.app

fail() {
  printf 'Vortex: %s\n' "$*" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "Vortex runs on macOS only."
[ "$(uname -m)" = arm64 ] || fail "Vortex needs a Mac with Apple silicon."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Vortex needs macOS 14 or later."

# GitHub sends /releases/latest on to the newest release's tag.
latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") \
  || fail "GitHub can't be reached."
tag=${latest##*/}
case $tag in
  v[0-9]*) ;;
  *) fail "no release found on GitHub." ;;
esac
version=${tag#v}

installed=""
if [ -e "$app" ]; then
  [ "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)" = "$bundle_id" ] \
    || fail "$app is another app, so it stays. Move it out of Applications, then run this again."
  installed=$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
fi
if [ "$installed" = "$version" ]; then
  printf 'Vortex %s, the latest version, is already in Applications.\n' "$version"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work" 2>/dev/null || true' EXIT

printf 'Downloading Vortex %s…\n' "$version"
curl -fsSL -o "$work/Vortex.zip" "https://github.com/$repo/releases/download/$tag/Vortex-$tag.zip" \
  || fail "the download failed."
ditto -x -k "$work/Vortex.zip" "$work/zip"
new="$work/zip/Vortex/Vortex.app"
[ -d "$new" ] || fail "the download holds no Vortex.app."

codesign --verify --strict --deep "$new" 2>/dev/null || fail "the download's signature is broken."
requirement=$(codesign -d -r - "$new" 2>&1 | sed -n 's/^designated => //p')
[ "$requirement" = "identifier \"$bundle_id\" and certificate leaf = H\"$certificate_sha1\"" ] \
  || fail "the download isn't signed with Vortex's certificate, so it isn't installed."

# The new copy next to the old one, then the swap: the old copy only ever moves whole, and comes back if the new one
# can't take its place.
rm -rf "$app.new"
ditto "$new" "$app.new" || fail "can't write to /Applications."
running=$(pgrep -f "^$app/Contents/MacOS/Vortex" || true)
if [ -e "$app" ] && ! mv "$app" "$work/old" 2>/dev/null; then
  rm -rf "$app.new"
  fail "macOS didn't let Terminal replace Vortex. Allow Terminal in System Settings › Privacy & Security › App Management, or move Vortex from Applications to the Bin yourself, then run this again."
fi
if ! mv "$app.new" "$app"; then
  [ -e "$work/old" ] && mv "$work/old" "$app"
  rm -rf "$app.new"
  fail "can't put the new Vortex in Applications; the old one is back."
fi

# The new Vortex asks a running one to quit, which saves its settings; the old copy is deleted once it has gone.
open "$app"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -n "$running" ] && kill -0 $running 2>/dev/null || break
  sleep 1
done
printf 'Vortex %s is in Applications and open.\n' "$version"
