#!/usr/bin/env sh
# Place window into floating fraction/slot
# Usage: window-place.sh <left-half|right-half|top-half|bottom-half|first-third|center-third|last-third|first-two-thirds|center|maximize-height>

ACTION="$1"

# Ensure window is floating
yabai -m window --grid 1:1:0:0:1:1 2>/dev/null

d=$(yabai -m query --displays --display | jq '.frame')
dx=$(echo "$d" | jq '.x | floor')
dy=$(echo "$d" | jq '.y | floor')
dw=$(echo "$d" | jq '.w | floor')
dh=$(echo "$d" | jq '.h | floor')

# Offsets for sketchybar / padding
TOP_OFFSET=36
GAP=10
USABLE_H=$((dh - TOP_OFFSET - GAP))
USABLE_Y=$((dy + TOP_OFFSET))

case "$ACTION" in
  "left-half")
    w=$(( (dw - GAP * 3) / 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "right-half")
    w=$(( (dw - GAP * 3) / 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + w ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "top-half")
    w=$(( dw - GAP * 2 ))
    h=$(( (USABLE_H - GAP * 2) / 2 ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "bottom-half")
    w=$(( dw - GAP * 2 ))
    h=$(( (USABLE_H - GAP * 2) / 2 ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y + h + GAP ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "first-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "center-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + w ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "last-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 3 + w * 2 ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "first-two-thirds")
    unit=$(( (dw - GAP * 4) / 3 ))
    w=$(( unit * 2 + GAP ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "last-two-thirds")
    unit=$(( (dw - GAP * 4) / 3 ))
    w=$(( unit * 2 + GAP ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + unit ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "center")
    w=$(yabai -m query --windows --window | jq '.frame.w | floor')
    h=$(yabai -m query --windows --window | jq '.frame.h | floor')
    x=$(( dx + (dw - w) / 2 ))
    y=$(( USABLE_Y + (USABLE_H - h) / 2 ))
    yabai -m window --move abs:$x:$y
    ;;
  "maximize-height")
    w=$(yabai -m query --windows --window | jq '.frame.w | floor')
    h=$(( USABLE_H - GAP ))
    cur_x=$(yabai -m query --windows --window | jq '.frame.x | floor')
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$cur_x:$USABLE_Y
    ;;
esac
