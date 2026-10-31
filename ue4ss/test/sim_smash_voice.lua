-- Reuse the exact beheading cutoff for head/upper-body smashes; other cuts keep their voice.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }\ns.active.animated = false')
local F, E, G, pawn = T.F, T.E, T.G, T.pawn
local fails, audio = 0, {}
local function check(ok, what)
  F.say((ok and "ok   " or "FAIL ") .. what)
  if not ok then fails = fails + 1 end
end
for i = 1, 5 do
  local name = string.format("vo_eve_die_%02d_VO", i)
  local path = "/Game/Sound/Dialogue/ActionVoice/Eve/" .. name .. "." .. name
  F.objects[path] = F.obj(name, "SoundWave")
end
local function spawn()
  local c = F.obj("Cry", "AudioComponent", { started = F.t, fades = {}, playing = true })
  c.IsPlaying = function(self) return self.playing end
  c.FadeOut = function(self, seconds, volume, curve)
    self.fades[#self.fades + 1] = { at = F.t, seconds = seconds, volume = volume, curve = curve }
    self.playing = false
  end
  audio[#audio + 1] = c
  return c
end
local gs = F.objects["/Script/Engine.Default__GameplayStatics"]
gs.SpawnSoundAttached, gs.SpawnSoundAtLocation = spawn, spawn
local function run(sec)
  for _ = 1, math.floor(sec * 60) do F.step(1/60); G.tick(pawn); G.pump() end
end
local cases = {
  { "head cut", "Bip001-Head", false, true },
  { "head smash", "Bip001-Head", true, true },
  { "upper-body smash", "Bip001-Spine1", true, true },
  { "upper-body cut", "Bip001-Spine1", false, false },
  { "arm cut", "Bip001-L-UpperArm", false, false },
  { "arm smash", "Bip001-L-UpperArm", true, false },
  { "leg smash", "Bip001-L-Thigh", true, false },
}
local original = G.slice_bone
for _, c in ipairs(cases) do
  E.s.sim = true
  G.voice_death(pawn, E.mesh)
  local cry = audio[#audio]
  run(0.12)
  if c[3] then
    -- Force this bone while still running the production smash path and all cut stages.
    local part = G.smash_part
    G.smash_part = function() return c[2], nil, c[2] == "Bip001-Head" and "head" or c[2] == "Bip001-Spine1" and "torso" or "limb" end
    G.smash(pawn, E.mesh, nil, "test")
    G.smash_part = part
  else original(pawn, E.mesh, c[2], nil, "test") end
  run(1)
  check(#cry.fades == (c[4] and 1 or 0), c[1] .. ": correct voice cutoff gate")
  if c[4] then
    local fade = cry.fades[1]
    check(fade and fade.at > cry.started and fade.seconds == 0.08 and fade.volume == 0 and fade.curve == 3,
      c[1] .. ": cry starts first, then the unchanged 0.08 s Sin fade")
  end
  cry.playing = false
  local soft = G.voice_soft(pawn, E.mesh, { "vo_eve_die_01" }, 0.2)
  check((soft == nil) == c[4], c[1] .. ": soft voice blocked only after head loss or upper-body smash")
  G.cleanup(pawn, E.mesh)
end
-- Only smashes get the guard when they happen before the death voice starts.
for _, c in ipairs(cases) do
  E.s.sim = true
  if c[3] then G.smash_once = true end
  original(pawn, E.mesh, c[2], nil, "test")
  G.smash_once = nil
  run(1)
  G.voice_death(pawn, E.mesh)
  local cry = audio[#audio]
  check(#cry.fades == (c[3] and c[4] and 1 or 0), c[1] .. " before cry: smash-only late-start guard")
  G.cleanup(pawn, E.mesh)
end
G.voice_death(pawn, E.mesh)
check(#audio[#audio].fades == 0, "recovery leaves the next intact death cry alone")
-- Actual death broadcasts start the cry and smash through main.lua, not test calls.
for _, kind in ipairs({ "head", "torso" }) do
  E.respawn(); F.run(3, pawn)
  local g = T.ctx.tune.gore
  g.smash.always = true
  g.death = { limb = 0, head = 0, torso = 0, split = 0 }
  g.death[kind] = 100
  E.s.hp = 0
  local n0 = #audio
  E.die(true); F.run(1, pawn)
  local cry = audio[n0 + 1]
  check(cry and #audio == n0 + 1 and #cry.fades == 1 and cry.fades[1].seconds == 0.08,
    kind .. ": real death starts one cry and applies the beheading fade")
end
for _, e in ipairs(F.errors) do check(false, "hook: " .. e) end
F.say(fails == 0 and "PASS" or "FAIL")
