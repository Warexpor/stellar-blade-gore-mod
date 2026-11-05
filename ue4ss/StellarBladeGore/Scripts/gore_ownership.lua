-- Ownership tagging and guarded access to enemy-owned effects.
return function(enemy, M, get_ctx, get_valid, get_lists)
-- run fn(...) cutting for owner (an enemy's address, nil for Eve): whatever it adds to the lists is tagged with it
function enemy.run(owner, fn, ...)
  local prev = enemy.cur
  enemy.cur = owner
  local lists = get_lists()
  local n0 = {}
  for i, l in ipairs(lists) do n0[i] = #l end
  local r = table.pack(pcall(fn, ...))
  for i, l in ipairs(lists) do
    for k = n0[i] + 1, #l do
      local x = l[k]
      if enemy.owned[x] == nil then
        enemy.owned[x] = owner or false
        -- an object on an enemy goes with its actor, freed by the game unseen: kept to be checked safely (enemy.alive),
        -- its index taken now (held reads it only within keepFresh s of keep: the caps, first checked at the dissolve
        -- seconds later, read as gone and were left up long after the corpse, playtest)
        if owner and type(x) == "userdata" then
          local ctx = get_ctx()
          local k = ctx.keep(x)
          enemy.kept[x] = k
          if k then ctx.held(k) end
        end
      end
    end
  end
  enemy.cur = prev
  -- a cut that finished opening on a corpse already dissolving: its caps and bleeds go at once (they stayed in the
  -- air where it had been until it went back to its pool, playtest: leftover covers)
  if owner and enemy.faded[owner] then M.enemy_fading(owner, true) end
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end
function enemy.owner_of(x) return enemy.owned[x] or nil end
-- valid() for an object tagged to an enemy: never read once the game may have freed it (main.lua held)
function enemy.alive(x)
  local ctx, valid = get_ctx(), get_valid()
  local k = enemy.kept[x]
  if k then return ctx.held(k) end
  return not enemy.owned[x] and valid(x)
end

end
