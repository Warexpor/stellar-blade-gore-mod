-- Her death cry as the character she looks like (gore.lua looks_as, voice_as; another mod plays her as someone else,
-- Stellar Blade Play As): Tachy's NPC body on her mesh, she dies crying a Tachy recording, and convulse's breaths and moans are
-- Tachy's; Raven's hair on her pose: Raven's; her own body again: Eve's
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
-- the recordings, loadable
local function sound(p) local o = F.obj(p:match("([^.]+)$"), "SoundWave"); F.objects[p] = o; return o end
for _, who in ipairs({ { "Tachy", "vo_Tachy_dmg_xl%d", 3 }, { "Raven", "vo_Raven_dmg_xl%d", 4 }, { "Tachy", "vo_Tachy_dmg_s%d", 5 },
  { "Tachy", "vo_Tachy_breath_s%d", 2 } }) do
  for i = 1, who[3] do
    local n = string.format(who[2], i) .. "_VO"
    sound("/Game/Sound/Dialogue/ActionVoice/" .. who[1] .. "/" .. n .. "." .. n)
  end
end
for i = 1, 5 do local n = string.format("vo_eve_die_%02d_VO", i); sound("/Game/Sound/Dialogue/ActionVoice/Eve/" .. n .. "." .. n) end
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("Default__GameplayStatics", "GameplayStatics", {
  SpawnSoundAttached = function() return F.obj("AudioComponent", "AudioComponent") end })

local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)
local function mark() return #F.log_lines() + 1 end
local function next_life() F.run(14, pawn); E.respawn(); F.run(6, pawn) end
local function cry(at) return F.find("voice: vo_", at) or "" end

-- Tachy
local eveBody = E.mesh.SkeletalMesh
E.mesh.SkeletalMesh = F.obj("CH_NPC_TachyNPC_Body", "SkeletalMesh")
local at = mark()
E.die(true)
F.run(1, pawn)
check(F.find("she looks like tachy", at) ~= nil, "Tachy's body on her: seen as Tachy")
check(cry(at):find("vo_Tachy_dmg_xl") ~= nil, "her cry a Tachy recording (" .. cry(at) .. ")")
F.run(6, pawn)
local soft = F.find("vo_Tachy_dmg_s%d_VO at", at) or F.find("vo_Tachy_breath_s%d_VO at", at)
check(soft ~= nil and not F.find("vo_eve_cinematic", at), "her breaths and moans after it Tachy's (" .. tostring(soft) .. ")")
next_life()

-- Raven: her hair on Eve's pose
E.mesh.SkeletalMesh = F.obj("CH_P_EVE_11", "SkeletalMesh")
local hair = F.obj("SkeletalMeshComponent_RavenHair", "SkeletalMeshComponent", {
  SkeletalMesh = F.obj("CH_M_NA_53_Hair", "SkeletalMesh"), IsVisible = function() return true end,
  MasterPoseComponent = { Get = function() return E.mesh end } })
rawset(E.mesh, "AttachChildren", { ForEach = function(_, f) f(1, { get = function() return hair end }) end })
at = mark()
E.die(true)
F.run(1, pawn)
check(F.find("she looks like raven", at) ~= nil, "Raven's hair on her pose: seen as Raven")
check(cry(at):find("vo_Raven_dmg_xl") ~= nil, "her cry a Raven recording (" .. cry(at) .. ")")
next_life()

-- Eve again
E.mesh.SkeletalMesh = eveBody
rawset(E.mesh, "AttachChildren", nil)
at = mark()
E.die(true)
F.run(1, pawn)
check(F.find("she looks like", at) == nil, "her own body: Eve")
check(cry(at):find("vo_eve_die_") ~= nil, "her cry Eve's own (" .. cry(at) .. ")")
check(#F.errors == 0, "no errors (" .. table.concat(F.errors, "; ") .. ")")
print(fails == 0 and "PASS" or "FAIL")
