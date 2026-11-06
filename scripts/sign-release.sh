#!/bin/bash
# Signs a release build of Vortex with the project's permanent self-signed certificate. Every release then has the
# same designated requirement (`identifier … and certificate leaf = H"…"`), so macOS keeps Vortex's permissions
# (Accessibility, Screen Recording, browsers) across updates. Ad hoc signing gives every build a requirement of its
# own, and macOS took each release for a new app.
#
#   scripts/sign-release.sh <Vortex.app>
#
# Needs VORTEX_SIGNING_P12 (the certificate with its private key, a base64-encoded .p12) and VORTEX_SIGNING_PASSWORD
# (its password): GitHub secrets in the release workflow. The certificate must be the one pinned below, which
# site/public/install.sh pins too: another one would cost every user their permissions once more.
#
# The hardened runtime stays on, without library validation: macOS validates libraries by Team ID, which only Apple
# issues, so it refuses the embedded Swift library (libswiftCompatibilitySpan.dylib) of a self-signed app.
set -euo pipefail

# SHA-1 of the "Vortex Release Signing" certificate, valid until November 2036.
CERTIFICATE_SHA1=e33103feda938ec4b07b8a797c75728577155110

app=${1:?usage: scripts/sign-release.sh <Vortex.app>}
[ -d "$app/Contents/MacOS" ] || { echo "sign-release: no app at $app" >&2; exit 64; }
: "${VORTEX_SIGNING_P12:?sign-release: VORTEX_SIGNING_P12 is not set}"
: "${VORTEX_SIGNING_PASSWORD:?sign-release: VORTEX_SIGNING_PASSWORD is not set}"

work=$(mktemp -d)
keychain="$work/signing.keychain-db"
keychain_password=$(openssl rand -hex 16)
search_list=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')

cleanup() {
  # The user's keychain search list ends as it started, and the temporary keychain goes with the folder.
  # shellcheck disable=SC2086
  (set -f; IFS=$'\n'; security list-keychains -d user -s $search_list)
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

printf '%s' "$VORTEX_SIGNING_P12" | tr -d '\r\n ' | base64 --decode > "$work/signing.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/signing.p12" -k "$keychain" -P "$VORTEX_SIGNING_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
# codesign finds an identity only in a keychain on the search list, even with --keychain.
# shellcheck disable=SC2086
(set -f; IFS=$'\n'; security list-keychains -d user -s "$keychain" $search_list)

identity=$(security find-identity -p codesigning "$keychain" | awk '/"Vortex Release Signing"/ { print $2; exit }')
if [ "$(echo "$identity" | tr '[:upper:]' '[:lower:]')" != "$CERTIFICATE_SHA1" ]; then
  echo "sign-release: the secret holds another certificate (${identity:-none}), not $CERTIFICATE_SHA1" >&2
  exit 1
fi

# The app's own entitlements, as Xcode signed them from App/Vortex.entitlements, without library validation.
codesign -d --entitlements - --xml "$app" > "$work/entitlements.plist" 2>/dev/null || true
[ -s "$work/entitlements.plist" ] || plutil -create xml1 "$work/entitlements.plist"
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.cs.disable-library-validation" "$work/entitlements.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$work/entitlements.plist"

sign() { codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$@"; }

# Inside out: every Mach-O file in the bundle but the main executable, the deepest first, then the app itself.
main_executable="$app/Contents/MacOS/$(defaults read "$(cd "$app" && pwd)/Contents/Info" CFBundleExecutable)"
nested=()
while IFS= read -r -d '' file; do
  if [ "$file" != "$main_executable" ] && file -b "$file" | grep -q '^Mach-O'; then nested+=("$file"); fi
done < <(find "$app/Contents" -type f -print0)
if [ ${#nested[@]} -gt 0 ]; then
  while IFS= read -r file; do
    sign "$file"
  done < <(for file in "${nested[@]}"; do printf '%s\t%s\n' "$(tr -cd '/' <<< "$file" | wc -c)" "$file"; done | sort -rn | cut -f2-)
fi
sign --options runtime --entitlements "$work/entitlements.plist" "$app"

codesign --verify --strict --deep "$app"
requirement=$(codesign -d -r - "$app" 2>&1 | sed -n 's/^designated => //p')
bundle_id=$(defaults read "$(cd "$app" && pwd)/Contents/Info" CFBundleIdentifier)
expected="identifier \"$bundle_id\" and certificate leaf = H\"$CERTIFICATE_SHA1\""
if [ "$requirement" != "$expected" ]; then
  echo "sign-release: designated requirement is '$requirement', expected '$expected'" >&2
  exit 1
fi
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.cs.disable-library-validation' \
  || { echo "sign-release: library validation is still on" >&2; exit 1; }
echo "Signed $app"
echo "  designated => $requirement"
