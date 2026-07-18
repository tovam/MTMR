#!/bin/sh

set -eu

SCHEME="MMTMR"
APP_NAME="MMTMR"
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOCAL_BUILD_DIR="$PROJECT_ROOT/build-checks/xcode"
RELEASE_DIR="$PROJECT_ROOT/Release"

if [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ]; then
    echo "MMTMR requires a complete Xcode installation (not only Command Line Tools)." >&2
    exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$LOCAL_BUILD_DIR"

xcodebuild archive \
    -project "$PROJECT_ROOT/MTMR.xcodeproj" \
    -scheme "$SCHEME" \
    -derivedDataPath "$LOCAL_BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$LOCAL_BUILD_DIR/SourcePackages" \
    -archivePath "$RELEASE_DIR/App.xcarchive"

xcodebuild \
    -exportArchive \
    -archivePath "$RELEASE_DIR/App.xcarchive" \
    -exportOptionsPlist "$PROJECT_ROOT/export-options.plist" \
    -exportPath "$RELEASE_DIR"

echo "Built $RELEASE_DIR/$APP_NAME.app"
