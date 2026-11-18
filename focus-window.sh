#!/usr/bin/env bash

# Focus window by position index on current space (0-based)
# Windows sorted top-to-bottom, left-to-right:
# 0 -> g (top-left)
# 1 -> h
# 2 -> j
# 3 -> k
# 4 -> l

target_index="$1"

if [ -z "$target_index" ]; then
    echo "Usage: $0 <window-index-0-based>"
    exit 1
fi

window_id=$(yabai -m query --windows --space | jq -r --argjson idx "$target_index" '
  [ .[] | select(."is-visible" == true and ."is-minimized" == false and ."is-hidden" == false and ."role" == "AXWindow") ]
  | sort_by( ((.frame.y / 60) | floor), .frame.x, .id )
  | .[$idx].id // empty
')

if [ -n "$window_id" ]; then
    yabai -m window --focus "$window_id"
fi
