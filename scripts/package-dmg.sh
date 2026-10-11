#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
app=${1:?Usage: package-dmg.sh APP_BUNDLE VERSION}
version=${2:?Usage: package-dmg.sh APP_BUNDLE VERSION}
bash "$script_dir/validate-version.sh" "$version"
[[ -d "$app" ]] || { echo "error: app bundle missing: $app" >&2; exit 1; }

staging=$(mktemp -d "${TMPDIR:-/tmp}/quick-text-processor-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/QuickTextProcessor.app"
ln -s /Applications "$staging/Applications"
mkdir -p build
hdiutil create -ov -format UDZO -volname "QuickTextProcessor $version" \
    -srcfolder "$staging" "build/QuickTextProcessor-$version-arm64.dmg"
