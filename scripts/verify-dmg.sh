#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
dmg=${1:?Usage: verify-dmg.sh DMG VERSION}
version=${2:?Usage: verify-dmg.sh DMG VERSION}
bash "$script_dir/validate-version.sh" "$version"
hdiutil verify "$dmg"

mountpoint=$(mktemp -d "${TMPDIR:-/tmp}/quick-text-processor-verify.XXXXXX")
attached=false
cleanup() {
    if [[ "$attached" == true ]]; then
        hdiutil detach "$mountpoint" || hdiutil detach -force "$mountpoint" || return 1
    fi
    rmdir "$mountpoint"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$dmg"
attached=true

app="$mountpoint/QuickTextProcessor.app"
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/QuickTextProcessor"
[[ -d "$app" && -L "$mountpoint/Applications" ]]
[[ "$(readlink "$mountpoint/Applications")" == /Applications ]]
[[ "$(lipo -archs "$binary")" == arm64 ]]
# SwiftPM's macOS deployment target must remain 14.0, even on newer hosts.
[[ "$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')" =~ ^14\.0(\.0)?$ ]]
for key in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")" == "$version" ]]
done
codesign --verify --deep --strict "$app"
codesign -dv "$app" 2>&1 | grep -x 'Signature=adhoc' >/dev/null
[[ -s "$app/Contents/Resources/AppIcon.icns" ]]
resources="$app/Contents/Resources/QuickTextProcessor_QuickTextProcessor.bundle"
[[ -d "$resources" ]]
for resource in oauth_success.html codex_instructions.md; do
    # SwiftPM bundles can use either a flat or a macOS Contents/Resources layout.
    [[ -s "$resources/$resource" || -s "$resources/Contents/Resources/$resource" ]]
done
echo "Verified arm64 DMG for QuickTextProcessor $version"
