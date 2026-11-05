-- Split and blade plane geometry, shared by hit selection and staged split cuts.
return function(M, cfg, bone_loc, vec, sub, add, scale, norm, dot, cross, get_try)
local function try(...) local f = get_try(); return f(...) end
-- a cut through her body is one of two kinds: across her (square to her spine, under her bust, leaned a little) or
-- down her length (through her middle, left from right). A blade within 45 degrees of her spine's line goes down it,
-- else across. Whatever angle the blade had, the cut snaps to one of them: free angles cut slabs off her chest and
-- slivers off her flank, each with a rule of its own to clean it up.
-- A third kind runs diagonally from over a shoulder to the other hip (M.diag_plane), set by the joints, not snapped.
M.ALONG = math.sqrt(0.5)
-- her right, square to her spine (axis): from her left hip and shoulder joints to her right ones, which move with
-- her pelvis and chest whatever her arms and legs do
function M.her_right(mesh, axis, bl)
  bl = bl or function(b) return bone_loc(mesh, b) end
  local r = vec(0, 0, 0)
  for _, s in ipairs({ "Thigh", "UpperArm" }) do
    local l, rr = bl("Bip001-L-" .. s), bl("Bip001-R-" .. s)
    if l and rr then r = add(r, sub(rr, l)) end
  end
  return norm(sub(r, scale(axis, dot(r, axis))))
end

