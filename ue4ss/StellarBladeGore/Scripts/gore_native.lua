-- Native command dispatch and startup handshake.
return function(M, native, cfg, load_obj, vec, mark, log, read_file, CHEAT_CDO, get_ctx, get_guards, get_cuts)
local UFUNC = "/Script/SB.SBCheatManager:SBRewardGroupDropFormationPathLocation"
local REQ = "ue4ss/Mods/StellarBladeGore/sbslice.req"
local OK = "ue4ss/Mods/StellarBladeGore/sbslice.ok"
local ERR = "ue4ss/Mods/StellarBladeGore/sbslice.err"
local RESULT = "ue4ss/Mods/StellarBladeGore/sbslice.cut"
local function file_exists(p) local f = io.open(p, "r"); if f then f:close(); return true end; return false end
-- a stump seam is weighted to a helper, and that helper keeps moving after the cut (a thigh twist, Ab-AX3T, a knee
-- driver): the opening's point swings out and the cut face cones. "H" rewrites the collapse point onto the rim's bone.
-- No result file — reading one every frame is what stuttered. Her own tick calls this, before the mesh is posed.
-- The cheat CDO it calls on is kept in native.hold_cdo (this chunk is at Lua's 200-local limit)
function M.hold_seams()
  if native.state ~= "ready" then return end
  local cuts = get_cuts()
  if #cuts == 0 then return end
  local try, valid = get_guards()
  local ok, err = pcall(function()
    local list = {}
    for _, c in ipairs(cuts) do
      if valid(c.mesh) and try(function() return c.mesh:GetAddress() end) == c.addr then list[#list + 1] = string.format("%x", c.addr) end
    end
    if #list == 0 then return end
    if not valid(native.hold_cdo) then native.hold_cdo = load_obj(CHEAT_CDO) end
    if not native.hold_cdo then return end
    native.hold_cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, "H" .. table.concat(list, ","), 0, 0, 0)
  end)
  if not ok then native.hold_cdo = nil; log("seam hold failed: " .. tostring(err)) end
end

-- a command with no answer file (active.lua's eased grip, sent every tick: reading an answer each time stuttered)
function M.fire(s)
  if native.state ~= "ready" then return end
  local _, valid = get_guards()
  local ok, err = pcall(function()
    if not valid(native.hold_cdo) then native.hold_cdo = load_obj(CHEAT_CDO) end
    if native.hold_cdo then native.hold_cdo:SBRewardGroupDropFormationPathLocation(FName("None"), 0, 0, 0, s, 0, 0, 0) end
  end)
  if not ok then native.hold_cdo = nil; log("sbslice " .. s:sub(1, 1) .. " failed: " .. tostring(err)) end
end

-- one command to sbslice.dll (see exec_slice there); the answer it leaves in sbslice.cut
local function command(s, p, n)
  mark("lua")
  os.remove(RESULT)
  local cdo = load_obj(CHEAT_CDO)
  if not cdo then return "err no cheat manager" end
  p, n = p or vec(0, 0, 0), n or vec(0, 0, 0)
  local t0 = os.clock()
  local ok, err = pcall(function()
    cdo:SBRewardGroupDropFormationPathLocation(FName("None"), p.X, p.Y, p.Z, s, n.X, n.Y, n.Z)
  end)
  -- a command that holds the game thread long enough to show as a stutter (the split's, eighteenth playtest)
  local ms = (os.clock() - t0) * 1000
  if ms >= (cfg().slowMs or 15) then log(string.format("sbslice %s took %.0f ms", s:sub(1, 1), ms)) end
  mark("sbslice " .. s:sub(1, 1))
  if not ok then return "err call: " .. tostring(err) end
  local r = read_file(RESULT) or "err no answer"
  -- a cut mesh's copies (M.copies) take its new weights at the end of the frame's stage, and lose them with its own
  local k = s:sub(1, 1)
  if (k == "c" or k == "x") and r:sub(1, 2) == "ok" and M.copies then
    local a = tonumber(s:match("^.(%x+)") or "", 16)
    if a and k == "c" then M.copies.dirty[a] = true elseif a then M.copies_clear(a) end
  end
  return r
end

-- handshake with sbslice.dll: hand it the UFunction to repoint, then wait for its answer
local function native_tick()
  if native.state == "ready" or native.state == "failed" then return end
  local ctx = get_ctx()
  local try, valid = get_guards()
  if native.state == "init" then
    os.remove(OK); os.remove(ERR)
    -- what sbslice.dll noted as the last session ended: a command that never finished, a crash in it or in a command
    -- (no local of its own: this chunk is at Lua's 200-local limit)
    for _, p in ipairs({ "ue4ss/Mods/StellarBladeGore/sbslice.stuck", "ue4ss/Mods/StellarBladeGore/sbslice.crash" }) do
      local note = read_file(p)
      if note then log("sbslice.dll last session: " .. note); os.remove(p) end
    end
    -- (and its own start: written from its DllMain, by its own path, for a launch that closed before the first window)
    log("sbslice.dll " .. tostring(read_file("ue4ss/Mods/StellarBladeGore/sbslice.boot") or "boot: no note (an older sbslice.dll?)"))
    local f = try(function() return StaticFindObject(UFUNC) end)
    if not valid(f) then native.state = "failed"; log("no " .. UFUNC); return end
    -- (written whole, then renamed in: the DLL polls for it and could read it half written)
    local w = io.open(REQ .. ".tmp", "w")
    if not w then native.state = "failed"; log("cannot write " .. REQ); return end
    w:write(string.format("%x", f:GetAddress())); w:close()
    os.remove(REQ)
    if not os.rename(REQ .. ".tmp", REQ) then native.state = "failed"; log("cannot write " .. REQ); return end
    native.state = "waiting"
    log(string.format("asked sbslice.dll to take over %s (UFunction %x)", UFUNC, f:GetAddress()))
    return
  end
  native.waited = native.waited + 1
  if file_exists(OK) then
    native.state = "ready"
    local ok = tostring(read_file(OK))
    -- every outfit keeps its LOD0 CPU copy (the DLL's NeedCPUData patch): physfix stops warning about the flag
    ctx.cpu_forced = ok:find("cpu copy LOD0 on", 1, true) ~= nil
    -- a reloaded script forgets its cuts, the DLL doesn't: put back anything a previous run left collapsed
    log("sbslice.dll ready: " .. ok .. ", leftovers: " .. command("r"))
  elseif file_exists(ERR) then
    native.state = "failed"
    local e = tostring(read_file(ERR))
    -- (its engine calls are at fixed addresses in the exe: another build of the game, a patch or a modified exe, has
    -- them elsewhere, and the first one isn't found)
    log("sbslice.dll refused: " .. e .. (e:find("no thunk pointer", 1, true)
      and " (this game exe isn't the Steam build sbslice.dll was made for: no cuts, and no outfit physics fix)" or ""))
  elseif native.waited > 150 then
    native.state = "failed"
    log("sbslice.dll did not answer (is Mods/SBSlice/dlls/main.dll installed, with Mods/SBSlice/enabled.txt or SBSlice : 1 in mods.txt?)")
  end
end

return command, native_tick
end
