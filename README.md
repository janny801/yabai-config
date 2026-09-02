# cycle-quarters

A lightweight macOS window management script for **[yabai](https://github.com/koekeishiya/yabai)** and **[skhd](https://github.com/koekeishiya/skhd)** that cycles the focused window through the four screen quadrants.

---

## 🚀 How It Works

Each time the script is triggered, it cycles the currently focused window through the 4 screen corners:
1. **Top-Left**
2. **Top-Right**
3. **Bottom-Right**
4. **Bottom-Left**

The script queries the active display frame dimensions via `yabai` and `jq`, calculates quadrant bounds dynamically (with custom padding adjustments), and updates the position state in `/tmp/yabai-quarter-state`.

---

## 📋 Prerequisites

- **yabai**: `yabai --start-service`
- **skhd**: `skhd --start-service`
- **jq**: `brew install jq`

---

## ⚙️ Setup

1. **Make the script executable:**
   ```bash
   chmod +x cycle-quarter.sh
   ```

2. **Add a keybinding to `~/.config/skhd/skhdrc`:**
   ```bash
   # Cycle window across quarters on Ctrl + i
   ctrl - i : /path/to/cycle-quarter.sh
   ```

3. **Reload skhd:**
   ```bash
   skhd --reload
   ```

---

## 🛠️ Configuration

You can tweak the padding/offset variables at the top of [`cycle-quarter.sh`](cycle-quarter.sh):

```sh
TOP_ADJUST=30       # reduces height of top windows (e.g. for menu bar / status bar)
BOTTOM_ADJUST=20    # pushes bottom windows down (e.g. for dock / status bar padding)
```
