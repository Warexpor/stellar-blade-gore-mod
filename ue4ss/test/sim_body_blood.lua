local create = dofile('ue4ss/Mods/StellarBladeGore/Scripts/body_blood.lua')
local M, values = {}, { BloodFactor = 0.2, BloodOffset = 0.3 }
local ctx = { tune = { stains = { enabled = false }, gore = { bodyBlood = { enabled = true, factor = 1, offset = 0.9, time = 0.2 } } } }
local writes = 0
FName = function(n) return n end
local library = {
  GetScalarParameterValue = function(_, _, _, name) return values[name] end,
  SetScalarParameterValue = function(_, _, _, name, v) values[name] = v; writes = writes + 1 end,
}
local function try(fn) local ok, result = pcall(fn); if ok then return result end end
local function load(path) return path == 'collection' and {} or library end
local blood = create(M, function() return ctx.tune.gore end, load, function() return ctx end,
  function() return try, function(o) return o ~= nil end end, function() end, 'collection', 0.1)
local fails = 0
local function check(ok, msg) print((ok and 'ok   ' or 'FAIL ') .. msg); if not ok then fails = fails + 1 end end
local function close(a, b) return math.abs(a - b) < 0.0001 end
blood.up({})
blood.tick()
check(close(values.BloodFactor, 0.6) and close(values.BloodOffset, 0.6), 'blood ramps from original values')
blood.tick()
check(close(values.BloodFactor, 1) and close(values.BloodOffset, 0.9), 'blood reaches configured values')
blood.down()
check(close(values.BloodFactor, 0.2) and close(values.BloodOffset, 0.3), 'recovery restores original values')
blood.up({})
blood.tick()
local before = writes
blood.forget()
check(writes == before and close(M.blood_restore.BloodFactor, 0.2) and close(M.blood_restore.BloodOffset, 0.3),
  'world change saves old values without touching old objects')
blood.restore(nil)
check(M.blood_restore ~= nil and writes == before, 'invalid pawn leaves restoration pending')
blood.restore({})
check(M.blood_restore == nil and close(values.BloodFactor, 0.2) and close(values.BloodOffset, 0.3),
  'new pawn restores the saved material values')
before = writes
ctx.tune.stains.enabled = true
blood.up({})
blood.tick()
blood.down()
check(writes == before, 'native stains prevent the legacy ramp from writing')
print(fails == 0 and 'PASS' or 'FAIL')
