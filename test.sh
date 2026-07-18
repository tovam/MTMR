#!/bin/sh

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOCAL_BUILD_DIR="$PROJECT_ROOT/build-checks/xcode-tests"

if [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ]; then
    echo "MMTMR tests require a complete Xcode installation (not only Command Line Tools)." >&2
    exit 1
fi

mkdir -p "$LOCAL_BUILD_DIR"

xcodebuild test \
    -project "$PROJECT_ROOT/MTMR.xcodeproj" \
    -scheme MMTMR \
    -configuration Debug \
    -derivedDataPath "$LOCAL_BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$LOCAL_BUILD_DIR/SourcePackages"
