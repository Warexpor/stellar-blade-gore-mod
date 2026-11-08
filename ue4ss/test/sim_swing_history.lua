local original_clock = os.clock
os.clock = function() return 100 end
FName = function(name) return name end
local actor = { K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end }
local mesh = { GetSocketLocation = function() return { X = 0, Y = 0, Z = 0 } end }
local state = { addr = 1, actor = actor, mesh = mesh, k = true, bones = { "hand" }, hist = {} }
local sw = { next = math.huge, list = { state }, state = function() return {} end }
local ctx = { held = function() return true end, time_scale = function() return 1 end }
local try = function(f) local ok, v = pcall(f); if ok then return v end end
local track = dofile("ue4ss/Mods/StellarBladeGore/Scripts/swing_tracking.lua")(
  sw, ctx, function() return { gore = { swingWindow = 0.6 } } end,
  function() return state end, function() end, function() return true end, function() end,
  {}, try, function() return true end, function(v) return v end, function() return 0 end,
  function() return "enemy" end, function() end)
local cases = {
  {}, { 98, 99, 99.4, 99.5, 100 }, { 99.4, 99.5, 98 },
}
local long = {}
for i = 1, 260 do long[i] = 99.5 end
cases[#cases + 1] = long
for _, times in ipairs(cases) do
  local history, expected = {}, {}
  for i, t in ipairs(times) do history[i] = { t = t }; expected[i] = history[i] end
  state.hist = history
  local added = { t = 100 }
  expected[#expected + 1] = added
  while #expected > 0 and 100 - expected[1].t > 0.6 do table.remove(expected, 1) end
  while #expected > 240 do table.remove(expected, 1) end
  track(nil, mesh)
  assert(state.hist == history and #history == #expected, "history identity or length changed")
  for i, sample in ipairs(expected) do
    assert(history[i].t == sample.t and (sample == added or history[i] == sample), "history order changed")
  end
end
os.clock = original_clock
print("swing history pruning matches the previous algorithm")
print("PASS")
