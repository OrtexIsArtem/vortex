#!/bin/sh
# Installs Vortex, or updates it, from its latest GitHub release:
#
#   curl -fsSL https://vortex-notch.web.app/install.sh | sh
#
# Downloaded by curl, the app carries no quarantine, so macOS opens it without the "Open Anyway" step. Before it
# touches Applications, the script checks that the download is Vortex signed with the project's certificate, the one
# that keeps Vortex's permissions across updates (scripts/sign-release.sh in the repository pins the same one).
#
# Everything runs inside main, so a download cut short runs nothing.
set -eu

main() {
  repo=OrtexIsArtem/vortex
  bundle_id=io.github.ortexisartem.vortex
  certificate_sha1=e33103feda938ec4b07b8a797c75728577155110
  app=/Applications/Vortex.app

  [ "$(uname -s)" = Darwin ] || fail "Vortex runs on macOS only."
  [ "$(uname -m)" = arm64 ] || fail "Vortex needs a Mac with Apple silicon."
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Vortex needs macOS 14 or later."

  # A run cut short between the two moves below leaves the old copy as Vortex.app.old: it goes back first.
  if [ ! -e "$app" ] && [ -d "$app.old" ]; then
    mv "$app.old" "$app"
  fi
  rm -rf "$app.new"

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
  if [ -n "$installed" ] && newer "$installed" "$version"; then
    printf 'Vortex %s in Applications is newer than the latest release, %s, so it stays.\n' "$installed" "$version"
    exit 0
  fi

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  printf 'Downloading Vortex %s…\n' "$version"
  curl -fsSL -o "$work/Vortex.zip" "https://github.com/$repo/releases/download/$tag/Vortex-$tag.zip" \
    || fail "the download failed."
  ditto -x -k "$work/Vortex.zip" "$work/zip"
  new="$work/zip/Vortex/Vortex.app"
  [ -d "$new" ] || fail "the download holds no Vortex.app."
  codesign --verify --strict --deep \
    -R "=identifier \"$bundle_id\" and certificate leaf = H\"$certificate_sha1\"" "$new" 2>/dev/null \
    || fail "the download isn't Vortex signed with its certificate, so it isn't installed."

  # The new copy next to the old one, then two renames in the same folder: the old copy only ever moves whole, comes
  # back if the new one can't take its place, and is deleted only once the new one is there.
  ditto "$new" "$app.new" || fail "can't write to /Applications."
  running=$(pgrep -f "^$app/Contents/MacOS/Vortex" || true)
  if [ -e "$app" ]; then
    rm -rf "$app.old"
    if ! mv "$app" "$app.old" 2>/dev/null; then
      rm -rf "$app.new"
      fail "macOS didn't let Terminal replace Vortex. Allow Terminal in System Settings › Privacy & Security › App Management, or move Vortex from Applications to the Bin yourself, then run this again."
    fi
  fi
  if ! mv "$app.new" "$app" 2>/dev/null; then
    if [ -e "$app.old" ]; then mv "$app.old" "$app" || true; fi
    rm -rf "$app.new"
    fail "can't put the new Vortex in Applications, so the old one stays."
  fi

  # The new Vortex asks a running one to quit, which saves its settings; the old copy goes once that one is gone.
  open "$app"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$running" ] && kill -0 $running 2>/dev/null || break
    sleep 1
  done
  rm -rf "$app.old" 2>/dev/null || true
  printf 'Vortex %s is in Applications and open.\n' "$version"
  if [ -e "$app.old" ]; then
    printf 'macOS kept the old copy as %s: move it to the Bin.\n' "$app.old"
  fi
}

fail() {
  printf 'Vortex: %s\n' "$*" >&2
  exit 1
}

# Whether version $1 is newer than $2, compared number by number.
newer() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, ".")
    for (i = 1; i <= (n > m ? n : m); i++) {
      if (x[i] + 0 > y[i] + 0) exit 0
      if (x[i] + 0 < y[i] + 0) exit 1
    }
    exit 1
  }'
}

main "$@"
