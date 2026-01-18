#!/bin/bash

# Build script for Tom Lander (LÖVE2D game)
# Creates distributable packages for macOS

set -e  # Exit on error

# Configuration
GAME_NAME="TomLander"
VERSION="1.0.0"
LOVE_APP="/Applications/love.app"
BUILD_DIR="build"
DIST_DIR="dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Tom Lander Build Script for macOS${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if LÖVE is installed
if [ ! -d "$LOVE_APP" ]; then
    echo -e "${RED}Error: LÖVE not found at $LOVE_APP${NC}"
    echo "Please install LÖVE from https://love2d.org/"
    exit 1
fi

# Create build directories
echo -e "${YELLOW}Creating build directories...${NC}"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# Create .love file (zip of game files)
echo -e "${YELLOW}Creating .love package...${NC}"
LOVE_FILE="$BUILD_DIR/$GAME_NAME.love"

# Files and directories to include
zip -9 -r "$LOVE_FILE" \
    main.lua \
    conf.lua \
    src/ \
    assets/ \
    -x "*.DS_Store" \
    -x "*/.git/*" \
    -x "*.gitignore"

echo -e "${GREEN}Created: $LOVE_FILE${NC}"

# Get .love file size
LOVE_SIZE=$(du -h "$LOVE_FILE" | cut -f1)
echo "  Size: $LOVE_SIZE"

# Create standalone macOS .app bundle
echo ""
echo -e "${YELLOW}Creating macOS application bundle...${NC}"

APP_NAME="$GAME_NAME.app"
APP_PATH="$DIST_DIR/$APP_NAME"

# Copy LÖVE.app as base
cp -R "$LOVE_APP" "$APP_PATH"

# Copy .love file into the app bundle
cp "$LOVE_FILE" "$APP_PATH/Contents/Resources/"

# Update Info.plist
PLIST="$APP_PATH/Contents/Info.plist"

# Use PlistBuddy to modify the plist (macOS built-in tool)
/usr/libexec/PlistBuddy -c "Set :CFBundleName '$GAME_NAME'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$GAME_NAME'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier 'com.tomlander.game'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion '$VERSION'" "$PLIST" 2>/dev/null || true

# Remove LÖVE's URL handler (so our app doesn't try to handle .love files)
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" "$PLIST" 2>/dev/null || true

echo -e "${GREEN}Created: $APP_PATH${NC}"

# Get app size
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo "  Size: $APP_SIZE"

# Create a DMG (optional, requires create-dmg or hdiutil)
echo ""
echo -e "${YELLOW}Creating DMG installer...${NC}"

DMG_NAME="$GAME_NAME-$VERSION-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# Simple DMG creation using hdiutil (built-in macOS tool)
DMG_TEMP="$BUILD_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create a symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$GAME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

echo -e "${GREEN}Created: $DMG_PATH${NC}"
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "  Size: $DMG_SIZE"

# Create a zip of the .app for easy distribution
echo ""
echo -e "${YELLOW}Creating ZIP archive...${NC}"

ZIP_NAME="$GAME_NAME-$VERSION-macOS.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

cd "$DIST_DIR"
zip -9 -r "$ZIP_NAME" "$APP_NAME" -x "*.DS_Store"
cd - > /dev/null

echo -e "${GREEN}Created: $ZIP_PATH${NC}"
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo "  Size: $ZIP_SIZE"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Output files:"
echo "  $BUILD_DIR/$GAME_NAME.love  ($LOVE_SIZE)"
echo "  $DIST_DIR/$APP_NAME         ($APP_SIZE)"
echo "  $DIST_DIR/$DMG_NAME         ($DMG_SIZE)"
echo "  $DIST_DIR/$ZIP_NAME         ($ZIP_SIZE)"
echo ""
echo -e "${YELLOW}To test the build:${NC}"
echo "  open $APP_PATH"
echo ""
echo -e "${YELLOW}To distribute:${NC}"
echo "  - Share the DMG for easy install (drag to Applications)"
echo "  - Share the ZIP for manual install"
echo "  - Share the .love file (requires LÖVE installed)"
echo ""

# Note about code signing
echo -e "${YELLOW}Note:${NC} The app is not code-signed. Users may need to:"
echo "  1. Right-click the app and select 'Open'"
echo "  2. Or: System Preferences > Security > 'Open Anyway'"
echo ""
echo "For distribution on the App Store or notarization,"
echo "you'll need an Apple Developer account and code signing."
