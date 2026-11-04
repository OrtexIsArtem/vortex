#!/bin/sh
# KeyboardShortcuts ships no Ukrainian: its recorder said "Record Shortcut" in a Ukrainian Vortex, and Russian when
# macOS lists Russian before English. A build phase of the app (project.yml) runs this once Xcode has copied the
# library's resource bundle into the app, and adds our uk.lproj (App/KeyboardShortcuts) to that copy. Remove both once
# the library ships uk.
set -eu

resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/KeyboardShortcuts_KeyboardShortcuts.bundle/Contents/Resources"
source="$SRCROOT/App/KeyboardShortcuts/uk.lproj/Localizable.strings"
target="$resources/uk.lproj/Localizable.strings"

if [ ! -d "$resources" ]; then
  echo "error: no KeyboardShortcuts bundle at $resources; update scripts/keyboard-shortcuts-uk.sh" >&2
  exit 1
fi
# A uk.lproj without our first line is the library's own: it wins, and this step has done its job.
if [ -e "$target" ] && ! grep -q '^/\* Vortex adds this file' "$target"; then
  echo "warning: KeyboardShortcuts ships Ukrainian now: remove scripts/keyboard-shortcuts-uk.sh, its build phase and App/KeyboardShortcuts"
  exit 0
fi
mkdir -p "$resources/uk.lproj"
cp "$source" "$target"
