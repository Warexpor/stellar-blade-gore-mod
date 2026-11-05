-- Manual slow motion (tune.manualSlowmo, the Slow Motion key): run the game slower at the death slow
-- motion's speed till the key is pressed again. The caller owns the actual time control; this only decides
-- when (off unless enabled, and the speed is deathSlowmo's).
return function(get_tune, log)
  local M = { _on = false }
  local function speed()
    local d = (get_tune() or {}).deathSlowmo or {}
    local k = tonumber(d.speed) or 0.15
    if not (k > 0 and k < 1) then
      log(string.format("slow motion: speed %.2f out of range", k))
      return nil
    end
    return k
  end
  function M.enabled() return ((get_tune() or {}).manualSlowmo or {}).enabled == true end
  function M.running() return M._on == true end
  function M.speed() return M._on and speed() or nil end
  -- the key: on or off, returning the speed to run at (always 1 going off). On needs the feature and a
  -- usable speed; off always takes
  function M.toggle()
    if M._on then M._on = false; return 1 end
    if not M.enabled() then return nil end
    local k = speed()
    if not k then return nil end
    M._on = true
    return k
  end
  function M.reset() M._on = false end
  return M
end
