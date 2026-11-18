#!/usr/bin/env bash
# Toggle layout between BSP and Float, handling window unfloating/refloating and saving positions

STATE_DIR="/tmp/yabai-layout-state"
mkdir -p "$STATE_DIR"

SPACE_ID=$(yabai -m query --spaces --space | jq -r '.id')
CUR_TYPE=$(yabai -m query --spaces --space | jq -r '.type')
STATE_FILE="$STATE_DIR/space-${SPACE_ID}-frames.json"

if [ "$CUR_TYPE" = "bsp" ]; then
    # Switching from BSP -> Float
    yabai -m space --layout float
    
    # Re-float all standard managed windows on current space
    yabai -m query --windows --space | jq -r '.[] | select(.["is-visible"] == true and .["is-minimized"] == false and .role == "AXWindow" and .subrole == "AXStandardWindow" and .["is-floating"] == false) | .id' | while read -r wid; do
        [ -n "$wid" ] && yabai -m window "$wid" --toggle float 2>/dev/null
    done
    
    # Restore previous float frames if available
    if [ -f "$STATE_FILE" ]; then
        jq -c '.[]' "$STATE_FILE" | while read -r win; do
            id=$(echo "$win" | jq -r '.id')
            x=$(echo "$win" | jq -r '.x')
            y=$(echo "$win" | jq -r '.y')
            w=$(echo "$win" | jq -r '.w')
            h=$(echo "$win" | jq -r '.h')
            # Check if window still exists on this space
            if yabai -m query --windows --window "$id" >/dev/null 2>&1; then
                yabai -m window "$id" --move abs:"$x":"$y" 2>/dev/null
                yabai -m window "$id" --resize abs:"$w":"$h" 2>/dev/null
            fi
        done
        rm -f "$STATE_FILE"
    fi
else
    # Switching from Float -> BSP
    # Save positions of all visible floating standard windows on this space
    yabai -m query --windows --space | jq '[.[] | select(.["is-visible"] == true and .["is-minimized"] == false and .role == "AXWindow" and .subrole == "AXStandardWindow") | {id: .id, x: (.frame.x | floor), y: (.frame.y | floor), w: (.frame.w | floor), h: (.frame.h | floor)}]' > "$STATE_FILE"
    
    # Unfloat all floating windows on this space so yabai can tile them in BSP
    yabai -m query --windows --space | jq -r '.[] | select(.["is-visible"] == true and .["is-minimized"] == false and .["is-floating"] == true and .role == "AXWindow" and .subrole == "AXStandardWindow") | .id' | while read -r wid; do
        [ -n "$wid" ] && yabai -m window "$wid" --toggle float 2>/dev/null
    done
    
    yabai -m space --layout bsp
fi

# Trigger sketchybar status update
if command -v sketchybar >/dev/null 2>&1; then
    sketchybar --trigger yabai_mode_update 2>/dev/null
fi
