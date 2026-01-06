#!/bin/bash

# Launch Tom Lander with LÖVE2D
# LÖVE2D is located in the Applications folder

GAME_DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE_APP="/Applications/love.app/Contents/MacOS/love"

if [ ! -f "$LOVE_APP" ]; then
    echo "Error: LÖVE2D not found at $LOVE_APP"
    echo "Please make sure LÖVE2D is installed in /Applications"
    exit 1
fi

"$LOVE_APP" "$GAME_DIR"
