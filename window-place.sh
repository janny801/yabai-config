#!/usr/bin/env sh
# Place window into floating fraction/slot
# Usage: window-place.sh <left-half|right-half|top-half|bottom-half|first-third|center-third|last-third|first-two-thirds|last-two-thirds|center|maximize|maximize-height>

ACTION="$1"

# Query current window frame BEFORE changing anything
win=$(yabai -m query --windows --window)
is_floating=$(echo "$win" | jq '.["is-floating"]')
cur_x=$(echo "$win" | jq '.frame.x | floor')
cur_w=$(echo "$win" | jq '.frame.w | floor')

# Ensure window is floating without moving it
if [ "$is_floating" = "false" ]; then
  yabai -m window --toggle float 2>/dev/null
fi

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

abs() {
  v=$1
  if [ "$v" -lt 0 ]; then
    echo $(( -v ))
  else
    echo "$v"
  fi
}

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
  "two-thirds"|"first-two-thirds"|"cycle-two-thirds")
    unit=$(( (dw - GAP * 4) / 3 ))
    w=$(( unit * 2 + GAP ))
    h=$(( USABLE_H - GAP ))
    x_left=$(( dx + GAP ))
    x_right=$(( dx + GAP * 2 + unit ))
    
    # Check if currently near left two-thirds or right two-thirds
    diff_left=$(abs $(( cur_x - x_left )))
    diff_right=$(abs $(( cur_x - x_right )))
    diff_w=$(abs $(( cur_w - w )))
    
    if [ "$diff_w" -le 30 ] && [ "$diff_left" -le 30 ]; then
      # Currently left 2/3 -> cycle to right 2/3
      x=$x_right
    else
      # Otherwise go to left 2/3
      x=$x_left
    fi
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
  "maximize")
    w=$(( dw - GAP * 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$x:$y
    ;;
  "center")
    w=$(echo "$win" | jq '.frame.w | floor')
    h=$(echo "$win" | jq '.frame.h | floor')
    x=$(( dx + (dw - w) / 2 ))
    y=$(( USABLE_Y + (USABLE_H - h) / 2 ))
    yabai -m window --move abs:$x:$y
    ;;
  "maximize-height")
    w=$(echo "$win" | jq '.frame.w | floor')
    h=$(( USABLE_H - GAP ))
    yabai -m window --resize abs:$w:$h
    yabai -m window --move abs:$cur_x:$USABLE_Y
    ;;
esac
