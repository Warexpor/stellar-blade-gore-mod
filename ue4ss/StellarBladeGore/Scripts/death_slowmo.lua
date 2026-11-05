-- Slow-motion death effect: briefly run the game slower when she dies so the damage
-- reads, then hand time back well before the death screen. The caller owns the
-- shared ahead clock and the actual time control; this only decides when.
return function(get_tune, clock, log)
  local M = { k = nil, t0 = 0, dur = 0 }
  local function cfg()
    local t = get_tune() or {}
    return t.deathSlowmo or {}
  end
  function M.start()
    if M.k ~= nil then return nil end
    local c = cfg()
    if c.enabled ~= true then return nil end
    local k = tonumber(c.speed) or 0.3
    if not (k > 0.05 and k < 0.99) then
      log(string.format("death: slow motion off: speed %.2f out of range", k))
      return nil
    end
    local dur = tonumber(c.duration) or 2.5
    if not (dur >= 0.5 and dur <= 8) then
      log(string.format("death: slow motion off: duration %.1f s out of range", dur))
      return nil
    end
    M.k, M.t0, M.dur = k, clock(), dur
    return k
  end
  function M.running() return M.k ~= nil end
  function M.speed() return M.k end
  function M.elapsed() return clock() - M.t0 end
  function M.done() return M.k ~= nil and M.elapsed() >= M.dur end
  -- stops the effect, restoring full speed through the caller's setter; true when it was running
  function M.stop(why, set_full)
    if M.k == nil then return false end
    local k, after = M.k, M.elapsed()
    M.k, M.t0, M.dur = nil, 0, 0
    if set_full then set_full() end
    log(string.format("death: slow motion x%.2f off after %.1f s (%s)", k, after, why))
    return true
  end
  return M
end
