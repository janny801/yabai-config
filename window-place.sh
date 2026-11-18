#!/usr/bin/env sh
# Place window into floating fraction/slot
# Usage: window-place.sh <left-half|right-half|top-half|bottom-half|first-third|center-third|last-third|first-two-thirds|last-two-thirds|center|maximize|maximize-height>

ACTION="$1"

# Check if current space is BSP mode
cur_space_type=$(yabai -m query --spaces --space | jq -r '.type // "float"')

if [ "$cur_space_type" = "bsp" ]; then
  # In BSP mode: place active window to occupy the desired half/side and balance the rest
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

other_ids = [w["id"] for w in managed if w["id"] != cur_id]
if not other_ids:
    sys.exit(0)

target_dir = None
if action in ["left-half", "first-third", "first-two-thirds"]:
    target_dir = "left"
elif action in ["right-half", "last-third", "last-two-thirds", "two-thirds", "cycle-two-thirds"]:
    target_dir = "right"
elif action in ["top-half"]:
    target_dir = "top"
elif action in ["bottom-half"]:
    target_dir = "bottom"
elif action == "center":
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)
    sys.exit(0)

if not target_dir:
    sys.exit(0)

# 1. Cluster all other windows together into other_ids[0]
lead_other = other_ids[0]
for oid in other_ids[1:]:
    subprocess.run(["yabai", "-m", "window", str(oid), "--warp", str(lead_other)], capture_output=True)
subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)

# 2. Find who is solitary (occupying an entire half)
s2 = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"]))
managed_s2 = [w for w in s2 if w["id"] in [m["id"] for m in managed]]
solitary = max(managed_s2, key=lambda w: w["frame"]["w"] * w["frame"]["h"])
if solitary["id"] != cur_id:
    subprocess.run(["yabai", "-m", "window", str(cur_id), "--swap", str(solitary["id"])], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)

# 3. Orient root split axis
s3 = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"]))
c3 = next(w for w in s3 if w["id"] == cur_id)
o3 = [w for w in s3 if w["id"] in other_ids]

cur_cx = c3["frame"]["x"] + c3["frame"]["w"] / 2.0
cur_cy = c3["frame"]["y"] + c3["frame"]["h"] / 2.0
other_cx = sum(w["frame"]["x"] + w["frame"]["w"] / 2.0 for w in o3) / len(o3)
other_cy = sum(w["frame"]["y"] + w["frame"]["h"] / 2.0 for w in o3) / len(o3)

dx = abs(cur_cx - other_cx)
dy = abs(cur_cy - other_cy)

if target_dir in ["left", "right"] and dx < dy:
    subprocess.run(["yabai", "-m", "space", "--rotate", "90"], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)
elif target_dir in ["top", "bottom"] and dy < dx:
    subprocess.run(["yabai", "-m", "space", "--rotate", "90"], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)

# 4. Check if cur_id is on target side
s4 = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"]))
c4 = next(w for w in s4 if w["id"] == cur_id)
o4 = [w for w in s4 if w["id"] in other_ids]
cur_cx = c4["frame"]["x"] + c4["frame"]["w"] / 2.0
cur_cy = c4["frame"]["y"] + c4["frame"]["h"] / 2.0
other_cx = sum(w["frame"]["x"] + w["frame"]["w"] / 2.0 for w in o4) / len(o4)
other_cy = sum(w["frame"]["y"] + w["frame"]["h"] / 2.0 for w in o4) / len(o4)

is_on_target = (
    (target_dir == "left" and cur_cx < other_cx) or
    (target_dir == "right" and cur_cx > other_cx) or
    (target_dir == "top" and cur_cy < other_cy) or
    (target_dir == "bottom" and cur_cy > other_cy)
)

if not is_on_target:
    cluster_lead = o4[0]["id"]
    subprocess.run(["yabai", "-m", "window", str(cur_id), "--swap", str(cluster_lead)], capture_output=True)
    for w in o4[1:]:
        subprocess.run(["yabai", "-m", "window", str(w["id"]), "--warp", str(cluster_lead)], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)

# 5. Keep focus on cur_id
subprocess.run(["yabai", "-m", "window", "--focus", str(cur_id)], capture_output=True)
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
