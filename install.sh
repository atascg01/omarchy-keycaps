#!/usr/bin/env bash
# Wires the omarchy-keycaps Lua bridge into ~/.config/hypr/hyprland.lua.
# Idempotent: safe to run repeatedly.
# Run with --uninstall to remove the bridge line.

set -euo pipefail

HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
MARKER="omarchy-keycaps bridge"
LINE="dofile((os.getenv(\"HOME\") or \"$HOME\") .. \"/.config/omarchy/plugins/omarchy-keycaps/hypr/keys.lua\")"

mkdir -p "$(dirname "$HYPRLAND_LUA")"

if [[ ! -f "$HYPRLAND_LUA" ]]; then
  echo "hyprland.lua not found at $HYPRLAND_LUA" >&2
  exit 1
fi

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "uninstall" || "${1:-}" == "-u" ]]; then
  if grep -q "omarchy-keycaps\|andrestascon.keys" "$HYPRLAND_LUA"; then
    cp "$HYPRLAND_LUA" "$HYPRLAND_LUA.bak.$(date +%s)"
    sed -i '/omarchy-keycaps/d;/andrestascon.keys/d' "$HYPRLAND_LUA"
    echo "unwired. run: hyprctl reload"
  else
    echo "not wired"
  fi
  exit 0
fi

if grep -q "omarchy-keycaps/hypr/keys.lua" "$HYPRLAND_LUA"; then
  echo "already wired"
  exit 0
fi

cp "$HYPRLAND_LUA" "$HYPRLAND_LUA.bak.$(date +%s)"

# Clean up any legacy andrestascon.keys line
sed -i '/andrestascon.keys/d' "$HYPRLAND_LUA"

# Append the bridge loader at the end of the file.
{
  echo ""
  echo "-- $MARKER"
  echo "$LINE"
} >> "$HYPRLAND_LUA"

echo "wired. run: hyprctl reload"
