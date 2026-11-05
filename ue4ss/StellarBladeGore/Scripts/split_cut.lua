-- Staged split preparation and native cuts; the owning lifecycle handles rollback and later opening.
return function(M, d)
local cfg, addr, face_of, clone_of, log = d.cfg, d.addr, d.face_of, d.clone_of, d.log
local bone_loc, spine_break, split_plane, body_frame, from_body = d.bone_loc, d.spine_break, d.split_plane, d.body_frame, d.from_body
local add, sub, scale, norm, len, dot = d.add, d.sub, d.scale, d.norm, d.len, d.dot
local limb_sides, place_like, command, enemy, split_chains = d.limb_sides, d.place_like, d.command, d.enemy, d.split_chains
local send_limbs, send_neck, side_cut, SPLIT_RIDE, SPLIT_SINK = d.send_limbs, d.send_neck, d.side_cut, d.SPLIT_RIDE, d.SPLIT_SINK
local ok_cut, num = d.ok_cut, d.num
local function v3(...) return d.v3()(...) end
local function stage_split_prep(q)
  q.armcuts = {}
  for _, c in ipairs(d.cuts()) do
    if c.addr == addr(q.mesh) then
      if not M.ARM_CUTS[c.bone] or cfg().splitArms == false then log("split skipped (" .. q.why .. "): she has been cut already"); return false end
      q.armcuts[#q.armcuts + 1] = c
    end
  end
  q.face = face_of(q.pawn, q.mesh)
  q.body2 = clone_of(q.pawn, q.mesh)
  if not q.body2 then log("split skipped: could not clone the body"); return false end
  if cfg().splitRigOff ~= false then
    log(string.format("split: the rig's post-process AnimBP off: hers %s, the copy's %s",
      M.rig(q.mesh, false) and "ok" or "failed", M.rig(q.body2, false) and "ok" or "failed"))
  end
  return true
end

local function stage_split_cut(q)
  local at, n, from
  if q.plane and q.plane.diag then
    local deg, lift, hip
    at, n, deg, lift, hip = M.diag_plane(q.mesh, q.plane.diag, true)
    if at then
      from = string.format("diagonal from over her %s shoulder, %.0f deg off her spine (%.1f cm over the shoulder, %.1f over the hip)",
        q.plane.diag == "R" and "right" or "left", deg, lift, hip)
      q.spine = spine_break(q.mesh, at, n)
    end
  elseif q.plane then
    at, n, from = q.plane.at, q.plane.n, "blade"
    local f = q.plane.rel and body_frame(q.mesh)
    if f then
      at, n = add(f.o, from_body(f, q.plane.rel.at)), norm(from_body(f, q.plane.rel.n)) or n
      from = string.format("blade, followed her %.0f cm", len(sub(at, q.plane.at)))
    end
    local head = bone_loc(q.mesh, "Bip001-Head")
    if head and dot(sub(head, at), n) < 0 then n = scale(n, -1) end
    -- a waist split keeps both arms on her half and gives both legs to the copy: in an animated fall the
    -- plane square to her lower spine ran flat through her bent hips, a thigh each side, and her half's chest flew
    -- off its pelvis stretching 3.7 m of skin (playtest 42). Squared again from her hips to her chest as she is now,
    -- else a waist cut
    if q.plane.waist and not M.waist_sides(q.mesh, at, n) then
      local a, b, c = bone_loc(q.mesh, "Bip001-Spine"), bone_loc(q.mesh, "Bip001-Spine1"), bone_loc(q.mesh, "Bip001-Spine2")
      local l, r = bone_loc(q.mesh, "Bip001-L-Thigh"), bone_loc(q.mesh, "Bip001-R-Thigh")
      local n2 = c and l and r and norm(sub(c, scale(add(l, r), 0.5)))
      if a and b and n2 and M.waist_sides(q.mesh, add(a, scale(sub(b, a), 0.4)), n2) then
        at, n, from = add(a, scale(sub(b, a), 0.4)), n2, from .. ", squared to her hips"
      else
        log(string.format("split (%s): the waist plane puts a leg or an arm on the wrong half: a waist cut instead", q.why))
        q.degenerate = true
        return false
      end
    end
    q.spine = spine_break(q.mesh, at, n)
  else
    at, n, from = split_plane(q)
    -- the head on her half's side (a leaned plane runs past it)
    local head = at and bone_loc(q.mesh, "Bip001-Head")
    if head and dot(sub(head, at), n) < 0 then n = scale(n, -1) end
    if at then q.spine = spine_break(q.mesh, at, n) end
  end
  if not at then log("split skipped: no bone transforms"); return false end
  q.c = { at = at, n = n }
  q.gone1, q.gone2 = limb_sides(q.mesh, at, n)
  q.spine = M.her_break(q.mesh, q.spine, q.gone2)
  q.spine2 = M.copy_break(q.mesh, q.spine, q.gone1)
  place_like(q.body2, q.mesh)
  local p = command(string.format("p%x,%x", q.mesh:GetAddress(), q.body2:GetAddress()))
  local neg = scale(n, -1)
  -- recorded before they are checked, so a failed half is undone with the rest
  -- her arm cuts before it: her weights and the sinks saved ("S": a split that fails puts them back, "R"; "x" would take
  -- the arm cuts with it), and the copy cut from her weights ("y"), the stump and the flying arm in them. Cut from the
  -- mesh's own, the copy's half put the arm's seam back on the shoulder, stretched out to where the arm flew (harness)
  local saved = false
  if #q.armcuts > 0 then
    local sv = command(string.format("S%x,0", q.mesh:GetAddress()))
    saved = sv:sub(1, 2) == "ok"
    local cp = saved and command(string.format("y%x,0,%x", q.mesh:GetAddress(), q.body2:GetAddress())) or "not saved"
    local names = {}
    for _, c in ipairs(q.armcuts) do names[#names + 1] = c.bone end
    log(string.format("split after the arm cut%s (%s): her weights %s, on the copy %s", #names > 1 and "s" or "", table.concat(names, ", "), sv, cp))
    if cp:sub(1, 9) ~= "ok copied" then
      if saved then command(string.format("R%x,0", q.mesh:GetAddress())) end
      log("split skipped: the copy can't take her cut weights")
      return false
    end
  end
  d.add_cut({ mesh = q.mesh, addr = addr(q.mesh), bone = "split", saved = saved or nil, copy = saved and addr(q.body2) or nil,
    sm = enemy.asset(q.mesh) })
  d.add_cut({ mesh = q.body2, addr = addr(q.body2), bone = "split copy", sm = enemy.asset(q.body2) })
  M.wedding_cloth(q.mesh)
  M.wedding_cloth(q.body2)
  -- each half keeps the limbs on its side whole and lets the others go; the halves share the mesh's sinks, and each
  -- half's skin lets go of every helper past the plane, so the other half's sinks never pull on it (q.gone1, q.gone2:
  -- limb_sides, above)
  -- her half keeps the head, face and hair whole, on their own animation; the copy's neck closes. The DLL holds one
  -- neck plane, for the next split cut of that component
  local front, back = split_chains(q.mesh, at, n, q.gone1)
  local keep1, keep2 = {}, {}
  for _, b in ipairs(q.gone2) do keep1[#keep1 + 1] = b end
  for _, b in ipairs(front) do keep1[#keep1 + 1] = b end
  for _, b in ipairs(q.gone1) do keep2[#keep2 + 1] = b end
  for _, b in ipairs(back) do keep2[#keep2 + 1] = b end
  send_limbs(q.mesh, q.gone1, keep1, back, SPLIT_RIDE.lid(q, q.mesh), q.spine, true)
  local h1 = send_neck(q.mesh, 1)
  local r1 = side_cut(q.mesh, SPLIT_SINK, at, n, q.gone1)
  -- her spine as her half was cut: the lid's points are placed against it (skin_lid), as sbslice placed the sheet.
  -- Noted a frame later with the copy's, an animated fall had moved her on and the lid sat off the sheet
  q.posed1 = M.snap({ { q.mesh, { "Bip001-Neck", table.unpack(SPLIT_RIDE.of(q, q.mesh)) } } })
  -- the copy's cut the next tick (M.stage_split_copy): each cut is the engine building a new skin weight buffer,
  -- 15-30 ms, and the two in one frame were a stutter at the death (playtest 41). She is held still meanwhile, and
  -- the new weights show nothing till the opening
  q.cut1 = { from = from, p = p, h1 = h1, r1 = r1, front = front, back = back, keep2 = keep2, neg = neg }
  return true
end
function M.stage_split_copy(q)
  local c1 = q.cut1
  q.cut1 = nil
  local at, n, from, p, h1, r1, front, back = q.c.at, q.c.n, c1.from, c1.p, c1.h1, c1.r1, c1.front, c1.back
  send_limbs(q.body2, q.gone2, c1.keep2, front, SPLIT_RIDE.lid(q, q.body2), q.spine2, false)
  local h2 = send_neck(q.body2, 2)
  local r2 = side_cut(q.body2, SPLIT_SINK, at, c1.neg, q.gone2)
  log(string.format("split (%s) at %s normal %s (%s), pose %s, limbs %s | %s, chains %s | %s, spine breaks at %s, neck %s | %s",
    q.why, v3(at), v3(n), from, p, table.concat(q.gone2, ","), table.concat(q.gone1, ","), table.concat(front, ","),
    table.concat(back, ","), tostring(q.spine) .. (q.spine2 ~= q.spine and " (the copy's at " .. tostring(q.spine2) .. ")" or ""), h1, h2))
  log("split body: " .. r1)
  log("split body copy: " .. r2)
  -- a half that cut nothing falls back to a waist cut too: across her waist in an animated death that had just gone
  -- ragdoll, the copy vanished 101400 vertices with no seam and none sunk, and she died whole (playtest, CH_P_EVE_29)
  if not (ok_cut(r1) and ok_cut(r2)) then
    if r1:sub(1, 2) == "ok" and r2:sub(1, 2) == "ok" then
      log(string.format("split (%s) failed: the %s cut nothing", q.why, ok_cut(r1) and "copy" or "body"))
      q.degenerate = true
    end
    return false
  end
  -- each half must keep a real share of her, all sunk: a plane that grazed her left one half a sliver and the other
  -- a whole body nothing could sink (85506 vertices unsunk), standing over her as if nothing was cut
  local nv = num(r1, "vverts") or num(r1, "verts") or 0
  local nv2 = num(r2, "vverts") or num(r2, "verts") or 0
  local k1 = nv - (num(r1, "vvanished") or num(r1, "vanished") or 0)
  local k2 = nv2 - (num(r2, "vvanished") or num(r2, "vanished") or 0)
  local un = (num(r1, "vunsunk") or num(r1, "unsunk") or 0) + (num(r2, "vunsunk") or num(r2, "unsunk") or 0)
  local least = cfg().splitMinShare or 0.12
  if nv > 0 and (math.min(k1, k2) < nv * least or un > nv * 0.02) then
    log(string.format("split (%s) degenerate: halves keep %d and %d of %d vertices, %d unsunk",
      q.why, k1, k2, nv, un))
    q.degenerate = true
    return false
  end
  -- (the lids the next tick: with them the split held one frame 200 ms, twenty-ninth playtest)
  q.caps, q.r1, q.r2 = {}, r1, r2
  return true
end

return stage_split_prep, stage_split_cut
end
