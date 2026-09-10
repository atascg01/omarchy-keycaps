-- Complete shortcut snapshots over Hyprland's ordered event socket. No process
-- is spawned on the keyboard path, and ordinary typing is never forwarded.
local modifier_codes = { 133, 134, 37, 105, 50, 62, 64, 108 }
local modifier_order = { "SUPER", "CTRL", "SHIFT", "ALT" }
local held_codes = {}
local regular_keys = {} -- ordered by physical press, not numeric keycode
local sequence = 0

-- A new Lua state gets a new identity, so sequence numbers can restart on reload.
local uuid_file = assert(io.open("/proc/sys/kernel/random/uuid", "r"))
local session = uuid_file:read("*l")
uuid_file:close()

local function contains_swap(options)
  if type(options) ~= "string" then return false end
  for option in options:gmatch("[^,]+") do
    if option:match("^%s*(.-)%s*$") == "altwin:swap_lalt_lwin" then return true end
  end
  return false
end

local function check_swap_lalt_lwin()
  if type(hl.get_config) == "function" and contains_swap(hl.get_config("input:kb_options")) then
    return true
  end
  -- get_config exposes global options only, not hl.device overrides. Preserve
  -- the original input.lua fallback for device-specific Alt/Super swaps.
  -- Only inspect literal kb_options assignments, ignoring commented examples.
  local file = io.open((os.getenv("HOME") or "") .. "/.config/hypr/input.lua", "r")
  if not file then return false end
  local content = file:read("*a")
  file:close()
  content = content:gsub("%-%-%[(=*)%[.-%]%1%]", "")
  content = content:gsub("%-%-[^\n]*", "")
  for _, options in content:gmatch("kb_options%s*=%s*(['\"])(.-)%1") do
    if contains_swap(options) then return true end
  end
  return false
end

local has_swap = check_swap_lalt_lwin()

local function modifier_label(code)
  if code == 37 or code == 105 then return "CTRL" end
  if code == 50 or code == 62 then return "SHIFT" end
  if code == 108 then return "ALT" end
  if code == 134 then return "SUPER" end
  if code == 64 then return has_swap and "SUPER" or "ALT" end
  if code == 133 then return has_swap and "ALT" or "SUPER" end
  return nil
end

local function logical_modifiers()
  local modifiers = {}
  for _, code in ipairs(modifier_codes) do
    if held_codes[code] then modifiers[modifier_label(code)] = true end
  end
  return modifiers
end

local function has_shortcut(modifiers)
  return modifiers.SUPER or modifiers.CTRL or modifiers.ALT
end

local function publish(reset)
  local modifiers = logical_modifiers()
  local keys = {}
  if has_shortcut(modifiers) then
    for _, label in ipairs(modifier_order) do
      if modifiers[label] then keys[#keys + 1] = '"' .. label .. '"' end
    end
    for _, code in ipairs(regular_keys) do keys[#keys + 1] = tostring(code) end
  else
    -- Releasing the last shortcut modifier ends the combo even when a regular
    -- key remains down. Retain physical Shift for the next shortcut.
    regular_keys = {}
  end
  sequence = sequence + 1
  local payload = string.format(
    '{"version":1,"session":"%s","sequence":%d,"reset":%s,"keys":[%s]}',
    session, sequence, reset and "true" or "false", table.concat(keys, ","))
  hl.dispatch(hl.dsp.event("omarchy-keycaps," .. payload))
end

local function reconcile()
  if type(hl.is_key_down) ~= "function" then return end
  for _, code in ipairs(modifier_codes) do
    held_codes[code] = hl.is_key_down(code) or nil
  end
  for i = #regular_keys, 1, -1 do
    if not hl.is_key_down(regular_keys[i]) then table.remove(regular_keys, i) end
  end
end

hl.on("input.keyboard.key", function(code, _, state)
  -- Hyprland uses state 2 for repeats. It is not a release.
  if state ~= 0 and state ~= 1 then return end
  if type(code) ~= "number" or code % 1 ~= 0 or code <= 0 or code >= 768 then return end
  local pressed = state == 1
  if modifier_label(code) then
    local was_shortcut = has_shortcut(logical_modifiers())
    if (held_codes[code] == true) == pressed then return end
    held_codes[code] = pressed or nil
    if was_shortcut or has_shortcut(logical_modifiers()) then publish(false) end
  else
    local index = nil
    for i, key in ipairs(regular_keys) do
      if key == code then index = i; break end
    end
    if pressed then
      if not index and has_shortcut(logical_modifiers()) then
        regular_keys[#regular_keys + 1] = code
        publish(false)
      end
    elseif index then
      table.remove(regular_keys, index)
      publish(false)
    end
  end
end)

hl.on("config.reloaded", function()
  has_swap = check_swap_lalt_lwin()
  held_codes = {}
  regular_keys = {}
  publish(true)
end)

-- Recover missed releases and shell restarts, including when no further keys
-- are pressed. Empty heartbeats do not extend the service's dismissal timer.
if type(hl.timer) == "function" then
  hl.timer(function()
    reconcile()
    publish(false)
  end, { timeout = 1000, type = "repeat" })
end

publish(true)
