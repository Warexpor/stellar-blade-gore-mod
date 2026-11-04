-- Gore sound cues and their playback throttling.
return function(cfg, load_obj, valid, log, vec, get_ctx)
-- the game's own gore sounds (sound cues, played where it happens): each kind has a few sets of cues from the same
-- family (the slice of a Naytiba's limb, a boss finisher's gore splash, a power hit's blood),
-- one set per event, never one with a cue that played in the last few seconds (a cue that is still playing drops its
-- next start: an arm cut right after a thigh's was silent, sixteenth playtest). The finishers' bass-heavy gore layers
-- (Boss_Gore, Crawler, Quadruped) were too much
local SFX
do -- (a block: the main chunk is near Lua's 200 locals)
local function cue(p) return "/Game/Sound/Character/" .. p .. "." .. p:match("([^/]+)$") end
local L = "Skill/Link/Boss/"
local SLICE_BIG, SLICE_SMALL = cue("Hit/Slice/Mon_slice_Big_Cue"), cue("Hit/Slice/Mon_slice_Small_Cue")
local SPLASH, BLOOD = cue(L .. "PC_LinkAttack_Boss_Gore_Splash_Cue"), cue("Hit/hit_Linkskill_Blood_01_Cue")
-- a smash (tune.gore.smash): a blunt crunch as the blow lands (crunch, at the lethal hit), then the meat bursting out
-- (smash): here the finishers' bass-heavy gore fits
local CRUNCH, THUD = cue("Hit/PCHitSound/Common/CSS_HIT_Blunt_Strong_Common_Cue"), cue("Hit/Result_Hit_Stand_Blunt_StrongAttack_Cue")
local GORE, POWER = cue(L .. "Crawler/PC_LinkAttack_Crawler_Gore_Impact_Cue"), cue("Hit/hit_common_blood_power_00_Cue")
SFX = {
  cut = { { SLICE_BIG }, { SLICE_SMALL }, { SLICE_SMALL, BLOOD } },
  big = { { SLICE_BIG, SPLASH }, { SLICE_SMALL, SPLASH }, { SLICE_BIG, BLOOD } },
  crunch = { { CRUNCH }, { THUD } },
  smash = { { GORE, POWER }, { SPLASH, BLOOD } },
  -- a wound on her (Blood and Dirt, stains.lua): only the wet layer, over the game's own hit sound
  wound = { { BLOOD }, { POWER } },
}
end
local SFX_GAP = 3.0 -- s a cue rests after it played
-- cue path -> os.clock() it last played; any: the last gore sound. Gore sounds are apart s apart at least: a swing
-- cutting a corpse three or four times in a second played each cut's pair of cues over the last (playtest: doubled
-- sounds on enemies)
local sfx_last = { apart = 0.35, any = -1e9 }
-- cue path -> poll window it last started in (ctx.poll, main.lua): never start the same cue twice in one window.
-- Forced layers (a smash's crunch and burst landing together) bypass the apart gate above, and piling simultaneous
-- voices of one cue onto the audio thread coincided with an access-violation crash there (playtest). Audibly this
-- changes nothing: a cue that is still playing drops its restart for SFX_GAP seconds either way.


-- attached: follow comp (at bone, or at world loc / rot when given: KeepWorldPosition), else a one-off at loc
-- a gore sound where it happened (tune.gore.sounds, soundVolume). Every parameter is passed: UE4SS leaves the
-- missing ones at zero, which is a silent volume
-- force: even right after another gore sound (a smash's burst a few frames after its crunch). vol: times
-- soundVolume. aside: neither held back by the other gore sounds nor holding them back (a wound's layer: the cut
-- that may follow it still plays)
local function sfx(kind, pawn, at, force, vol, aside)
  local g = cfg()
  if g.sounds == false or not at then return end
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  if not gs then return end
  -- the sets in random order; the first with no cue still ringing, else the one whose newest cue is the oldest
  local sets, now = SFX[kind] or {}, os.clock()
  if not aside then
    if not force and now - sfx_last.any < sfx_last.apart then
      log(string.format("sound %s: held %.2f s after the last gore sound (apart %.2f s)", kind, now - sfx_last.any, sfx_last.apart))
      return
    end
    sfx_last.any = now
  end
  local order = {}
  for i = 1, #sets do order[i] = i end
  for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
  local pick, pick_age = nil, -1
  for _, i in ipairs(order) do
    local age = math.huge
    for _, path in ipairs(sets[i]) do age = math.min(age, now - (sfx_last[path] or -1e9)) end
    if age >= SFX_GAP then pick = i; break end
    if age > pick_age then pick, pick_age = i, age end
  end
  local played = {}
  local started = sfx_last.started or {}
  sfx_last.started = started
  local window = get_ctx().poll or 0
  local function play(path)
    if not valid(pawn) then return end
    if started[path] == window then
      log(string.format("sound %s: %s already started this window", kind, path:match("([^/.]+)%.[^.]+$") or path))
      return
    end
    local startedAt = os.clock()
    local snd = load_obj(path)
    local loadedAt = os.clock()
    if snd then
      -- no owning actor: the cues' concurrency is per owner, so a cut right after another on her was dropped as the
      -- same sound playing again (leg cuts came out silent, fifteenth playtest)
      local ok, err = pcall(function()
        gs:PlaySoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, (g.soundVolume or 1.0) * (vol or 1),
          0.92 + math.random() * 0.16, 0.0, nil, nil, nil)
      end)
      local endedAt = os.clock()
      if (endedAt - startedAt) * 1000 >= 10 then
        log(string.format("sound timing %s: lookup %.0f ms, play %.0f ms", path:match("([^/.]+)$") or path, (loadedAt - startedAt) * 1000, (endedAt - loadedAt) * 1000))
      end
      if ok then
        sfx_last[path] = now
        started[path] = window
        played[#played + 1] = path:match("([^/.]+)%.[^.]+$") or path
      else
        log("sound " .. path .. ": " .. tostring(err))
      end
    else
      log("sound " .. path .. " didn't load")
    end
  end
  for _, path in ipairs(pick and sets[pick] or {}) do play(path) end
  log(string.format("sound %s: %s", kind, #played > 0 and table.concat(played, ", ") or "none"))
end

return SFX, sfx
end
