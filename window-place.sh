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

# Helper: always move first, then resize, so screen edges never constrain resize
apply_geometry() {
  target_x=$1
  target_y=$2
  target_w=$3
  target_h=$4
  yabai -m window --move abs:$target_x:$target_y
  yabai -m window --resize abs:$target_w:$target_h
}

case "$ACTION" in
  "left-half")
    w=$(( (dw - GAP * 3) / 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "right-half")
    w=$(( (dw - GAP * 3) / 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + w ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "top-half")
    w=$(( dw - GAP * 2 ))
    h=$(( (USABLE_H - GAP * 2) / 2 ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "bottom-half")
    w=$(( dw - GAP * 2 ))
    h=$(( (USABLE_H - GAP * 2) / 2 ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y + h + GAP ))
    apply_geometry $x $y $w $h
    ;;
  "first-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "center-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + w ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "last-third")
    w=$(( (dw - GAP * 4) / 3 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 3 + w * 2 ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "two-thirds"|"first-two-thirds"|"cycle-two-thirds")
    unit=$(( (dw - GAP * 4) / 3 ))
    w=$(( unit * 2 + GAP ))
    h=$(( USABLE_H - GAP ))
    x_left=$(( dx + GAP ))
    x_right=$(( dx + GAP * 2 + unit ))
    
    # Check if currently near left two-thirds or right two-thirds
    diff_left=$(abs $(( cur_x - x_left )))
    diff_w=$(abs $(( cur_w - w )))
    
    if [ "$diff_w" -le 30 ] && [ "$diff_left" -le 30 ]; then
      # Currently left 2/3 -> cycle to right 2/3
      x=$x_right
    else
      # Otherwise go to left 2/3
      x=$x_left
    fi
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "last-two-thirds")
    unit=$(( (dw - GAP * 4) / 3 ))
    w=$(( unit * 2 + GAP ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP * 2 + unit ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "maximize")
    w=$(( dw - GAP * 2 ))
    h=$(( USABLE_H - GAP ))
    x=$(( dx + GAP ))
    y=$(( USABLE_Y ))
    apply_geometry $x $y $w $h
    ;;
  "center")
    w=$(echo "$win" | jq '.frame.w | floor')
    h=$(echo "$win" | jq '.frame.h | floor')
    x=$(( dx + (dw - w) / 2 ))
    y=$(( USABLE_Y + (USABLE_H - h) / 2 ))
    apply_geometry $x $y $w $h
    ;;
  "maximize-height")
    w=$(echo "$win" | jq '.frame.w | floor')
    h=$(( USABLE_H - GAP ))
    apply_geometry $cur_x $USABLE_Y $w $h
    ;;
esac
