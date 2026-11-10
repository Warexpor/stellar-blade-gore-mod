-- Test: Animated Death (Alt+F6): the game's own death shows played on her, so a death animation mod's (death_anim_P)
-- replaced animations show in the mod's animated death. Each press the next show, the death starting with it, taken
-- as animated even with active.animated off, her own fall, no cut, and she lies till F8
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.active = s.active or {}
s.active.animated = false
s.gore.smash.enabled = false
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
R.install(F, E)
F.world = R.step
-- (the game's death shows, in memory as they are once she has played)
for _, n in ipairs({ "P_Eve_Dead", "P_Eve_Dead2", "P_Eve_Dead3", "Eve_Dead_Down" }) do
  F.objects["/Game/Art/Show/CH_P_EVE_01/Basic/" .. n .. "." .. n] = F.obj(n, "SBShowData")
end
-- Model an outfit whose physics asset must be reattached at death, recreating its bodies.
local realDofile, remake, runtimeTune, gore, impulseAtSetup = dofile, false, nil, nil, nil
local broken = {}
E.mesh.BreakConstraint = function(_, _, _, bone) broken[#broken + 1] = tostring(bone) end
dofile = function(path)
  local result = realDofile(path)
  if path:match("/tune%.lua$") then runtimeTune = result end
  if path:match("/gore%.lua$") then gore = result end
  if path:match("physfix%.lua$") then
    local start = result.start
    result.start = function(...)
      local iv = pawn.RagdollInfo and pawn.RagdollInfo.ImpulseValue
      if iv then impulseAtSetup = math.sqrt(iv.X * iv.X + iv.Y * iv.Y + iv.Z * iv.Z) end
      local r = start(...)
      if remake then E.s.sim = false; result.remakes = (result.remakes or 0) + 1 end
      return r
    end
  end
  return result
end
local ok, err = pcall(dofile, DIR .. "main.lua")
dofile = realDofile
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from)
  for i, x in ipairs(F.log_lines()) do if i >= from then print("  | " .. x:sub(1, 200)) end end
end

-- 1: the show plays and her death starts with it: animated (active.animated off or not), her own fall, no cut, and
-- she lies 20 s on; F8 ends it (an animated death has no physics for F8 to turn off: it did nothing, playtest)
local at, shows = mark(), #E.shows
check(F.press("F6", "ALT"), "Alt+F6 bound")
F.run(0.5, pawn)
check(F.find("Test: Animated Death 1 of 4: her standing death %(P_Eve_Dead%)", at) ~= nil, "1: the first press: P_Eve_Dead")
check(#E.shows > shows and E.shows[#E.shows] == "P_Eve_Dead", "1: P_Eve_Dead played on her (" .. tostring(E.shows[#E.shows]) .. ")")
check(F.find("Test: Animated Death: her standing death %(P_Eve_Dead%): her death starts with it, no cut", at) ~= nil, "1: the death started with the show")
check(F.find("death: animated fall, physics off", at) ~= nil, "1: an animated death, active.animated off or not")
check(F.find("animated death: fall own", at) ~= nil, "1: her own fall: the show's animation, none of the knockdown falls")
F.run(20, pawn)
check(gore.cuts_on(E.mesh) == 0 and not gore.split_on(E.mesh), "1: no cut")
check(not F.find("recovering after", at) and not F.find("recover %(", at), "1: she lies there 20 s on")
local r = mark()
F.press("F8", "")
F.run(1, pawn)
check(F.find("recover %(ragdoll ended%)", r) ~= nil, "1: F8 got her up")
if fails > 0 then dump(at) end

-- Death starts with simulated bodies; asset setup recreates them as kinematic.
F.run(2, pawn)
at = mark()
remake = true
pawn.RagdollInfo = { ImpulseValue = { X = 5000, Y = 0, Z = 0 } }
E.s.hp = 0; E.die(true)
F.run(1, pawn)
check(impulseAtSetup and impulseAtSetup <= 701, "engine impulse capped before physics setup and deferred ragdoll start")
pawn.RagdollInfo = nil
check(F.find("ragdoll: restored simulation after physics asset setup: true", at) ~= nil, "3: physics asset replacement restores the ragdoll")
check(E.s.sim and not F.find("recover %(ragdoll ended%)", at), "3: death remains active after asset replacement")
remake = false
F.press("F8", ""); F.run(1, pawn)
F.run(3, pawn)

-- A waist cut made before death must stay disconnected if asset setup rebuilds its constraints.
at = mark()
check(gore.slice_bone(pawn, E.mesh, "Bip001-Spine1", nil, "test"), "early waist cut starts")
F.run(0.6, pawn)
check(gore.cut_parts(E.mesh)[1] == "Bip001-Spine1", "early waist cut opens before death")
broken = {}
remake = true
E.s.hp = 0; E.die(true)
F.run(0.5, pawn)
local rebroken = false
for _, b in ipairs(broken) do if b == "Bip001-Spine1" then rebroken = true end end
check(rebroken and F.find("re%-broke cuts after physics asset setup: Bip001%-Spine1", at),
  "death re-breaks the existing waist joint after physics bodies are recreated")
remake = false
F.press("F8", ""); F.run(2, pawn)

-- A death with unchanged physics must not re-break an existing cut.
at = mark()
check(gore.slice_bone(pawn, E.mesh, "Bip001-Spine1", nil, "test"), "second early waist cut starts")
F.run(0.6, pawn)
broken = {}
E.s.hp = 0; E.die(true)
F.run(0.5, pawn)
local unnecessary = false
for _, b in ipairs(broken) do if b == "Bip001-Spine1" then unnecessary = true end end
check(not unnecessary, "unchanged physics does not re-break existing cuts")
F.press("F8", ""); F.run(3, pawn)

-- 2: the next press, a death again (she was up)
at = mark()
F.press("F6", "ALT")
F.run(0.5, pawn)
check(F.find("Test: Animated Death 2 of 4: a hit's death %(P_Eve_Dead2%)", at) ~= nil, "2: the next press: P_Eve_Dead2")
check(F.find("her death starts with it", at) ~= nil and not F.find("already down", at), "2: its death started too")
F.press("F8", "")
F.run(1, pawn)
check(F.find("recover %(ragdoll ended%)", at) ~= nil, "2: F8 got her up")
if fails > 0 then dump(at) end

-- A projectile death can use the game's animated-show marker. It must retain its physics even with smash off.
E.respawn(); F.run(2, pawn)
assert(runtimeTune).active.animated = true
rawset(pawn, "RagdollInfo", { ImpulseLimitVelocity = 701 })
at = mark()
local head = E.bone("Bip001-Head")
F.fire("/Script/SB.SBNetworkPlayerController:ClientBroadcast_ProjectileHitResult", F.param(nil), F.param(1),
  F.param(991), F.param(4242), F.param(F.fname("Result")), F.param(1), F.param(head),
  F.param({X=0,Y=0,Z=1}), F.param(F.fname("Bip001-Head")), F.param({X=1,Y=0,Z=0}))
E.s.hp=0; E.die(true, 0)
F.run(0.5, pawn)
check(F.find("death: projectile hit, the ragdoll instead of an animated fall", at) ~= nil,
  "projectile death bypasses an animated show even with Blunt Smash disabled")
check(E.s.sim and not F.find("death: animated fall, physics off", at), "projectile death keeps body physics on")
F.press("F8", ""); F.run(1, pawn)
E.respawn(); F.run(2, pawn)
at = mark()
E.s.hp=0; E.die(true, 0); F.run(0.5, pawn)
check(F.find("death: animated fall, physics off", at) ~= nil, "ordinary marked death can still use its animation")
F.press("F8", ""); F.run(1, pawn)
if fails > 0 then dump(at) end

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
