-- The mod's keys, rebindable (tune.keys, the F3 menu's Keys tab): each action's key is "F11", "Ctrl+Shift+F5",
-- "Alt+NUM_ONE" (UE4SS's Key names, Ctrl / Shift / Alt before it), or "None". Unset, the default here (the test keys
-- F9-F11 on Alt with Ultra Violence on: it has them). UE4SS's key binds can't be taken back, so every key below is
-- bound once at load with each set of modifiers; a press is looked up in the bindings as they are then, and a key
-- with two sets down at once (Ctrl+F5 fired F5's bind too) goes to the one with the most modifiers. Another mod on the
-- same key (a body slider's menu on F11, Nexus report) still gets it: moving ours off it is the way out
local M = {}
local ctx, log

-- the keys a binding can use: UE4SS's Key name, the engine's (the menu reads a key down by it), as shown
M.LIST = {}
do
  local function add(enum, fkey, show) M.LIST[#M.LIST + 1] = { enum = enum, fkey = fkey, show = show or enum } end
  for i = 1, 12 do add("F" .. i, "F" .. i) end
  for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do add(c, c) end
  local digits = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
  local fdigits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
  for i = 0, 9 do add(digits[i + 1], fdigits[i + 1], tostring(i)) end
  for i = 0, 9 do add("NUM_" .. digits[i + 1], "NumPad" .. fdigits[i + 1], "Num " .. i) end
  add("MULTIPLY", "Multiply", "Num *"); add("ADD", "Add", "Num +"); add("SUBTRACT", "Subtract", "Num -")
  add("DIVIDE", "Divide", "Num /"); add("DECIMAL", "Decimal", "Num .")
  add("INS", "Insert", "Insert"); add("DEL", "Delete", "Delete"); add("HOME", "Home", "Home"); add("END", "End", "End")
  add("PAGE_UP", "PageUp", "Page Up"); add("PAGE_DOWN", "PageDown", "Page Down")
end
M.BY_ENUM = {}
for _, k in ipairs(M.LIST) do M.BY_ENUM[k.enum] = k end
M.MODS = { "Ctrl", "Shift", "Alt" }
M.MOD_KEY = { Ctrl = "CONTROL", Shift = "SHIFT", Alt = "ALT" }
M.MOD_FKEYS = { Ctrl = { "LeftControl", "RightControl" }, Shift = { "LeftShift", "RightShift" }, Alt = { "LeftAlt", "RightAlt" } }

-- No default a key she uses alive is on Shift or Ctrl: they are the game's own (sprint, dodge...), held in a fight
-- with the key or not. Shift+F4 (Hold the Death) is only read in a death.
-- the actions, in the menu's order: id (tune.keys.<id>), its row's label, the default, dev (a test key: dead unless
-- settings.lua's dev), help
M.ACTIONS = {
  { id = "menu", label = "Settings Menu", def = "F3", help = "Opens and closes this menu." },
  { id = "hold", label = "Hold the Death", def = "Shift+F4", help = "In a death: brings the death screen up early, or hides it and keeps her down till pressed again." },
  { id = "photo", label = "Photo Mode in a Death", def = "P", help = "In a death: opens the game's photo mode on her body. The death waits while it is open." },
  { id = "slice", label = "Test: Cut", def = "F9", uv = true, dev = true, help = "Developer Keys: cuts a limb, the head or the torso off her where she stands." },
  { id = "split", label = "Test: Split", def = "F11", uv = true, dev = true, help = "Developer Keys: ragdolls her and splits her in half along the camera's view." },
  { id = "mark", label = "Test: Hit Mark", def = "F10", uv = true, dev = true, help = "Developer Keys: a living hit's wound on a part of her facing the camera." },
  { id = "ragdoll", label = "Test: Ragdoll", def = "F7", dev = true, help = "Developer Keys: ragdolls her with a shove. She stays down till Test: Get Up." },
  { id = "recover", label = "Test: Get Up", def = "F8", dev = true, help = "Developer Keys: gets her up from a test ragdoll or cut." },
  { id = "face", label = "Test: Death Face", def = "PAGE_UP", dev = true, help = "Developer Keys: her death face for 6 s, the next mood each press." },
  { id = "loseLeft", label = "Test: Lose Left Arm", def = "Alt+F7", dev = true, help = "Developer Keys: with Lose Arm at Low HP on, takes her left arm off now as a hit under the mark would, with No Heals or Gun." },
  { id = "loseRight", label = "Test: Lose Right Arm", def = "Alt+F8", dev = true, help = "Developer Keys: with Lose Arm at Low HP on, takes her right arm off now as a hit under the mark would, with No Sword." },
  { id = "death", label = "Test: Struggle", def = "F6", dev = true, help = "Developer Keys: a ragdoll death with set cuts to test the struggle, the next each press: right arm, left leg, waist, left arm and right leg, both legs, left forearm, no cut (sitting up only), with Test: Ragdoll's shove. She lies till F8." },
  { id = "animDeath", label = "Test: Animated Death", def = "Alt+F6", dev = true, help = "Developer Keys: kills her with the game's own death animations, the next each press: standing, two hit deaths, lying down (death animation mods show in them). Always the animated death, with no cut. She lies till Test: Get Up." },
  { id = "blade", label = "Test: Blade Death", def = "DEL", dev = true, help = "Developer Keys: ragdolls her and cuts along a made-up blade." },
  { id = "spawn", label = "Test: Spawn Enemy", def = "F5", dev = true, help = "Developer Keys: spawns the enemy kind picked in front of her." },
  { id = "nextEnemy", label = "Test: Next Enemy Kind", def = "INS", dev = true, help = "Developer Keys: picks the next enemy kind to spawn." },
  { id = "spawner", label = "Test: Spawner Window", def = "HOME", dev = true, help = "Developer Keys: opens the enemy spawner window." },
  { id = "kill", label = "Test: Kill Nearest Enemy", def = "END", dev = true, help = "Developer Keys: kills the enemy nearest her." },
  { id = "glass", label = "Test: Glass Cannon", def = "PAGE_DOWN", dev = true, help = "Developer Keys: glass cannon mode on and off." },
}
M.BY_ID = {}
for _, a in ipairs(M.ACTIONS) do M.BY_ID[a.id] = a end
M.uv = false -- Ultra Violence is on (main.lua): the uv actions' defaults are on Alt
M.handlers = {}
M.fired = {}
M.nav = {} -- the arrow keys pressed since the menu last looked: "up", "down", "left", "right"

function M.init(c)
  ctx, log = c, c.log
end

-- "Ctrl+Shift+F5" -> { Ctrl = true, Shift = true }, "F5" (nil key when it isn't one of LIST)
function M.parse(s)
  local mods, key = {}, nil
  for part in tostring(s or ""):gmatch("[^+]+") do
    local p = part:gsub("^%s+", ""):gsub("%s+$", "")
    local m = ({ ctrl = "Ctrl", control = "Ctrl", shift = "Shift", alt = "Alt" })[p:lower()]
    if m then mods[m] = true else key = p:upper() end
  end
  if key and not M.BY_ENUM[key] then key = nil end
  return mods, key
end
-- the canonical form: modifiers in M.MODS' order
function M.combo(mods, key)
  if not key then return "None" end
  local out = {}
  for _, m in ipairs(M.MODS) do if mods[m] then out[#out + 1] = m end end
  out[#out + 1] = key
  return table.concat(out, "+")
end
function M.default(id)
  local a = M.BY_ID[id]
  if not a then return "None" end
  return (a.uv and M.uv) and ("Alt+" .. a.def) or a.def
end
-- an action's binding now (canonical, "None" when unbound or unreadable)
function M.binding(id)
  local v = ((ctx and ctx.tune or {}).keys or {})[id]
  if v == nil then v = M.default(id) end
  if v == false or v == "None" then return "None" end
  local mods, key = M.parse(v)
  return M.combo(mods, key)
end
-- as shown: "Ctrl+Shift+F5", "Alt+Num 1"
function M.show(s)
  local mods, key = M.parse(s)
  if not key then return "None" end
  local out = {}
  for _, m in ipairs(M.MODS) do if mods[m] then out[#out + 1] = m end end
  out[#out + 1] = M.BY_ENUM[key].show
  return table.concat(out, "+")
end

-- main.lua's function for an action: fn() run on the game thread, its label for the log
function M.on(id, fn)
  M.handlers[id] = fn
end

-- every key with every set of modifiers but all three, bound once (UE4SS's input thread: noted, run by flush)
function M.register()
  local sets = { {}, { "Shift" }, { "Ctrl" }, { "Alt" }, { "Ctrl", "Shift" }, { "Ctrl", "Alt" }, { "Shift", "Alt" } }
  local n = 0
  for _, k in ipairs(M.LIST) do
    local key = Key[k.enum]
    if key then
      for _, set in ipairs(sets) do
        local mk, mods = {}, {}
        for _, m in ipairs(set) do mk[#mk + 1] = ModifierKey[M.MOD_KEY[m]]; mods[m] = true end
        local combo, count = M.combo(mods, k.enum), #set
        local function cb()
          local f = M.fired[k.enum]
          if not f or count > f.count then M.fired[k.enum] = { combo = combo, count = count } end
        end
        local ok = (#mk == 0) and pcall(RegisterKeyBind, key, cb) or (#mk > 0 and pcall(RegisterKeyBind, key, mk, cb))
        if ok then n = n + 1 end
      end
    end
  end
  -- the menu's arrow keys, its own: the engine never saw the arrow keys while the game played (the menu read them
  -- down by name, and nothing moved, playtest). Noted here, taken by gui.lua's tick (M.nav)
  for _, d in ipairs({ { "UP_ARROW", "up" }, { "DOWN_ARROW", "down" }, { "LEFT_ARROW", "left" }, { "RIGHT_ARROW", "right" } }) do
    if Key[d[1]] and pcall(RegisterKeyBind, Key[d[1]], function() M.nav[#M.nav + 1] = d[2] end) then n = n + 1 end
  end
  log(string.format("keys: %d binds (%d keys, 7 sets of modifiers each, and the menu's arrows)", n, #M.LIST))
end

-- the keys pressed since the last frame: each to the action bound to it (game thread, game_tick). The menu taking a
-- key (its Keys tab waiting for one) gets it instead
function M.flush()
  local fired = M.fired
  if next(fired) == nil then return end
  M.fired = {}
  for _, f in pairs(fired) do
    if M.capture then M.capture(f.combo)
    else
      for _, a in ipairs(M.ACTIONS) do
        if M.binding(a.id) == f.combo and M.handlers[a.id] and not (a.dev and not ctx.tune.dev) then
          local ok, err = pcall(M.handlers[a.id])
          if not ok then log(M.show(f.combo) .. " (" .. a.label .. ") error: " .. tostring(err)) end
        end
      end
    end
  end
end

-- the actions on a binding (the menu: another one on the key just taken)
function M.on_combo(combo, but)
  local out = {}
  for _, a in ipairs(M.ACTIONS) do if a.id ~= but and M.binding(a.id) == combo then out[#out + 1] = a end end
  return out
end

return M
