# Omarchy Keycaps Plugin

Visual keyboard shortcut overlay for the Omarchy shell. Displays currently-held keyboard shortcuts as tactile 3D mechanical keycaps centered at the bottom of the screen.

Press `Super + Space`, `Ctrl + Shift + Esc`, or any shortcut combination and watch the keycaps dynamically depress with active theme lighting, then smoothly spring back and fade away upon release.

![Keycaps Preview](preview.png)

## Features

- **Mechanical Keycap Styling**: Realistic 3D keycap geometry with bottom shadow bevels, depression travel animations on press, and spring return on release.
- **Theme-Adaptive**: Fully integrated with Omarchy's color tokens (`Color.popups.*`, `Color.accent`) and typography (`Style.font.*`). Looks sharp and maintains high contrast in both light and dark themes.
- **Smart Filtering**: Ignores normal typing (letters, numbers, space, standalone Shift); only activates when shortcut modifiers (`Super`, `Ctrl`, `Alt`) are invoked.
- **Safe Layer-Shell Window**: Rendered via Wayland layer-shell on the currently focused monitor with an empty input mask, ensuring it never blocks desktop clicks or gaming inputs.

---

## Installation

### 1. Install via Omarchy Shell

```bash
omarchy plugin add https://github.com/atascg01/omarchy-keycaps --enable
```

### 2. Wire the Hyprland Event Bridge

Key events are captured through Hyprland's lightweight event stream and forwarded via IPC. Run the bundled installer to hook the bridge:

```bash
bash ~/.config/omarchy/plugins/omarchy-keycaps/install.sh
hyprctl reload
```

---

## How It Works

1. **Hyprland Event Hook** (`hypr/keys.lua`): A non-blocking Lua hook on Hyprland's `input.keyboard.key` stream that forwards raw key press and release events via fire-and-forget IPC (`omarchy-shell -q omarchy-keycaps keyEvent <code> <0|1>`). Automatically cleans up and flushes keys on modifier release or compositor reload.
2. **Quickshell Service** (`Service.qml`): Runs in the background inside Omarchy shell. Tracks active modifier states, sequences key presses, and manages the dismissal countdown.
3. **Quickshell Overlay Panel** (`Panel.qml`): Multi-monitor aware Quickshell layer surface rendered on `Hyprland.focusedMonitor` with smooth entry/exit opacity and slide transitions.

---

## Manual Verification

Verify that the service is running and responsive:

```bash
# Ping the service
omarchy-shell omarchy-keycaps ping

# Simulate manual key events:
omarchy-shell omarchy-keycaps keyEvent SUPER 1   # Super down
omarchy-shell omarchy-keycaps keyEvent 65 1      # Space down
omarchy-shell omarchy-keycaps keyEvent 65 0      # Space up
omarchy-shell omarchy-keycaps keyEvent SUPER 0   # Super up
```

---

## Uninstallation

To cleanly remove the plugin:

```bash
# 1. Unhook the Lua bridge from ~/.config/hypr/hyprland.lua:
bash ~/.config/omarchy/plugins/omarchy-keycaps/install.sh --uninstall
hyprctl reload

# 2. Remove the plugin from Omarchy shell:
omarchy plugin remove omarchy-keycaps --yes
```

---

## License

[MIT](LICENSE) © Andres Tascon