-- which side of her a hit landed on, "left" or "right" (tune.gore.lowArm.side "hit"): a bone of one side named (the
-- mesh's hit bone), else where it landed off her spine, her right (M.her_right) one way; nil within mid cm of the
-- spine, or nothing to go by
function M.hit_side(mesh, at, bone, mid)
  bone = bone and tostring(bone) or ""
  if bone:find("%-L%-") then return "left", "on " .. bone end
  if bone:find("%-R%-") then return "right", "on " .. bone end
  if not at then return nil, "nowhere" end
  local p0, p1 = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Neck")
  if not (p0 and p1) then return nil, "no spine" end
  local ax = norm(sub(p1, p0))
  local r = ax and M.her_right(mesh, ax)
  if not r then return nil, "no spine" end
  local d = dot(sub(at, p0), r)
  if math.abs(d) < (mid or 3) then return nil, string.format("%.0f cm off her spine", d) end
  return d > 0 and "right" or "left", string.format("%.0f cm to her %s", math.abs(d), d > 0 and "right" or "left")
end

-- the plane: through the spine, its normal square to the spine (from the swing, else her right)
local function split_plane(q)
  local pel, head = bone_loc(q.mesh, "Bip001-Pelvis"), bone_loc(q.mesh, "Bip001-Head")
  local at = bone_loc(q.mesh, "Bip001-Spine1")
  if not (pel and head and at) then return nil end
  local axis = norm(sub(head, pel)) or vec(0, 0, 1)
  local function square(v) return v and norm(sub(v, scale(axis, dot(v, axis)))) end
  local n = not q.middle and square(q.out) or nil
  local from = "swing"
  if not n then
    from = "her right"
    n = square(try(function() local v = q.pawn:GetActorRightVector(); return vec(v.X, v.Y, v.Z) end)) or vec(0, 1, 0)
  end
  local tilt = q.middle and 0 or (cfg().tilt or 0.25) * 0.3
  n = square(add(n, vec((math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt, (math.random() - 0.5) * tilt))) or n
  -- with no swing to follow, turned at random within splitYaw about her spine (it was the same plane every time)
  if from == "her right" and not q.middle then
    local th = (math.random() * 2 - 1) * math.rad(cfg().splitYaw or 15)
    n = square(add(scale(n, math.cos(th)), scale(cross(axis, n), math.sin(th)))) or n
  end
  -- left from right only, at most splitYaw off her middle: a plane facing her front cut a slab off her chest
  local r = M.her_right(q.mesh, axis)
  if r and q.middle then n, from = r, "her middle"
  elseif r then
    if dot(n, r) < 0 then r = scale(r, -1) end
    local max = math.rad(cfg().splitYaw or 15)
    if math.acos(math.max(-1, math.min(1, dot(n, r)))) > max then
      local f = norm(sub(n, scale(r, dot(n, r))))
      n = f and norm(add(scale(r, math.cos(max)), scale(f, math.sin(max)))) or r
      from = from .. string.format(", turned to %.0f deg off her middle", math.deg(max))
    end
  end
  -- splitBeside: leaned about her front-to-back axis from her crotch to that far beside her neck, so the head stays
  -- whole on her half. Her crotch, the gap between her breasts (they sit 4.3 cm either side) and her neck all lie on
  -- her middle, so the lean is small: at 10 cm the cut ran 7 cm off it at the chest, through a breast; at 2, 1.4 cm
  -- Its lower end moves up to splitHipShift cm off her crotch to either side at random, so it runs a little
  -- diagonally (the breasts, 4.3 cm off her middle, see under a third of it; the hip joints are 10 cm off)
  local side, neck = cfg().splitBeside or 2, bone_loc(q.mesh, "Bip001-Neck")
  if side > 0 and neck then
    local t = norm(cross(axis, n))
    local hip = q.middle and 0 or (math.random() * 2 - 1) * (cfg().splitHipShift or 4)
    local low = add(pel, scale(n, hip))
    local d = sub(sub(neck, scale(n, side)), low)
    local m = t and norm(cross(t, d))
    if m then
      if dot(m, n) < 0 then m = scale(m, -1) end
      at, n, from = low, m, from .. string.format(", beside the neck, %.1f cm off her crotch", hip)
    end
  end
  return at, n, from
end

-- a diagonal cut (tune.gore.diagonal): from lift cm over one shoulder's joint ("R" or "L") down across her to hip cm
-- over the other hip's joint and out cm out past it, the plane holding her front-to-back axis, as she is now. Her half
-- keeps the head and the other arm, the copy that arm and both legs. By the joints, not an angle, so the limbs always
-- fall to those halves: 33-40 degrees off her spine with jitter cm on lift and hip (jit). At 30 her far hip's skin rode
-- her chest once her spine broke and shifted 9 cm at the cut on a bent spine (harness, real_split.c DIAG). Returns
-- the plane's point and normal (the head's side), its angle off her spine, lift and hip
function M.diag_plane(mesh, side, jit)
  local d = cfg().diagonal or {}
  local pel, head = bone_loc(mesh, "Bip001-Pelvis"), bone_loc(mesh, "Bip001-Head")
  local sh = bone_loc(mesh, side == "R" and "Bip001-R-UpperArm" or "Bip001-L-UpperArm")
  local hp = bone_loc(mesh, side == "R" and "Bip001-L-Thigh" or "Bip001-R-Thigh")
  if not (pel and head and sh and hp) then return nil end
  local axis = norm(sub(head, pel))
  local r = axis and M.her_right(mesh, axis)
  if not r then return nil end
  local j = jit and math.max(tonumber(d.jitter) or 2, 0) or 0
  local lift = (tonumber(d.lift) or 6) + (math.random() * 2 - 1) * j
  local hip = (tonumber(d.hip) or 8) + (math.random() * 2 - 1) * j
  local s = side == "R" and 1 or -1
  local top = add(sh, scale(axis, lift))
  local bot = sub(add(hp, scale(axis, hip)), scale(r, s * (tonumber(d.out) or 7)))
  local dl = norm(sub(bot, top))
  local n = dl and norm(cross(dl, cross(axis, r)))
  if not n then return nil end
  if dot(n, axis) < 0 then n = scale(n, -1) end
  return top, n, math.deg(math.acos(math.max(-1, math.min(1, -dot(dl, axis))))), lift, hip
end
-- a blade's plane n against her (axis: up her spine, r: her right): the angle its line across her front runs off her
-- spine (0 down her length, 90 across), whether it faces her front or back more than ALONG (a slab, not a cut through
-- her), and the shoulder it comes down from ("R" when it runs down towards her left)
function M.blade_slant(axis, r, n)
  local f = norm(cross(axis, r))
  if not (f and n) then return nil end
  local np = norm(sub(n, scale(f, dot(n, f))))
  if not np then return nil, true end
  local deg = math.deg(math.asin(math.min(1, math.abs(dot(np, axis)))))
  local d = cross(np, f)
  if dot(d, axis) > 0 then d = scale(d, -1) end
  return deg, math.abs(dot(norm(n), f)) > M.ALONG, dot(d, r) > 0 and "L" or "R"
end

return split_plane
end
