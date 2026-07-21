#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_app=${1:-}
signing_identity=${2:-}
installed_app=/Applications/MMTMR.app

if [ -z "$source_app" ] || [ -z "$signing_identity" ]; then
    echo "Usage: $0 /path/to/MMTMR.app \"Stable code-signing identity\"" >&2
    echo "Available identities:" >&2
    security find-identity -v -p codesigning >&2
    exit 64
fi

if [ "$signing_identity" = "-" ]; then
    echo "Ad-hoc signing is not stable and would reset Accessibility access." >&2
    exit 64
fi

source_directory=$(CDPATH= cd -- "$(dirname -- "$source_app")" && pwd)
source_app="$source_directory/$(basename -- "$source_app")"

if [ ! -x "$source_app/Contents/MacOS/MMTMR" ]; then
    echo "MMTMR application not found at: $source_app" >&2
    exit 66
fi

bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
if [ "$bundle_identifier" != "com.tovam.MMTMR" ]; then
    echo "Unexpected bundle identifier: $bundle_identifier" >&2
    exit 65
fi

if ! security find-identity -v -p codesigning | grep -F "\"$signing_identity\"" >/dev/null; then
    echo "Code-signing identity not found: $signing_identity" >&2
    exit 69
fi

mkdir -p "$project_root/build-checks/local-installs"
install_directory=$(mktemp -d "$project_root/build-checks/local-installs/install.XXXXXX")
signed_app="$install_directory/MMTMR.app"
previous_app="$install_directory/previous-MMTMR.app"
failed_app="$install_directory/failed-MMTMR.app"

ditto "$source_app" "$signed_app"

# Nested frameworks already carry valid archive signatures. Signing only the
# outer application avoids one private-key operation (and prompt) per framework.
codesign --force --timestamp=none --sign "$signing_identity" "$signed_app"
codesign --verify --deep --strict --verbose=2 "$signed_app"

designated_requirement=$(codesign -d -r- "$signed_app" 2>&1 | sed -n 's/^designated => //p')
if [ -z "$designated_requirement" ]; then
    echo "Could not read the signed application's designated requirement." >&2
    exit 70
fi

case "$designated_requirement" in
    *cdhash*)
        echo "Refusing to install a build whose identity changes with every binary hash." >&2
        echo "Designated requirement: $designated_requirement" >&2
        exit 70
        ;;
esac

/usr/bin/killall -TERM MMTMR 2>/dev/null || true
/bin/sleep 1

had_previous=false
if [ -d "$installed_app" ]; then
    /bin/mv "$installed_app" "$previous_app"
    had_previous=true
fi

if ! ditto "$signed_app" "$installed_app"; then
    /bin/mv "$installed_app" "$failed_app" 2>/dev/null || true
    if [ "$had_previous" = true ]; then
        /bin/mv "$previous_app" "$installed_app"
    fi
    exit 1
fi

if ! codesign --verify --deep --strict "$installed_app"; then
    /bin/mv "$installed_app" "$failed_app"
    if [ "$had_previous" = true ]; then
        /bin/mv "$previous_app" "$installed_app"
    fi
    exit 1
fi

installed_requirement=$(codesign -d -r- "$installed_app" 2>&1 | sed -n 's/^designated => //p')
if [ "$installed_requirement" != "$designated_requirement" ]; then
    /bin/mv "$installed_app" "$failed_app"
    if [ "$had_previous" = true ]; then
        /bin/mv "$previous_app" "$installed_app"
    fi
    echo "The installed signature does not match the verified source signature." >&2
    exit 70
fi

/usr/bin/open "$installed_app"

echo "Installed: $installed_app"
echo "Signing identity: $signing_identity"
echo "Stable requirement: $installed_requirement"
if [ "$had_previous" = true ]; then
    echo "Previous application: $previous_app"
fi
