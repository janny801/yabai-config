#!/usr/bin/env bash

# Focus window by position index on current space (0-based)
# Windows sorted top-to-bottom, left-to-right:
# 0 -> 1 (top-left)
# 1 -> 2
# 2 -> 3
# 3 -> 4
# 4 -> 5
# 5 -> 6
# 6 -> 7
# 7 -> 8
# 8 -> 9

target_index="$1"

if [ -z "$target_index" ]; then
    echo "Usage: $0 <window-index-0-based>"
    exit 1
fi

read -r window_id pid < <(yabai -m query --windows --space | jq -r --argjson idx "$target_index" '
  [ .[] | select(."is-visible" == true and ."is-minimized" == false and ."is-hidden" == false and ."role" == "AXWindow") ]
  | sort_by( ((.frame.y / 60) | floor), .frame.x, .id )
  | if .[$idx] then "\([$idx].id) \([$idx].pid)" else empty end
')

if [ -n "$window_id" ]; then
    yabai -m window --focus "$window_id" 2>/dev/null || {
        if [ -n "$pid" ]; then
            osascript -e "tell application \"System Events\" to set frontmost of first process whose unix id is $pid to true" 2>/dev/null
        fi
    }
fi
