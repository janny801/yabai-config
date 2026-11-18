#!/usr/bin/env bash

# In BSP mode: cycle window order through BSP tree slots
cur_space_type=$(yabai -m query --spaces --space | jq -r '.type // "float"')

if [ "$cur_space_type" = "bsp" ]; then
  # Swap with next window in tree; if at end, swap with first
  yabai -m window --swap next 2>/dev/null || yabai -m window --swap first 2>/dev/null
  exit 0
fi

STATE_FILE="/tmp/yabai-quarter-state"
TOP_ADJUST=30       # reduces height of top windows
BOTTOM_ADJUST=20    # pushes bottom windows down

# read current state
if [ -f "$STATE_FILE" ]; then
  state=$(cat "$STATE_FILE")
else
  state=0
fi

# display frame (ints)
d=$(yabai -m query --displays --display | jq '.frame')
dx=$(echo "$d" | jq '.x | floor')
dy=$(echo "$d" | jq '.y | floor')
dw=$(echo "$d" | jq '.w | floor')
dh=$(echo "$d" | jq '.h | floor')

hw=$((dw / 2))
hh=$((dh / 2))

hh_top=$((hh - TOP_ADJUST))
hh_bottom=$((hh - BOTTOM_ADJUST))

case "$state" in
  0)
    # top-left
    yabai -m window --resize abs:$hw:$hh_top
    yabai -m window --move abs:$dx:$dy
    next=1
    ;;
  1)
    # top-right
    yabai -m window --resize abs:$hw:$hh_top
    yabai -m window --move abs:$((dx + hw)):$dy
    next=2
    ;;
  2)
    # bottom-right
    yabai -m window --resize abs:$hw:$hh_bottom
    yabai -m window --move abs:$((dx + hw)):$((dy + hh + BOTTOM_ADJUST))
    next=3
    ;;
  3)
    # bottom-left
    yabai -m window --resize abs:$hw:$hh_bottom
    yabai -m window --move abs:$dx:$((dy + hh + BOTTOM_ADJUST))
    next=0
    ;;
esac

echo "$next" > "$STATE_FILE"

