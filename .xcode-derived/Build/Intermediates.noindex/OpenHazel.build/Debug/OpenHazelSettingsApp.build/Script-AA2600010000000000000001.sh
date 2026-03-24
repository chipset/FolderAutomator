#!/bin/sh
mkdir -p "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LoginItems"
rm -rf "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LoginItems/OpenHazelLoginHelper.app"
cp -R "$BUILT_PRODUCTS_DIR/OpenHazelLoginHelper.app" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LoginItems/"

