-- Spine anchors available to each split half and its bending lid.
local SPLIT_RIDE = { "Bip001-Head", "Bip001-Neck", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Spine", "Bip001-Pelvis" }
-- the ones a half's lid and sheet may ride: never a bone that half lets go of (settle_half: the copy's head, the
-- other end of a broken spine), which falls free and spins, and the lid stretched after it in tall flashing sheets
-- (ragdoll deaths, playtest 26). q.spine: where the spine breaks (her half keeps it and what is above it); q.spine2:
-- where the copy's does (it lets go of that and what is above it)
function SPLIT_RIDE.of(q, comp)
  local copy = comp ~= q.mesh
  local s, si, list = copy and (q.spine2 or q.spine) or q.spine, nil, {}
  for i, b in ipairs(SPLIT_RIDE) do if b == s then si = i end end
  for i, b in ipairs(SPLIT_RIDE) do
    local ok = not si or (copy and i > si) or (not copy and i <= si)
    if copy and b == "Bip001-Head" and not (q.spine and q.spine ~= b) then ok = false end
    if ok then list[#list + 1] = b end
  end
  return #list > 0 and list or SPLIT_RIDE
end
-- the ones a half's lid bends with, and the sheet behind it (sbslice's bands): never the head. The points by the neck
-- turned fully with it, and as the head flopped in her ragdoll they fanned out of her in long spikes, where the
-- neck's skin follows it only in part (playtest)
function SPLIT_RIDE.lid(q, comp)
  local list = {}
  for _, b in ipairs(SPLIT_RIDE.of(q, comp)) do if b ~= "Bip001-Head" then list[#list + 1] = b end end
  return #list > 0 and list or SPLIT_RIDE.of(q, comp)
end

return SPLIT_RIDE
