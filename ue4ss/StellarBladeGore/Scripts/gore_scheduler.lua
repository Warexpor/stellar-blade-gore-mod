-- Frame scheduler for cut stages and delayed impact work.
return function(M, enemy, cfg, get_guards, get_queues, get_pending, set_pending, owner_of, stage_tick, release_lods, log)
-- the cut's stages, one a frame (main.lua calls this every frame, ahead of her mesh's tick; q.wait counts frames).
-- On the 33 ms poll they were a tick each and the piece came off 350 ms after the killing blow, which read as a long
-- delay between the hit and the cut (playtest); a frame each still keeps every stage's work in a frame of its own
function M.pump()
  local later, bleeds, cuts, queued, pending = get_queues()
  -- A multi-cut can keep pending/queued busy for hundreds of ms. Play an opening's sound on the next
  -- render frame, ahead of blood/meat work and further cuts, rather than waiting for the whole blow.
  if cfg().enabled ~= false and not M.pumping then
    for i, l in ipairs(later) do
      if l.n <= 0 and l.label == "cut sound" then
        table.remove(later, i)
        local t0 = os.clock()
        local ok, err = pcall(enemy.run, owner_of(l), l.fn)
        local ms = (os.clock() - t0) * 1000
        if ms >= 10 then log(string.format("delayed step cut sound took %.0f ms", ms)) end
        if not ok then log("delayed step failed: " .. tostring(err)) end
        return -- Audio and cut/copy/effect work each keep a frame of their own.
      end
    end
  end
  local copiesDue = cfg().enabled ~= false and #cuts > 0 and not M.pumping
    and (os.clock() >= M.copies.next or next(M.copies.dirty) ~= nil)
  if cfg().enabled ~= false and #cuts > 0 and not M.pumping then
    local copyStart = copiesDue and os.clock()
    local ok, err = pcall(M.copies_flush)
    local copyMs = copyStart and (os.clock() - copyStart) * 1000
    if copyMs and copyMs >= (cfg().slowMs or 15) then
      log(string.format("copy refresh took %.0f ms (%d cuts, pending stage %s)", copyMs, #cuts,
        pending and tostring(pending.stage) or "none"))
    end
    if not ok then log("copies: " .. tostring(err)) end
    later, bleeds, cuts, queued, pending = get_queues()
  end
  if cfg().enabled ~= false and not copiesDue and not pending and #queued == 0 and not M.pumping then
    -- One costly ready effect per frame, FIFO. Do not overlap a cut stage or copy refresh with it.
    local serviced = false
    for i, l in ipairs(later) do
      if l.n <= 0 and M.impactSteps[l.label] then
        table.remove(later, i)
        local t0 = os.clock()
        local ok, err = pcall(enemy.run, owner_of(l), l.fn)
        local ms = (os.clock() - t0) * 1000
        if ms >= 10 then log(string.format("delayed step %s took %.0f ms", l.label or "other", ms)) end
        if not ok then log("delayed step failed: " .. tostring(err)) end
        serviced = true
        later, bleeds, cuts, queued, pending = get_queues()
        break
      end
    end
    if not serviced then
      -- Rotate through ready openings: one restart per frame, no repeated floor traces or new components.
      local count = #bleeds
      for offset = 1, count do
        local index = ((M.bleedCursor or 0) + offset - 1) % count + 1
        local b = bleeds[index]
        if (b.ready or 0) > 0 then
          b.ready = b.ready - 1
          M.bleedCursor = index
          local try, valid = get_guards()
          if valid(b.comp) then
            try(function() b.comp:ResetSystem() end)
            later, bleeds, cuts, queued, pending = get_queues()
          end
          break
        end
      end
    end
  end
  if cfg().enabled == false or (not pending and #queued == 0) or M.pumping then return end
  -- (a queued cut started from here runs its first stage below, not inside its start: a stage a frame)
  M.pumping = true
  local ok0, err0 = pcall(M.pump_once)
  M.pumping = false
  if not ok0 then error(err0, 0) end
end
function M.pump_once()
  local _, _, _, queued, pending = get_queues()
  if not pending and #queued > 0 then
    -- a few frames between one cut of the blow and the next: the engine's weight override waits on the render
    -- thread, still busy with the cut before (a waist cut right after a thigh's held the frame 126 ms, playtest)
    if (M.queue_gap or 0) > 0 then M.queue_gap = M.queue_gap - 1; return end
    M.queue_gap = cfg().queueGap or 1
    local nx = table.remove(queued, 1)
    local ok, err = pcall(enemy.run, owner_of(nx), nx)
    if not ok then log("next cut of the blow failed: " .. tostring(err)) end
  end
  local q = get_pending()
  if not q then return end
  local _, valid = get_guards()
  if not valid(q.mesh) then set_pending(nil); return end
  if q.wait > 0 then q.wait = q.wait - 1; return end
  -- and the next stage in the same frame while the stages so far left room (under half of stageBudgetMs): a cut's
  -- six stages a frame each, the piece came off 32-63 ms after the blow (playtest). Never past the cut itself or a
  -- chain's cut (sbslice.dll's work and the engine's weights, the heavy ones), nor a split's stages, nor a wait
  local t0, budget, n = os.clock(), (cfg().stageBudgetMs or 8) / 1000, 0
  while true do
    local stage = q.stage
    -- a stage that throws would run again on every frame and block every later cut: it ends the cut instead
    local ok, err = xpcall(enemy.run, debug and debug.traceback or tostring, q.owner, stage_tick, q)
    if not ok then
      if get_pending() == q then set_pending(nil) end
      release_lods()
      log(string.format("%s (%s) failed at stage %s, dropped: %s", q.kind, q.why, tostring(q.stage), tostring(err)))
      return
    end
    n = n + 1
    if get_pending() ~= q or q.wait > 0 or q.kind == "split" or budget <= 0 or not M.CHAINED[stage] or not M.CHAINED[q.stage]
      or (os.clock() - t0) * 2 > budget or n >= 6 or not valid(q.mesh) then return end
  end
end
M.CHAINED = { caps = true, caps2 = true, stubs = true, stubs2 = true, open = true }

end
