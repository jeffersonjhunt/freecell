#!/bin/bash
# Checks what `make export` produced before anything is uploaded — the things App Store Connect or
# the spec would otherwise catch late, or not at all:
#   signed "Apple Distribution" by the team; no debugger entitlement (iOS: get-task-allow false,
#   Mac: com.apple.security.get-task-allow absent — spec decision 2026-09-27); Mac sandboxed;
#   Game Center and iCloud's key-value store entitled on both (spec "Scores": without them the
#   build still uploads, but sign-in and Top 10 sync silently fail); the privacy manifest inside;
#   the version and build number that were archived.
#
#   tools/check-release.sh <release-dir>                          both exported packages
#   tools/check-release.sh --app <Solitaire.app> <ios|macos> <build>   one app bundle
set -uo pipefail
TEAM=${TEAM:-$(cat "$(dirname "$0")/../.devteam" 2>/dev/null)}
# The version is project.yml's MARKETING_VERSION — one place to change it.
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$(dirname "$0")/../project.yml")
fail=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; fail=1; }

# check_app <app> <ios|macos> <build number>
check_app() {
  local app=$1 platform=$2 build=$3 info res ents
  if [ "$platform" = macos ]; then info="$app/Contents/Info.plist"; res="$app/Contents/Resources"; else info="$app/Info.plist"; res="$app"; fi
  echo "$platform: $app"
  local auth; auth=$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
  case "$auth" in "Apple Distribution: "*"($TEAM)") ok "signed $auth" ;; *) bad "signed by '${auth:-nothing}', not Apple Distribution for team $TEAM" ;; esac
  ents=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')
  if [ "$platform" = macos ]; then
    if printf '%s' "$ents" | grep -q '"com.apple.security.get-task-allow"'; then bad "carries com.apple.security.get-task-allow"; else ok "no com.apple.security.get-task-allow"; fi
    if printf '%s' "$ents" | grep -q '"com.apple.security.app-sandbox":true'; then ok "sandboxed"; else bad "not sandboxed (the Mac App Store requires it)"; fi
  else
    if printf '%s' "$ents" | grep -q '"get-task-allow":true'; then bad "get-task-allow is true (debuggable)"; else ok "get-task-allow not true"; fi
  fi
  if printf '%s' "$ents" | grep -q '"com.apple.developer.game-center":true'; then ok "Game Center entitled"; else bad "no Game Center entitlement"; fi
  if printf '%s' "$ents" | grep -q "\"com.apple.developer.ubiquity-kvstore-identifier\":\"$TEAM.com.oneoffendeavors.solitaire\""; then
    ok "iCloud key-value store entitled"; else bad "no iCloud key-value store entitlement for $TEAM.com.oneoffendeavors.solitaire"; fi
  [ -f "$res/PrivacyInfo.xcprivacy" ] && ok "privacy manifest present" || bad "no PrivacyInfo.xcprivacy"
  local v b; v=$(plutil -extract CFBundleShortVersionString raw "$info" 2>/dev/null); b=$(plutil -extract CFBundleVersion raw "$info" 2>/dev/null)
  [ "$v" = "$VERSION" ] && [ "$b" = "$build" ] && ok "version $v ($b)" || bad "version $v ($b), expected $VERSION ($build)"
}

if [ "${1:-}" = --app ]; then
  check_app "$2" "$3" "$4"
else
  dir=${1:?usage: tools/check-release.sh <release-dir> | --app <app> <ios|macos> <build>}
  build=$(cat "$dir/build-number" 2>/dev/null) || { echo "no $dir/build-number — run make archive"; exit 1; }
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  if [ -f "$dir/export-ios/Solitaire.ipa" ]; then
    (cd "$t" && unzip -q "$OLDPWD/$dir/export-ios/Solitaire.ipa") && check_app "$t/Payload/Solitaire.app" ios "$build"
  else bad "no $dir/export-ios/Solitaire.ipa"; fi
  if [ -f "$dir/export-macos/Solitaire.pkg" ]; then
    echo "macos installer: $(pkgutil --check-signature "$dir/export-macos/Solitaire.pkg" | sed -n 's/^ *1\. //p')"
    pkgutil --expand-full "$dir/export-macos/Solitaire.pkg" "$t/pkg" >/dev/null
    check_app "$(find "$t/pkg" -name Solitaire.app -maxdepth 4 | head -1)" macos "$build"
  else bad "no $dir/export-macos/Solitaire.pkg"; fi
fi
[ "$fail" = 0 ] && echo "release check passed" || { echo "release check FAILED"; exit 1; }
