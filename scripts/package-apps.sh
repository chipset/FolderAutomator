#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.xcode-derived"
OUTPUT_DIR="$ROOT_DIR/dist"

mkdir -p "$OUTPUT_DIR"

xcodebuild -project "$ROOT_DIR/FolderAutomator.xcodeproj" -scheme FolderAutomatorApp -configuration Release -derivedDataPath "$DERIVED_DATA_PATH" build
xcodebuild -project "$ROOT_DIR/FolderAutomator.xcodeproj" -scheme FolderAutomatorSettingsApp -configuration Release -derivedDataPath "$DERIVED_DATA_PATH" build

rm -rf "$OUTPUT_DIR/FolderAutomatorApp.app" "$OUTPUT_DIR/FolderAutomatorSettingsApp.app"
cp -R "$DERIVED_DATA_PATH/Build/Products/Release/FolderAutomatorApp.app" "$OUTPUT_DIR/FolderAutomatorApp.app"
cp -R "$DERIVED_DATA_PATH/Build/Products/Release/FolderAutomatorSettingsApp.app" "$OUTPUT_DIR/FolderAutomatorSettingsApp.app"

ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/FolderAutomatorApp.app" "$OUTPUT_DIR/FolderAutomatorApp.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/FolderAutomatorSettingsApp.app" "$OUTPUT_DIR/FolderAutomatorSettingsApp.zip"

echo "Packaged apps in $OUTPUT_DIR"
