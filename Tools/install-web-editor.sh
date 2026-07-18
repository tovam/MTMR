#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$project_root/MMTMR.app"}
signing_identity=${2:-}

# Keep the destination stable after the script changes into Web below.
app_directory=$(CDPATH= cd -- "$(dirname -- "$app_path")" && pwd)
app_path="$app_directory/$(basename -- "$app_path")"
editor_destination="$app_path/Contents/Resources/Editor"

if [ ! -x "$app_path/Contents/MacOS/MMTMR" ]; then
    echo "MMTMR application not found at: $app_path" >&2
    exit 1
fi

mkdir -p "$project_root/build-checks/npm-cache"
cd "$project_root/Web"
npm ci --cache "$project_root/build-checks/npm-cache" --prefer-offline --no-audit
npm run check

mkdir -p "$editor_destination"
ditto "$project_root/Web/dist" "$editor_destination"

if [ -n "$signing_identity" ]; then
    codesign --force --deep --sign "$signing_identity" "$app_path"
    codesign --verify --deep --strict --verbose=2 "$app_path"
    echo "Editor installed and application signed: $app_path"
else
    echo "Editor installed: $editor_destination"
    echo "A running MMTMR serves these files immediately after a browser refresh."
    echo "Before relaunching the modified app, sign it by passing a code-signing identity as the second argument."
fi
