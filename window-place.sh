#!/usr/bin/env sh
# Place window into floating fraction/slot
# Usage: window-place.sh <left-half|right-half|top-half|bottom-half|first-third|center-third|last-third|first-two-thirds|last-two-thirds|center|maximize|maximize-height>

ACTION="$1"

# Check if current space is BSP mode
cur_space_type=$(yabai -m query --spaces --space | jq -r '.type // "float"')

if [ "$cur_space_type" = "bsp" ]; then
  # In BSP mode: warp/swap window in the specified direction and re-balance layout
  python3 - "$ACTION" << 'PYEOF'
import sys, json, subprocess

action = sys.argv[1] if len(sys.argv) > 1 else ""

try:
    cur_win = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows", "--window"]))
    space_wins = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"]))
except Exception:
    sys.exit(0)

managed = [w for w in space_wins if w.get("is-visible") and not w.get("is-minimized") and not w.get("is-hidden") and w.get("role") == "AXWindow" and not w.get("is-floating")]
cur_id = cur_win.get("id")

if not managed or cur_id not in [w["id"] for w in managed]:
    sys.exit(0)

if action == "maximize":
    subprocess.run(["yabai", "-m", "window", "--toggle", "zoom-fullscreen"], capture_output=True)
    sys.exit(0)

cur_f = cur_win["frame"]
cur_cx = cur_f["x"] + cur_f["w"] / 2.0
cur_cy = cur_f["y"] + cur_f["h"] / 2.0

candidates = [w for w in managed if w["id"] != cur_id]
if not candidates:
    sys.exit(0)

target = None
if action in ["left-half", "first-third", "first-two-thirds"]:
    left_wins = [w for w in candidates if (w["frame"]["x"] + w["frame"]["w"] / 2.0) < cur_cx - 20]
    target = min(left_wins, key=lambda w: (w["frame"]["x"] + w["frame"]["w"] / 2.0)) if left_wins else min(candidates, key=lambda w: (w["frame"]["x"] + w["frame"]["w"] / 2.0))
elif action in ["right-half", "last-third", "last-two-thirds", "two-thirds", "cycle-two-thirds"]:
    right_wins = [w for w in candidates if (w["frame"]["x"] + w["frame"]["w"] / 2.0) > cur_cx + 20]
    target = max(right_wins, key=lambda w: (w["frame"]["x"] + w["frame"]["w"] / 2.0)) if right_wins else max(candidates, key=lambda w: (w["frame"]["x"] + w["frame"]["w"] / 2.0))
elif action in ["top-half"]:
    top_wins = [w for w in candidates if (w["frame"]["y"] + w["frame"]["h"] / 2.0) < cur_cy - 20]
    target = min(top_wins, key=lambda w: (w["frame"]["y"] + w["frame"]["h"] / 2.0)) if top_wins else min(candidates, key=lambda w: (w["frame"]["y"] + w["frame"]["h"] / 2.0))
elif action in ["bottom-half"]:
    bottom_wins = [w for w in candidates if (w["frame"]["y"] + w["frame"]["h"] / 2.0) > cur_cy + 20]
    target = max(bottom_wins, key=lambda w: (w["frame"]["y"] + w["frame"]["h"] / 2.0)) if bottom_wins else max(candidates, key=lambda w: (w["frame"]["y"] + w["frame"]["h"] / 2.0))

if target and target["id"] != cur_id:
    # Warp focused window into the target direction slot
    res = subprocess.run(["yabai", "-m", "window", str(cur_id), "--warp", str(target["id"])], capture_output=True)
    if res.returncode != 0:
        subprocess.run(["yabai", "-m", "window", str(cur_id), "--swap", str(target["id"])], capture_output=True)
    # Balance remaining windows in BSP tree
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)
PYEOF
  exit 0
fi

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
