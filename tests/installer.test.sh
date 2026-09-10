#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
export KEYCAPS_HYPRLAND_CONFIG="$FIXTURE/hyprland.lua"
install_bridge() { bash "$ROOT/install.sh" "$@" > /dev/null; }

cat > "$KEYCAPS_HYPRLAND_CONFIG" <<'LUA'
-- My omarchy-keycaps notes must survive.
local example = "andrestascon.keys"
dofile("/my/omarchy-keycaps-custom.lua")
hl.config({ input = { kb_layout = "us" } })
LUA
cp "$KEYCAPS_HYPRLAND_CONFIG" "$FIXTURE/original"
install_bridge
test "$(grep -c '^-- BEGIN omarchy-keycaps bridge$' "$KEYCAPS_HYPRLAND_CONFIG")" = 1
test "$(find "$FIXTURE" -name '*.bak.*' | wc -l)" = 1
cmp "$FIXTURE/original" "$(find "$FIXTURE" -name '*.bak.*')"
cp "$KEYCAPS_HYPRLAND_CONFIG" "$FIXTURE/installed"
install_bridge
cmp "$FIXTURE/installed" "$KEYCAPS_HYPRLAND_CONFIG"
test "$(find "$FIXTURE" -name '*.bak.*' | wc -l)" = 1
install_bridge --uninstall
cmp "$FIXTURE/original" "$KEYCAPS_HYPRLAND_CONFIG"
install_bridge --uninstall
test "$(find "$FIXTURE" -name '*.bak.*' | wc -l)" = 2

for plugin in omarchy-keycaps andrestascon.keys; do
  cp "$FIXTURE/original" "$KEYCAPS_HYPRLAND_CONFIG"
  printf '%s\n' "-- $plugin bridge" >> "$KEYCAPS_HYPRLAND_CONFIG"
  printf 'dofile((os.getenv("HOME") or "/home/Someone With Spaces") .. "/.config/omarchy/plugins/%s/hypr/keys.lua")\n' "$plugin" >> "$KEYCAPS_HYPRLAND_CONFIG"
  install_bridge
  cmp "$FIXTURE/installed" "$KEYCAPS_HYPRLAND_CONFIG"
  install_bridge -u
  cmp "$FIXTURE/original" "$KEYCAPS_HYPRLAND_CONFIG"
done

for malformed in '-- BEGIN omarchy-keycaps bridge' '-- END omarchy-keycaps bridge'; do
  cp "$FIXTURE/original" "$KEYCAPS_HYPRLAND_CONFIG"
  printf '%s\n' "$malformed" >> "$KEYCAPS_HYPRLAND_CONFIG"
  cp "$KEYCAPS_HYPRLAND_CONFIG" "$FIXTURE/malformed"
  if install_bridge 2>/dev/null; then echo 'Malformed markers should fail' >&2; exit 1; fi
  cmp "$FIXTURE/malformed" "$KEYCAPS_HYPRLAND_CONFIG"
done
if install_bridge --typo 2>/dev/null; then echo 'Unknown argument should fail' >&2; exit 1; fi
cmp "$FIXTURE/malformed" "$KEYCAPS_HYPRLAND_CONFIG"
export KEYCAPS_HYPRLAND_CONFIG="$FIXTURE/missing/hyprland.lua"
if install_bridge 2>/dev/null; then echo 'Missing config should fail' >&2; exit 1; fi
test ! -d "$FIXTURE/missing"

export KEYCAPS_HYPRLAND_CONFIG="$FIXTURE/config with spaces.lua"
printf '%s' '-- omarchy-keycaps mention without a final newline' > "$KEYCAPS_HYPRLAND_CONFIG"
cp "$KEYCAPS_HYPRLAND_CONFIG" "$FIXTURE/no-newline"
install_bridge --uninstall
cmp "$FIXTURE/no-newline" "$KEYCAPS_HYPRLAND_CONFIG"
install_bridge
test "$(grep -c '^-- BEGIN omarchy-keycaps bridge$' "$KEYCAPS_HYPRLAND_CONFIG")" = 1
install_bridge --uninstall
printf '\n' >> "$FIXTURE/no-newline"
cmp "$FIXTURE/no-newline" "$KEYCAPS_HYPRLAND_CONFIG"

# Retain CRLF in unrelated lines; only the owned block is generated with LF.
printf '%s\r\n' '-- custom config' 'local name = "omarchy-keycaps"' > "$KEYCAPS_HYPRLAND_CONFIG"
cp "$KEYCAPS_HYPRLAND_CONFIG" "$FIXTURE/crlf"
install_bridge
install_bridge --uninstall
cmp "$FIXTURE/crlf" "$KEYCAPS_HYPRLAND_CONFIG"

if [[ "${OS:-}" != Windows_NT ]]; then
  cp "$FIXTURE/original" "$FIXTURE/dotfile.lua"
  chmod 640 "$FIXTURE/dotfile.lua"
  ln -s "$FIXTURE/dotfile.lua" "$FIXTURE/link.lua"
  export KEYCAPS_HYPRLAND_CONFIG="$FIXTURE/link.lua"
  install_bridge
  test -L "$KEYCAPS_HYPRLAND_CONFIG"
  test "$(stat -c %a "$FIXTURE/dotfile.lua")" = 640
  install_bridge --uninstall
  cmp "$FIXTURE/original" "$FIXTURE/dotfile.lua"
fi
echo 'PASS: installer preserves unrelated config, backs up changes, migrates legacy loaders, is idempotent, rejects malformed markers'
