#!/usr/bin/env bash

# In BSP mode: cycle window order through BSP tree slots
cur_space_type=$(yabai -m query --spaces --space | jq -r '.type // "float"')

if [ "$cur_space_type" = "bsp" ]; then
  # Swap with next window in tree; if at end, swap with first
  yabai -m window --swap next 2>/dev/null || yabai -m window --swap first 2>/dev/null
  exit 0
fi

# Query window and current display frame
win=$(yabai -m query --windows --window)
cur_win_id=$(echo "$win" | jq -r '.id')
cur_disp=$(echo "$win" | jq -r '.display')

# Per-window state tracking so different windows/monitors cycle independently
STATE_FILE="/tmp/yabai-quarter-state-${cur_win_id}"
TOP_ADJUST=30       # reduces height of top windows
BOTTOM_ADJUST=20    # pushes bottom windows down

# read current state for this window
if [ -f "$STATE_FILE" ]; then
  state=$(cat "$STATE_FILE")
else
  state=0
fi

# Query exact display frame for the screen containing this window
d=$(yabai -m query --displays --display "$cur_disp" 2>/dev/null | jq '.frame' 2>/dev/null)
if [ -z "$d" ] || [ "$d" = "null" ]; then
  d=$(yabai -m query --displays --display | jq '.frame')
fi

dx=$(echo "$d" | jq '.x | floor')
dy=$(echo "$d" | jq '.y | floor')
dw=$(echo "$d" | jq '.w | floor')
dh=$(echo "$d" | jq '.h | floor')

# External bar clearance offset (sketchybar height 28 + padding)
TOP_OFFSET=36
USABLE_Y=$((dy + TOP_OFFSET))
USABLE_H=$((dh - TOP_OFFSET))

hw=$((dw / 2))
hh=$((USABLE_H / 2))

hh_top=$((hh - TOP_ADJUST))
hh_bottom=$((hh - BOTTOM_ADJUST))

# Ensure window is floating
is_floating=$(echo "$win" | jq -r '.["is-floating"]')
if [ "$is_floating" = "false" ]; then
  yabai -m window --toggle float 2>/dev/null
fi

# Always move first, then resize, so screen boundaries never constrain resizing
apply_pos() {
  target_x=$1
  target_y=$2
  target_w=$3
  target_h=$4
  yabai -m window --move abs:$target_x:$target_y 2>/dev/null
  yabai -m window --resize abs:$target_w:$target_h 2>/dev/null
}

case "$state" in
  0)
    # top-left
    apply_pos "$dx" "$USABLE_Y" "$hw" "$hh_top"
    next=1
    ;;
  1)
    # top-right
    apply_pos "$((dx + hw))" "$USABLE_Y" "$hw" "$hh_top"
    next=2
    ;;
  2)
    # bottom-right
    apply_pos "$((dx + hw))" "$((USABLE_Y + hh + BOTTOM_ADJUST))" "$hw" "$hh_bottom"
    next=3
    ;;
  3)
    # bottom-left
    apply_pos "$dx" "$((USABLE_Y + hh + BOTTOM_ADJUST))" "$hw" "$hh_bottom"
    next=0
    ;;
esac

echo "$next" > "$STATE_FILE"

