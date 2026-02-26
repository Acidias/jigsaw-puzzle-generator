#!/bin/bash
set -euo pipefail

APP_NAME="JigsawPuzzleGenerator"
BUILD_DIR=".build/debug"
APP_BUNDLE="${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swift build

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "Sources/Resources/Info.plist" "${APP_BUNDLE}/Contents/"

echo "Launching ${APP_NAME}..."
# Kill any running instance so 'open' launches the new binary
pkill -x "${APP_NAME}" 2>/dev/null && sleep 0.5
open "${APP_BUNDLE}"
