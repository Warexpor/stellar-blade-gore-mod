-- Voice state, playback and preload paths.
return function(M, cfg, load_obj, try, valid, log, vec, get_cuts)
-- ---- her voice (tune.gore.voice) ----
-- Eve's own death cry (vo_eve_die_*, SoundWaves under Sound/Dialogue/ActionVoice/Eve, localized like the game's
-- voice), once, the moment she dies. Nothing after: the screams on later cuts and the moans and last breath that
-- followed played on over her body (twentieth playtest). Any death, real or a test key's, starts it (main.lua on_start)
local vox = { last = {} } -- one local for all of it (the chunk is at its 200-local limit)
vox.DIR = "/Game/Sound/Dialogue/ActionVoice/Eve/"
vox.DIE = {}
for i = 1, 5 do
  local n = string.format("vo_eve_die_%02d_VO", i)
  vox.DIE[i] = vox.DIR .. n .. "." .. n
end
-- the recordings to pick from: tune.gore.voice.sounds (names under vox.DIR, e.g. "vo_eve_die_fall_01", or full
-- object paths of any SoundWave or SoundCue, another mod's new ones too), else vox.DIE. A mod that replaces
-- vo_eve_die_* in place is heard with no setting at all
function vox.list(v)
  if type(v.sounds) ~= "table" or #v.sounds == 0 then return vox.DIE end
  local key = table.concat(v.sounds, "|")
  if vox.key ~= key then
    vox.key, vox.paths = key, {}
    for _, s in ipairs(v.sounds) do
      s = tostring(s)
      if s:sub(1, 1) ~= "/" then s = vox.DIR .. s:gsub("_VO$", "") .. "_VO" end
      if not s:find(".", 1, true) then s = s .. "." .. s:match("([^/]+)$") end
      vox.paths[#vox.paths + 1] = s
    end
  end
  return vox.paths
end
vox.ATTENUATION = "/Game/Sound/SoundAsset/Attenuations/Character/PC_ActionVoice.PC_ActionVoice"
-- vox.last: recording -> os.clock() it last played (none twice within voice.rest s)
-- The cry is spawned on her head (it flies with a cut-off head) and kept (vox.ac): a beheading cuts it off as the
-- head comes away (vox.cut), faded over voice.cutFade s so it doesn't end in a click
-- a recording on her head (kept as vox.ac: a beheading cuts it off), else at it: ok, how
function vox.spawn(pawn, mesh, snd, vol)
  local gs = load_obj("/Script/Engine.Default__GameplayStatics")
  local at = valid(mesh) and try(function()
    local x = mesh:GetSocketLocation(FName("Bip001-Head")); return { X = x.X, Y = x.Y, Z = x.Z }
  end) or try(function() local x = pawn:K2_GetActorLocation(); return { X = x.X, Y = x.Y, Z = x.Z } end)
  if not (gs and at) then return false, "nowhere" end
  local pitch, att = 0.97 + math.random() * 0.06, load_obj(vox.ATTENUATION)
  vox.ac = nil
  -- (KeepRelativeOffset 0, stopped if her mesh goes, not auto-destroyed till it ends)
  local ok, ac = pcall(function()
    return gs:SpawnSoundAttached(snd, mesh, FName("Bip001-Head"), vec(0, 0, 0), { Pitch = 0, Yaw = 0, Roll = 0 }, 0, true,
      vol, pitch, 0.0, att, nil, true)
  end)
  local how = "on her head"
  if ok and valid(ac) then vox.ac = ac
  else
    how = "at her head (" .. tostring(ac) .. ")"
    ok, ac = pcall(function()
      return gs:SpawnSoundAtLocation(pawn, snd, vec(at.X, at.Y, at.Z), { Pitch = 0, Yaw = 0, Roll = 0 }, vol, pitch, 0.0, att, nil, true)
    end)
    if ok and valid(ac) then vox.ac = ac end
  end
  return ok, ok and how or (how .. " failed: " .. tostring(ac))
end
-- one of `list` (paths), the one rested longest first: path or nil
function vox.pick(list, rest)
  local now, fresh = os.clock(), {}
  for _, path in ipairs(list) do if now - (vox.last[path] or -1e9) >= rest then fresh[#fresh + 1] = path end end
  if #fresh == 0 then fresh = list end
  return fresh[math.random(#fresh)]
end
-- her recordings as that character (tune.gore.voice.as[who]: die, breaths, moans), set at her death (vox.as), or nil:
-- Eve's. Not with voice.sounds set (a voice of the player's own choosing) or voice.asHer false
function M.voice_as(kind)
  return vox.as and vox.as[kind] or nil
end
function M.voice_death(pawn, mesh)
  local v = cfg().voice or {}
  local who = v.asHer ~= false and (type(v.sounds) ~= "table" or #v.sounds == 0) and M.looks_as(pawn, mesh) or nil
  vox.as = who and type(v.as) == "table" and v.as[who] or nil
  if vox.as then log("voice: she looks like " .. who .. ": her own recordings") end
  if v.enabled == false or v.cry == false then return end
  local list = vox.as and type(vox.as.die) == "table" and #vox.as.die > 0 and vox.list({ sounds = vox.as.die }) or vox.list(v)
  local path = vox.pick(list, v.rest or 8)
  local snd = path and load_obj(path)
  if not snd then log("voice: " .. tostring(path) .. " didn't load"); return end
  local vol = v.volume or 1.0
  local ok, how = vox.spawn(pawn, mesh, snd, vol)
  local now = os.clock()
  if ok then vox.last[path], vox.t = now, now end
  log(string.format("voice: %s at %.2f %s", path:match("([^/.]+)$") or path, vol, how))
  -- A lethal smash can finish before the death broadcast starts her cry. Apply the same cutoff then too;
  -- ordinary cuts keep their existing timing (only a beheading cuts the voice).
  local ma = try(function() return mesh:GetAddress() end)
  for _, c in ipairs(get_cuts()) do
    if c.addr == ma and c.smashed and (c.bone == "Bip001-Head" or c.bone == "Bip001-Spine1") then vox.cut(); break end
  end
end
-- a quiet sound of hers while she convulses (convulse.lua: a moan with a spasm, a breath with a gasp): names under
-- vox.DIR or full paths; the name played, or nil. Never while her cry still sounds, nor once her head is off
function M.voice_soft(pawn, mesh, names, vol)
  if (cfg().voice or {}).enabled == false or type(names) ~= "table" or #names == 0 then return nil end
  if M.already_cut(mesh, "Bip001-Head") or M.smashed.has(mesh, "Bip001-Spine1") then return nil end
  if valid(vox.ac) and try(function() return vox.ac:IsPlaying() end) then return nil end
  local list = {}
  for _, s in ipairs(names) do
    s = tostring(s)
    if s:sub(1, 1) ~= "/" then s = vox.DIR .. s:gsub("_VO$", "") .. "_VO" end
    if not s:find(".", 1, true) then s = s .. "." .. s:match("([^/]+)$") end
    list[#list + 1] = s
  end
  local path = vox.pick(list, 6)
  local snd = load_obj(path)
  if not snd then return nil end
  local ok = vox.spawn(pawn, mesh, snd, vol)
  if not ok then return nil end
  local now = os.clock()
  vox.last[path], vox.t = now, now
  return path:match("([^/.]+)$") or path
end
-- her head came off: the cry, if it still sounds, fades out fast (a beheading is instant). A sharp stop clicked
function vox.cut()
  local ac = vox.ac
  if not valid(ac) or not try(function() return ac:IsPlaying() end) then return end
  local d = (cfg().voice or {}).cutFade or 0.08
  -- (Sin: EAudioFaderCurve 3, smooth at both ends)
  local ok = pcall(function() ac:FadeOut(d, 0.0, 3) end) or pcall(function() ac:FadeOut(d, 0.0) end)
  log(string.format("voice: cut off %.2f s in as her head came off (%.2f s fade%s)", os.clock() - (vox.t or 0), d, ok and "" or ", failed"))
end


return vox
end
