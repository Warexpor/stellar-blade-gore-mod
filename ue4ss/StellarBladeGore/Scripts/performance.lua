-- Frame diagnostics and the guarded engine garbage-collection probe.
return function(screen, goreCtx, valid, try, log, get_active, get_tune, get_pawn)
-- slow ticks and frame hitches: each one with verboseLog, else one line a minute with how many and the worst of each
-- (one line per hitch was a sixth of the log)
screen.perf = { t = os.clock(), slow = { n = 0, ms = 0 }, hitch = { n = 0, ms = 0 } }
-- (in a death's first DEATH_S s each one at once, with how far into it: the minute's line was lost to a quit before
-- it, a death's hitch that put the cut after her turn as she fell untold, playtest)
screen.DEATH_S = 6
function screen.perf_note(kind, ms, line)
  local into = get_active() and screen.deathAt and os.clock() - screen.deathAt
  if get_tune().verboseLog or (into and into < screen.DEATH_S) then
    log(into and string.format("%s (%.2f s into the death)", line, into) or line); return
  end
  local k = screen.perf[kind]
  k.n = k.n + 1
  if ms > k.ms then k.ms, k.line = ms, line end
end
-- the engine's garbage collection: a probe object nothing holds, in the transient package; once a find by its path
-- misses, a GC pass has run (a find is a hash lookup, the freed object is never read). Each frame hitch says whether
-- one ran in its frame, and the minute's line how many ran and how many hitches had one: half-second game-thread
-- stalls with no disk or memory pressure were seen in vanilla too, and GC is the suspect (gc = { path, n, runs, hit })
screen.gc = { n = 0, runs = 0, hit = 0 }
screen.GC_S = 0.25
function screen.gc_ran(now_too)
  local g = screen.gc
  if g.off then return false end
  -- The probe makes synchronous native lifetime requests. Do not add those round
  -- trips to the busiest frames of a death, including the hitch-triggered probes.
  if get_active() and screen.deathAt and os.clock() - screen.deathAt < screen.DEATH_S then return false end
  -- looked at every GC_S s, and in a hitch's frame (each frame cost too much: 15 fps, playtest)
  local now = os.clock()
  if not now_too and now < (g.next or 0) then return false end
  g.next = now + screen.GC_S
  local gm = goreCtx.gore
  if not (gm and gm.native_ready and gm.native_ready()) then return false end
  -- asked of sbslice by its index ("G", as goreCtx.held), never read: UE4SS's StaticFindObject finds no subobject by
  -- its path (".../GameEngine_X:SBGameInstance_Y.SBGore_GCProbe1": "not found by its path", playtest)
  local k = g.k
  if k then
    if not goreCtx.alive_ask({ k }) then return false end
    if k.alive then return false end
    g.runs = g.runs + 1
  end
  -- (in the game instance, as the menu's widgets. An outer doesn't hold what is in it, so the probe still goes at
  -- the next pass)
  g.cls = valid(g.cls) and g.cls or try(function() return StaticFindObject("/Script/CoreUObject.Object") end)
  g.outer = valid(g.outer) and g.outer or try(function() return FindFirstOf("GameInstance") end)
  g.k = nil
  local why = not valid(g.cls) and "no Object class" or not valid(g.outer) and "no game instance"
  if not why then
    g.n = g.n + 1
    local o = try(function() return StaticConstructObject(g.cls, g.outer, FName("SBGore_GCProbe" .. g.n)) end)
    g.k = valid(o) and goreCtx.keep(o) or nil
    -- its index read now, while it is surely alive; alive at once, or the probe would read a pass every look
    if not g.k then why = "not made"
    elseif not goreCtx.alive_ask({ g.k }) then g.k = nil; return k ~= nil -- sbslice not up yet: made again next look
    elseif not g.k.alive then why = "not alive as it was made" end
  end
  -- a probe that can't be made is given up (one line), not tried again every look
  if why then g.off, g.k = true, nil; log("garbage collection probe: " .. why .. ", off") end
  return k ~= nil
end
-- fewer garbage collection passes (tune.fewerGC): the engine forces a pass each time a streamed level goes out, and
-- keeps incremental passes going while one waits to be purged. 9 passes a minute were counted, against the 61 s
-- timer, with the worst hitch of that minute (1296 ms) in one (playtest). Both are turned off; the timed pass still
-- runs, so nothing piles up past a minute. Each cvar's own value is read first and put back when the option goes off
-- (checked at the start and once a minute, so the menu's switch takes effect within a minute)
screen.GC_CVARS = { "s.ForceGCAfterLevelStreamedOut", "s.ContinuouslyIncrementalGCWhileLevelsPendingPurge" }
function screen.gc_tune()
  local want = get_tune().fewerGC == true
  local g = screen.gc
  if (g.tuned or false) == want then return end
  local pawn = get_pawn()
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  if not (valid(pawn) and valid(ksl)) then return end
  g.was = g.was or {}
  local out = {}
  for _, cv in ipairs(screen.GC_CVARS) do
    local cur = try(function() return ksl:GetConsoleVariableIntValue(cv) end)
    if want and g.was[cv] == nil then g.was[cv] = cur or 1 end
    local to = want and 0 or (g.was[cv] or 1)
    local ok = screen.console(pawn, string.format("%s %d", cv, to))
    local now = try(function() return ksl:GetConsoleVariableIntValue(cv) end)
    out[#out + 1] = string.format("%s %s -> %s%s", cv, tostring(cur), tostring(now), ok and "" or " (not run)")
  end
  g.tuned = want
  log(string.format("garbage collection: %s: %s", want and "fewer passes" or "the game's own passes", table.concat(out, ", ")))
end
function screen.perf_flush()
  local p = screen.perf
  if os.clock() - p.t < 60 then return end
  p.t = os.clock()
  screen.gc_tune()
  for _, kind in ipairs({ "slow", "hitch" }) do
    local k = p[kind]
    if k.n > 0 then log(string.format("%d %s in the last minute, the worst %s", k.n, kind == "slow" and "slow ticks" or "frame hitches", k.line)) end
    p[kind] = { n = 0, ms = 0 }
  end
  local g = screen.gc
  log(string.format("garbage collection: %d runs in the last minute, %d of them in a frame hitch%s", g.runs, g.hit,
    g.off and " (no probe: can't tell)" or ""))
  g.runs, g.hit = 0, 0
end
end
