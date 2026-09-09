-- Run from the repo root: lua tests/bridge.test.lua
local function bridge(options)
  local events, timers, messages, down = {}, {}, {}, {}
  local config = options or ""
  local env = setmetatable({
    io = { open = function(path)
      assert(path == "/proc/sys/kernel/random/uuid")
      return { read = function() return "test-session" end, close = function() end }
    end },
    hl = {
      on = function(name, fn) events[name] = fn end,
      timer = function(fn, spec)
        assert(spec.timeout == 1000 and spec.type == "repeat")
        timers[#timers + 1] = fn
      end,
      get_config = function(key) assert(key == "input:kb_options"); return config end,
      is_key_down = function(code) assert(type(code) == "number"); return down[code] == true end,
      dsp = { event = function(payload) return payload end },
      dispatch = function(payload) messages[#messages + 1] = payload end,
      exec_cmd = function() error("keyboard bridge must not spawn processes") end,
    }
  }, { __index = _G })
  assert(loadfile("hypr/keys.lua", "t", env))()
  return {
    messages = messages,
    down = down,
    key = function(code, state)
      if state ~= 2 then down[code] = state == 1 or nil end
      events["input.keyboard.key"](code, 1, state)
    end,
    tick = function() for _, timer in ipairs(timers) do timer() end end,
    reload = function(value) config = value or config; events["config.reloaded"]() end,
    expect = function(keys)
      local actual = messages[#messages]:match('"keys":(%[.-%])')
      assert(actual == keys, "expected " .. keys .. ", got " .. tostring(actual))
    end,
  }
end

local b = bridge()
b.expect('[]')
assert(b.messages[1]:find('"reset":true', 1, true))
local count = #b.messages
b.key(38, 1); b.key(38, 0); b.key(50, 1)
assert(#b.messages == count, "typing and Shift alone must not be forwarded")
b.key(133, 1); b.key(65, 1)
b.expect('["SUPER","SHIFT",65]')
b.key(65, 2)
b.expect('["SUPER","SHIFT",65]')
assert(#b.messages == count + 2, "repeat must not publish or release")
b.key(133, 0)
b.expect('[]')
count = #b.messages
b.key(65, 0)
assert(#b.messages == count, "regular key release after final modifier was already flushed")
b.key(37, 1)
b.expect('["CTRL","SHIFT"]')

for _, pair in ipairs({ {37, 105, 'CTRL'}, {133, 134, 'SUPER'}, {64, 108, 'ALT'}, {50, 62, 'SHIFT'} }) do
  b = bridge()
  if pair[3] == 'SHIFT' then b.key(133, 1) end
  b.key(pair[1], 1); b.key(pair[2], 1); b.key(pair[1], 0)
  b.expect(pair[3] == 'SHIFT' and '["SUPER","SHIFT"]' or '["' .. pair[3] .. '"]')
  b.key(pair[2], 0)
  b.expect(pair[3] == 'SHIFT' and '["SUPER"]' or '[]')
end

b = bridge()
b.key(133, 1); b.key(10, 1); b.key(10, 0); b.key(11, 1)
b.expect('["SUPER",11]')
b.key(10, 1)
b.expect('["SUPER",11,10]')
count = #b.messages
b.key(10, 1)
assert(#b.messages == count, "duplicate press must not reorder")

-- Reconciliation repairs a missed release using physical keycodes.
b.down[133] = nil
b.tick()
b.expect('[]')
-- A modifier held before the bridge started is recovered on its next heartbeat.
b.down[50] = true; b.down[105] = true
b.tick()
b.expect('["CTRL","SHIFT"]')
b.reload()
b.expect('[]')
assert(b.messages[#b.messages]:find('"reset":true', 1, true))
for index, message in ipairs(b.messages) do
  assert(message:match('^omarchy%-keycaps,{"version":1,'))
  assert(tonumber(message:match('"sequence":(%d+)')) == index, "sequence must increase through reload")
end

b = bridge('caps:escape, altwin:swap_lalt_lwin')
b.key(64, 1); b.key(134, 1); b.key(64, 0)
b.expect('["SUPER"]')
b.key(133, 1)
b.expect('["SUPER","ALT"]')
b.reload('')
b.key(64, 1)
b.expect('["ALT"]')
b = bridge('altwin:swap_lalt_lwin_extra')
b.key(64, 1)
b.expect('["ALT"]')

print('PASS: bridge filtering, Shift-first, dual modifiers, repeats, chords, reconciliation, reload, sequence, Alt/Super swap')
