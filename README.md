# cycle-quarters

A lightweight macOS window management script for **[yabai](https://github.com/koekeishiya/yabai)** and **[skhd](https://github.com/koekeishiya/skhd)** that cycles the active/focused window through the four screen quadrants.

---

## 🚀 How It Works

Each time the script runs, it moves and resizes the currently focused window clockwise through the 4 screen corners:
1. **Top-Left** (State 0 $\rightarrow$ 1)
2. **Top-Right** (State 1 $\rightarrow$ 2)
3. **Bottom-Right** (State 2 $\rightarrow$ 3)
4. **Bottom-Left** (State 3 $\rightarrow$ 0)

The script queries the active display frame dimensions via `yabai` and `jq`, calculates quadrant bounds dynamically (with custom padding adjustments), and tracks state in `/tmp/yabai-quarter-state`.

---

## 📋 Prerequisites & Installation

Make sure you have `yabai`, `skhd`, and `jq` installed:

```bash
# Install jq (JSON parser used for window calculations)
brew install jq

# Start yabai and skhd services
yabai --start-service
skhd --start-service
```

> **Note**: Grant Accessibility permissions to `yabai` and `skhd` when prompted in **System Settings > Privacy & Security > Accessibility**.

---

## ⚙️ Setup

1. **Make the script executable:**
   ```bash
   chmod +x cycle-quarter.sh
   ```

2. **Link or copy to your yabai config directory:**
   ```bash
   mkdir -p ~/.config/yabai
   ln -s "$(pwd)/cycle-quarter.sh" ~/.config/yabai/cycle-quarter.sh
   ```

3. **Bind a hotkey in `~/.config/skhd/skhdrc`:**
   ```bash
   # Cycle window across quarters on Ctrl + i
   ctrl - i : ~/.config/yabai/cycle-quarter.sh
   ```

4. **Reload skhd:**
   ```bash
   skhd --reload
   ```

---

## 🎮 How to Run

### Method 1: Using the Hotkey (Recommended)
- Click on any window to focus it.
- Press **`Ctrl` + `i`** to cycle it to the next quadrant.
- Repeatedly press **`Ctrl` + `i`** to move it around all four corners.

### Method 2: Running Directly from Terminal
You can trigger the script manually from your terminal:
```bash
./cycle-quarter.sh
# or via the full path:
~/.config/yabai/cycle-quarter.sh
```

---

## 🛠️ Configuration & Offsets

You can customize top/bottom paddings (e.g. for status bars or docks) directly in [`cycle-quarter.sh`](cycle-quarter.sh):

```sh
TOP_ADJUST=30       # reduces height of top windows (e.g. for menu bar / sketchybar)
BOTTOM_ADJUST=20    # pushes bottom windows down (e.g. for dock padding)
```

---

## 🔧 Service Management & Troubleshooting

| Action | Command |
| :--- | :--- |
| **Start Yabai** | `yabai --start-service` |
| **Restart Yabai** | `yabai --restart-service` |
| **Stop Yabai** | `yabai --stop-service` |
| **Start SKHD** | `skhd --start-service` |
| **Restart SKHD** | `skhd --restart-service` |
| **Reload SKHD config** | `skhd --reload` |
| **Check Yabai status** | `yabai -m query --displays --display` |

If windows do not move:
1. Ensure the yabai background service is running (`yabai --start-service`).
2. Verify Accessibility permissions in **macOS System Settings > Privacy & Security > Accessibility**.
3. Check error logs at `/tmp/yabai_<user>.err.log`.
