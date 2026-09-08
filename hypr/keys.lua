-- Keycaps bridge for the omarchy-keycaps Omarchy shell plugin.
--
-- Hooks Hyprland's global keyboard event stream and forwards press/release
-- events for shortcut modifiers and shortcuts to the shell service.
--
-- Ignores normal typing (letters/numbers/space without a shortcut modifier)
-- so keycaps only appear when shortcuts are invoked.

local plugin_id = "omarchy-keycaps"

local function send_key(key, pressed)
  hl.exec_cmd("omarchy-shell -q " .. plugin_id .. " keyEvent " .. tostring(key) .. " " .. (pressed and "1" or "0"))
end

-- Detect if altwin:swap_lalt_lwin is configured in user's hypr input config
local function check_swap_lalt_lwin()
  local home = os.getenv("HOME") or ""
  local path = home .. "/.config/hypr/input.lua"
  local f = io.open(path, "r")
  if not f then return false end
  local content = f:read("*a")
  f:close()
  return content and content:find("altwin:swap_lalt_lwin") ~= nil
end

local has_swap = check_swap_lalt_lwin()

-- Map XKB keycodes for modifiers to canonical modifier labels
local function modifier_label(code)
  if code == 37 or code == 105 then return "CTRL" end
  if code == 50 or code == 62 then return "SHIFT" end
  if code == 108 then return "ALT" end
  if code == 134 then return "SUPER" end
  if code == 64 then
    return has_swap and "SUPER" or "ALT"
  end
  if code == 133 then
    return has_swap and "ALT" or "SUPER"
  end
  return nil
end

local is_modifier_code = {
  [37] = true, [105] = true,
  [50] = true, [62] = true,
  [64] = true, [108] = true,
  [133] = true, [134] = true,
}

-- Track currently physically held modifiers
local held_modifiers = {
  SUPER = false,
  CTRL = false,
  ALT = false,
  SHIFT = false,
}

local function any_shortcut_modifier_held()
  return held_modifiers.SUPER or held_modifiers.CTRL or held_modifiers.ALT
end

-- Track regular keys that have been forwarded as part of an active shortcut
local active_regular_keys = {}

local function flush_regular_keys()
  for code, _ in pairs(active_regular_keys) do
    send_key(code, false)
  end
  active_regular_keys = {}
end

local function sync_modifiers()
  if type(hl.is_key_down) ~= "function" then return end
  held_modifiers.SUPER = hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
  held_modifiers.CTRL = hl.is_key_down("Control_L") or hl.is_key_down("Control_R")
  held_modifiers.ALT = hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")
  held_modifiers.SHIFT = hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R")

  if not any_shortcut_modifier_held() then
    flush_regular_keys()
  end
end

hl.on("input.keyboard.key", function(keycode, _, state)
  local pressed = (state == 1)

  if is_modifier_code[keycode] then
    local mod = modifier_label(keycode)
    if mod then
      held_modifiers[mod] = pressed

      if type(hl.timer) == "function" then
        hl.timer(sync_modifiers, { timeout = 1, type = "oneshot" })
      end

      -- Shift alone is normal typing (capitalization); do not activate the visualizer
      -- unless a shortcut modifier (SUPER, CTRL, ALT) is already held.
      if mod == "SHIFT" and not any_shortcut_modifier_held() then
        if not pressed then
          send_key("SHIFT", false)
        end
        return
      end

      send_key(mod, pressed)

      if not pressed and not any_shortcut_modifier_held() then
        -- All shortcut modifiers released; flush any regular keys still marked active
        flush_regular_keys()
      end
    end
  else
    -- Regular key (character, space, number, enter, function key, etc.)
    if pressed then
      if any_shortcut_modifier_held() then
        active_regular_keys[keycode] = true
        send_key(keycode, true)
      end
    else
      if active_regular_keys[keycode] then
        active_regular_keys[keycode] = nil
        send_key(keycode, false)
      end
    end
  end
end)

hl.on("config.reloaded", function()
  has_swap = check_swap_lalt_lwin()
  held_modifiers.SUPER = false
  held_modifiers.CTRL = false
  held_modifiers.ALT = false
  held_modifiers.SHIFT = false
  active_regular_keys = {}
  hl.exec_cmd("omarchy-shell -q " .. plugin_id .. " clear")
end)
