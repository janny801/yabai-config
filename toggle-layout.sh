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
    yabai -m query --windows --space | jq -r '.[] | select(.["is-visible"] == true and .["is-minimized"] == false and .role == "AXWindow" and .["is-floating"] == false) | .id' | while read -r wid; do
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
    yabai -m query --windows --space | jq '[.[] | select(.["is-visible"] == true and .["is-minimized"] == false and .role == "AXWindow") | {id: .id, x: (.frame.x | floor), y: (.frame.y | floor), w: (.frame.w | floor), h: (.frame.h | floor)}]' > "$STATE_FILE"
    
    # Record original window center positions before tiling
    python3 - << 'PYEOF'
import json, subprocess

raw_wins = subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"])
wins = [w for w in json.loads(raw_wins) if w.get("is-visible") and not w.get("is-minimized") and w.get("role") == "AXWindow"]

# Save id to original center (cx, cy)
orig_centers = {}
for w in wins:
    f = w["frame"]
    orig_centers[w["id"]] = (f["x"] + f["w"] / 2.0, f["y"] + f["h"] / 2.0)

with open("/tmp/yabai-orig-centers.json", "w") as f:
    json.dump(orig_centers, f)
PYEOF

    # Switch layout to BSP
    yabai -m space --layout bsp

    # Unfloat all managed windows and balance space
    yabai -m query --windows --space | jq -r '.[] | select(.["is-minimized"] == false and .["is-floating"] == true and .role == "AXWindow") | .id' | while read -r wid; do
        [ -n "$wid" ] && yabai -m window "$wid" --toggle float 2>/dev/null
    done
    yabai -m space --balance 2>/dev/null

    # Re-order/swap BSP slots so each window stays in the slot closest to its original position
    python3 - << 'PYEOF'
import json, subprocess, math

try:
    with open("/tmp/yabai-orig-centers.json", "r") as f:
        orig_centers = {int(k): tuple(v) for k, v in json.load(f).items()}
except Exception:
    orig_centers = {}

if len(orig_centers) >= 2:
    raw_wins = subprocess.check_output(["yabai", "-m", "query", "--windows", "--space"])
    tiled_wins = [w for w in json.loads(raw_wins) if w.get("id") in orig_centers]
    
    # Slots available in BSP tree (current frames of tiled windows)
    # Match each original window to the closest slot by center distance
    slots = []
    for w in tiled_wins:
        f = w["frame"]
        slots.append({
            "slot_idx": len(slots),
            "current_wid": w["id"],
            "center": (f["x"] + f["w"] / 2.0, f["y"] + f["h"] / 2.0)
        })
    
    # Find permutation that minimizes total distance squared
    import itertools
    wids = list(orig_centers.keys())
    best_dist = float("inf")
    best_assignment = None # maps wid -> slot_idx
    
    for perm in itertools.permutations(range(len(slots))):
        total_dist = 0.0
        for wid, slot_idx in zip(wids, perm):
            oc = orig_centers[wid]
            sc = slots[slot_idx]["center"]
            total_dist += (oc[0] - sc[0])**2 + (oc[1] - sc[1])**2
        if total_dist < best_dist:
            best_dist = total_dist
            best_assignment = dict(zip(wids, perm))
            
    # Perform swaps if window is not in its optimal slot
    # best_assignment: wid -> desired slot_idx
    current_occupant = {s["slot_idx"]: s["current_wid"] for s in slots}
    wid_to_slot = {s["current_wid"]: s["slot_idx"] for s in slots}
    
    for wid, target_slot in best_assignment.items():
        curr_slot = wid_to_slot[wid]
        if curr_slot != target_slot:
            other_wid = current_occupant[target_slot]
            # Swap wid with other_wid in yabai
            subprocess.run(["yabai", "-m", "window", str(wid), "--swap", str(other_wid)], capture_output=True)
            # Update tracking
            wid_to_slot[wid] = target_slot
            wid_to_slot[other_wid] = curr_slot
            current_occupant[target_slot] = wid
            current_occupant[curr_slot] = other_wid
PYEOF

fi

# Trigger sketchybar status update
if command -v sketchybar >/dev/null 2>&1; then
    sketchybar --trigger yabai_mode_update 2>/dev/null
fi
