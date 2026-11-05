-- Blade-hit classification and cut decisions; queued cuts remain with the gore lifecycle.
return function(M, d)
local PARTS, SPINE_CHAIN, enemy = d.PARTS, d.SPINE_CHAIN, d.enemy
local cfg, log, already_cut, bone_tm, start = d.cfg, d.log, d.already_cut, d.bone_tm, d.start
local norm, cross, dot, vec, add, sub, scale = d.norm, d.cross, d.dot, d.vec, d.add, d.sub, d.scale
local qrot, qinv = d.qrot, d.qinv
local CUT_AT_DEFAULT, SPINE_TOL = d.CUT_AT_DEFAULT, d.SPINE_TOL
local body_frame, from_body, to_body, mark = d.body_frame, d.from_body, d.to_body, d.mark
local function v3(...) return d.v3()(...) end
M.FLAT_LIMB = 10 -- cm: a limb this near the plane at both ends lies in it (classify)
local LIMB_SEGS = {
  { "Bip001-L-UpperArm", "Bip001-L-Forearm" }, { "Bip001-L-Forearm", "Bip001-L-Hand" },
  { "Bip001-R-UpperArm", "Bip001-R-Forearm" }, { "Bip001-R-Forearm", "Bip001-R-Hand" },
  { "Bip001-L-Thigh", "Bip001-L-Calf" }, { "Bip001-L-Calf", "Bip001-L-Foot" },
  { "Bip001-R-Thigh", "Bip001-R-Calf" }, { "Bip001-R-Calf", "Bip001-R-Foot" },
}
local function blade_plane(h)
  -- the plane the enemy's weapon swept (main.lua's weapon_swing)
  if h.n then return norm(h.n), h.how or "weapon" end
  local d, f = h.dir and norm(h.dir), h.fwd and norm(h.fwd)
  if d and f then
    local c = cross(d, f)
    if dot(c, c) > 0.09 then return norm(c), "swing x forward" end
  end
  -- no usable pair: by the game's attack direction, about the attacker's forward (or the swing's) on the level
  local fl = (f and norm(vec(f.X, f.Y, 0))) or (d and norm(vec(d.X, d.Y, 0)))
  if not fl then return nil end
  local right = vec(-fl.Y, fl.X, 0)
  if h.attack_dir == 1 or h.attack_dir == 2 then
    -- sideways: level, slanting a little along the swing
    return norm(add(vec(0, 0, 1), scale(right, (math.random() - 0.5) * 0.7))), "sideways"
  elseif h.attack_dir == 3 then
    -- from the front: upright, along the attacker's forward
    return right, "front"
  end
  return nil
end

-- her pose for M.blow (main.lua notes it with every sample of an enemy's swing): each bone the blade is judged on
-- (the spine's and the arms' and legs'), its world position and rotation ({ t, q })
M.pose_bones = (function()
  local l, seen = {}, {}
  for _, b in ipairs(SPINE_CHAIN) do l[#l + 1], seen[b] = b, true end
  for _, sg in ipairs(LIMB_SEGS) do
    for _, b in ipairs(sg) do if not seen[b] then l[#l + 1], seen[b] = b, true end end
  end
  return l
end)()
function M.pose(mesh)
  local p = {}
  for _, b in ipairs(M.pose_bones) do p[b] = bone_tm(mesh, b) end
  return p
end

-- tune.gore.oddsNear: the death odds main.lua rolls (a blade left aside by Hit Decides, or none seen) shaped by where
-- the blow landed: each kind's weight times how near the hit was to what it cuts, 1 within near cm and down to floor
-- at far cm (the neck for a beheading, the spine from her pelvis to her chest for a waist cut, her length for a split,
-- the nearest arm or leg for a limb). A blade's plane down her length makes a waist cut less likely (across), one across
-- her rules out a split, a blow from above a waist cut; with no plane a split is less likely (noPlane). A clear waist
-- cut rolled a beheading as often as a blow at her neck (playtest). Returns the factors per kind and how they were
-- judged, or nil: off, or no hit to go by
function M.near_odds(mesh, h, hit)
  local o = cfg().oddsNear or {}
  if o.enabled == false then return nil end
  local real = h and not h.made
  local at = (real and h.loc) or hit
  if not at then return nil end
  local P = real and h.pose
  local function bl(b)
    local x = P and P[b]
    if x then return x.t end
    return M.joint(mesh, b)
  end
  local function seg(a, b)
    local pa, pb = bl(a), bl(b)
    if not (pa and pb) then return nil end
    local ab = sub(pb, pa)
    local t = math.max(0, math.min(1, dot(sub(at, pa), ab) / math.max(dot(ab, ab), 1e-4)))
    local d = sub(at, add(pa, scale(ab, t)))
    return math.sqrt(dot(d, d))
  end
  local near, far, floor = o.near or 15, o.far or 35, math.min(math.max(o.floor or 0, 0), 1)
  local function f(d)
    if not d or d >= far then return floor end
    if d <= near then return 1 end
    return floor + (1 - floor) * (far - d) / math.max(far - near, 1e-3)
  end
  local dl
  for _, sg in ipairs(LIMB_SEGS) do
    if not already_cut(mesh, sg[1]) then
      local d = seg(sg[1], sg[2])
      if d and (not dl or d < dl) then dl = d end
    end
  end
  local dh, db, ds = seg("Bip001-Neck", "Bip001-Head"), seg("Bip001-Pelvis", "Bip001-Spine2"), seg("Bip001-Pelvis", "Bip001-Neck")
  local w = {
    limb = f(dl),
    head = already_cut(mesh, "Bip001-Head") and 0 or f(dh),
    torso = already_cut(mesh, "Bip001-Spine1") and 0 or f(db),
    split = f(ds),
    diagonal = f(ds),
  }
  local n = real and blade_plane(h)
  local dn = real and h.dir and norm(h.dir)
  local p0, p1 = bl("Bip001-Pelvis"), bl("Bip001-Neck")
  local ax = p0 and p1 and norm(sub(p1, p0))
  local how
  -- (a diagonal: in full from a blade slanting diagonal.bladeFrom-bladeTo degrees off her spine, else offSlant of it;
  -- noPlane of it with no plane, as a split)
  local dg = cfg().diagonal or {}
  local hr = n and ax and M.her_right(mesh, ax, bl)
  local deg = hr and M.blade_slant(ax, hr, norm(n))
  if not n then w.diagonal = w.diagonal * (o.noPlane or 0.5)
  elseif not (deg and deg >= (dg.bladeFrom or 20) and deg <= (dg.bladeTo or 60)) then w.diagonal = w.diagonal * (o.offSlant or 0.3) end
  if dn and dn.Z < -(cfg().splitDown or 0.6) then
    w.torso, how = 0, "from above"
  elseif n and ax and math.abs(dot(ax, norm(n))) < M.ALONG then
    w.torso, how = w.torso * (o.across or 0.25), "down her length"
  elseif n and ax then
    w.split, how = 0, "across her"
  else
    w.split, how = w.split * (o.noPlane or 0.5), "no plane"
  end
  if deg then how = how .. string.format(", %.0f deg off her spine", deg) end
  local function cm(d) return d and string.format("%.0f", d) or "?" end
  w.why = string.format("hit %s cm from a limb, %s from the neck, %s from the waist; %s; factors limb %.2f head %.2f torso %.2f split %.2f", cm(dl), cm(dh), cm(db), how, w.limb, w.head, w.torso, w.split)
  return w
end

function M.blow(pawn, mesh, h, why)
  local n, how = blade_plane(h)
  -- a hit after her death with no plane (a bare hand's swing along the attacker's forward, no attack direction from
  -- the game: "no plane", blood only, playtest): sideways or from the front, as a rolled attack direction would be
  if not n and why == "after" then
    n, how = blade_plane(setmetatable({ attack_dir = math.random() < 0.5 and 1 or 3 }, { __index = h }))
    if n then how = how .. " (rolled: no plane of its own)" end
  end
  local at = h.loc
  -- her pose as the blow landed (h.pose, from main.lua's swing samples): the blade is judged against it, not a frame
  -- into her death, when the death show had swung her arms on (an arm raised to block kept, the body behind it cut).
  -- What is chosen is then moved with its bone to where that bone is now (go): a limb's cut along its own bone, the
  -- rest with Spine1 (a head's with the neck)
  local P = h.pose
  if P then how = how .. string.format(" (on her pose %.2f s before)", h.pose_ago or 0) end
  local function bl(b)
    local x = P and P[b]
    if x then return x.t end
    return M.joint(mesh, b)
  end
  local function go(at, why, kind, out, plane, blade)
    -- a cut at the hit, before her death is reported (h.early, main.lua): a limb, the head or her body, which come off
    -- her animated body as F9's do (and open over openTime); a split waits for the death (it needs her ragdoll), and
    -- in an enemy's grab (h.grab) her body too: her legs stood on in its pose with nothing above them
    if h.early then
      if not (kind == "limb" or kind == "head" or (kind == "torso" and not h.grab)) then
        M.held = {}
        log(string.format("blade (early): %s %s waits for her death", kind, blade and blade.bone or ""))
        return false
      end
    end
    mark("blow: plane")
    local ref = blade and blade.bone or (kind == "head" and "Bip001-Neck") or "Bip001-Spine1"
    local was, now = P and P[ref], P and bone_tm(mesh, ref)
    if was and now then
      local function dirv(v) return v and qrot(now.q, qrot(qinv(was.q), v)) end
      local function pt(v) return v and add(now.t, dirv(sub(v, was.t))) end
      at, out = pt(at), dirv(out)
      if plane then plane = { at = pt(plane.at), n = dirv(plane.n) } end
      if blade then
        local c = {}
        for k, v in pairs(blade) do c[k] = v end
        c.n = dirv(blade.n)
        blade = c
      end
    end
    return start(pawn, mesh, at, why, kind, out, plane, blade)
  end
  local function vs(v) return v and string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) or "?" end
  if not (n and at) then
    log(string.format("blade (%s): no plane from dir %s fwd %s attack %s", why, vs(h.dir), vs(h.fwd), tostring(h.attack_dir)))
    return false
  end
  -- her sword, when the blade went through it (active.lua's weapon_cut: a blow she blocked with it, playtest); at
  -- the hit (h.early) once her death comes (M.release_held), she is still holding it
  -- The plane is the one at the blow, on her pose then (h.pose): carried with her sword hand to where it is now. Judged
  -- on her pose at the death instead, the death show had swung the sword out of it: "the blade misses it" on a blow
  -- she blocked with her blade up, split down the middle, the sword whole (playtest)
  local wat, wn = at, norm(n)
  local hw, hn = P and P["Bip001-R-Hand"], P and bone_tm(mesh, "Bip001-R-Hand")
  if hw and hn and wn then
    wat = add(hn.t, qrot(hn.q, qrot(qinv(hw.q), sub(at, hw.t))))
    wn = qrot(hn.q, qrot(qinv(hw.q), wn))
  end
  -- (at the hit: kept in the hand's frame, put back where the hand is when her death comes)
  if h.early then
    local l = hn and { at = qrot(qinv(hn.q), sub(wat, hn.t)), n = qrot(qinv(hn.q), wn) }
    M.held_sword = { mesh = mesh, at = wat, n = wn, hand = l }
  end
  if why == "death" and not h.early and not enemy.cur and d.ctx().rag and d.ctx().rag.weapon_cut then
    local ok, err = pcall(d.ctx().rag.weapon_cut, mesh, wat, wn, M.blocking)
    if not ok then log("weapon cut: " .. tostring(err)) end
  end
  -- a blow from above (a stomp, an overhead chop): it cuts down through her, never across her (a level waist cut from
  -- a stomp, playtest); splitDown as main.lua's split_normal
  local dn = h.dir and norm(h.dir)
  local down = dn ~= nil and dn.Z < -(cfg().splitDown or 0.6)
  -- what the plane does to her: the spine's heights over it, the arms and legs it crosses, and the first cut
  local function classify(n, at)
  local hs = {}
  for i, b in ipairs(SPINE_CHAIN) do
    local l = bl(b)
    if not l then return nil end
    hs[i] = dot(sub(l, at), n)
  end
  local pos, neg = false, false
  for _, x in ipairs(hs) do
    if x > SPINE_TOL then pos = true elseif x < -SPINE_TOL then neg = true end
  end
  local spine = {}
  for i, x in ipairs(hs) do spine[i] = string.format("%.0f", x) end
  local head_s = hs[#hs] >= 0 and 1 or -1
  -- the arm or leg the plane crosses nearest the hit, not along it (a blade running down a limb leaves nothing to cut)
  local best, struck
  local crossed = {} -- per limb (side and arm / leg): its crossing nearest the hit
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bl(sg[1]), bl(sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) > 0.3 and not already_cut(mesh, sg[1]) then
      local ha, hb = dot(sub(a, at), n), dot(sub(b, at), n)
      if (ha < 0) ~= (hb < 0) then
        local t = ha / (ha - hb)
        local x = add(a, scale(sub(b, a), t))
        local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
        local c = { bone = sg[1], t = t, d = dd, n = n }
        local limb = sg[1]:match("Bip001%-(%a)%-") .. ((sg[1]:find("Arm") or sg[1]:find("Forearm")) and "arm" or "leg")
        if not crossed[limb] or dd < crossed[limb].d then crossed[limb] = c end
        if not best or dd < best.d then best = c end
        if h.bone == sg[1] then struck = c end
      end
    end
  end
  -- an arm or leg lying along the plane, inside it (both ends within FLAT_LIMB cm): the blade went through it
  -- lengthwise, a forearm held across her to block a level swing. It was left out as "along the limb" and the swing
  -- took her waist alone behind it (playtest). It comes off where it is nearest the hit (multiCut), leaning with the
  -- blade as far as sliceTilt lets it
  for _, sg in ipairs(LIMB_SEGS) do
    local a, b = bl(sg[1]), bl(sg[2])
    local ax = a and b and norm(sub(b, a))
    if ax and math.abs(dot(ax, n)) <= 0.3 and not already_cut(mesh, sg[1])
      and math.abs(dot(sub(a, at), n)) <= M.FLAT_LIMB and math.abs(dot(sub(b, at), n)) <= M.FLAT_LIMB then
      local ab = sub(b, a)
      local t = math.max(0.2, math.min(0.9, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
      local x = add(a, scale(ab, t))
      local dd = math.sqrt(dot(sub(x, at), sub(x, at)))
      local limb = sg[1]:match("Bip001%-(%a)%-") .. ((sg[1]:find("Arm") or sg[1]:find("Forearm")) and "arm" or "leg")
      if not crossed[limb] then crossed[limb] = { bone = sg[1], t = t, d = dd, n = n, flat = true } end
    end
  end
  -- the limb the blow was aimed at (h.bone), when the plane crosses it, over whatever else it crosses nearer
  if struck then best = struck end
  -- how far the hit is from the spine (the nearest point of its segments)
  local off = 1e9
  for i = 1, #SPINE_CHAIN - 1 do
    local a, b = bl(SPINE_CHAIN[i]), bl(SPINE_CHAIN[i + 1])
    local ab = sub(b, a)
    local t = math.max(0, math.min(1, dot(sub(at, a), ab) / math.max(dot(ab, ab), 1e-4)))
    local x = add(a, scale(ab, t))
    off = math.min(off, math.sqrt(dot(sub(at, x), sub(at, x))))
  end
  -- down her length (the plane holds her spine's line) and how near the spine it passes
  local p0, p1 = bl("Bip001-Pelvis"), bl("Bip001-Neck")
  local ax = p0 and p1 and norm(sub(p1, p0))
  local along = ax and math.abs(dot(ax, n)) < M.ALONG
  local near = 1e9
  for i = 1, 5 do near = math.min(near, math.abs(hs[i])) end
  -- a blow from above landing at her neck (nearer it than her chest): a beheading, whichever way its plane runs
  local nk, s2 = bl("Bip001-Neck"), bl("Bip001-Spine2")
  local at_neck = down and nk and s2 and dot(sub(at, nk), sub(at, nk)) < dot(sub(at, s2), sub(at, s2))
  local what
  if at_neck and not already_cut(mesh, "Bip001-Head") then
    what = "head"
  elseif best and best.d < (cfg().limbReach or 12) and off > (cfg().spineReach or 15) then
    what = "limb" -- the blade met an arm or leg away from the body: that limb, whatever the plane does further on
  elseif pos and neg then
    -- through the spine: the neck (the chest clearly on the other side from the head) is a beheading
    what = hs[4] * head_s < -SPINE_TOL and "head" or "slice"
  elseif not pos and not neg then
    what = "slice" -- along the spine
  elseif along and near <= (cfg().spineReach or 15) then
    -- down her length a little beside the spine (14/10/7/3/-2/-3 cm off it): split there, it took nothing and the
    -- odds were rolled (playtest)
    what = "slice"
  else
    what = "limb"
  end
  -- down her length facing her front or back: a split there would be front from back, a slab of her chest (a blade
  -- down her front 4-10 cm off the spine, playtest). A cut across her body instead (shave), or the limb it met
  local r = along and M.her_right(mesh, ax, bl)
  local shave = false
  if what == "slice" and r and math.abs(dot(n, r)) < M.ALONG then
    if best and best.d < (cfg().limbReach or 12) then what = "limb" else shave = true end
  end
  return { hs = hs, pos = pos, neg = neg, spine = spine, head_s = head_s, best = best, crossed = crossed, off = off, what = what,
    shave = shave }
  end
  -- the blade decides what comes off, nothing rolled over it. For variety each blade is turned up to bladeJitter
  -- degrees and moved up to bladeShift cm along its normal (a sweep across her chest takes one arm, both, or an arm and
  -- the chest), and a death that would take the same first part as the last one tries other turns of it (up to
  -- bladeTries): one enemy's one attack took the same arm every time
  local g = cfg()
  local n0, at0, c = n, at, nil
  local jit = (why == "death" or why == "after") and not h.laser and (g.bladeJitter or 15) or 0
  local tries = jit > 0 and (g.bladeTries or 4) or 1
  local function key(x) return x.what .. (x.what == "limb" and x.best and (" " .. x.best.bone) or "") end
  -- a blade through her body (a split, a body cut) is taken as it came: turned, a vertical blade ran across her and
  -- missed, and the next death with the same attack, avoiding the split the last one made, rolled the head (playtest)
  local x0 = jit > 0 and classify(n0, at0)
  if x0 and x0.what ~= "limb" then tries, c = 0, x0 end
  for i = 1, tries do
    local nn, aa = n0, at0
    if jit > 0 then
      local r = norm(vec(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)) or vec(0, 0, 1)
      local u = norm(cross(n0, r))
      if u then
        local th = math.rad((math.random() * 2 - 1) * jit)
        nn = norm(add(scale(n0, math.cos(th)), scale(cross(u, n0), math.sin(th)))) or n0
      end
      aa = add(at0, scale(n0, (math.random() * 2 - 1) * (g.bladeShift or 10)))
    end
    local x = classify(nn, aa)
    if not x then return false end
    if not c or why ~= "death" or key(x) ~= M.last_blow then n, at, c = nn, aa, x end
    if why ~= "death" or key(c) ~= M.last_blow then break end
  end
  if not c then return false end
  if why == "death" then
    if c.what == "limb" and key(c) == M.last_blow then how = how .. " (same as the last death, no other turn of it)" end
    M.last_blow = key(c)
  end
  local hs, pos, neg, spine, head_s, best, crossed, off, what = c.hs, c.pos, c.neg, c.spine, c.head_s, c.best, c.crossed, c.off, c.what
  -- a plane past the spine that only takes a thigh at its hip joint (or a calf right at the knee from a blow aimed at
  -- the body) cut the hips: across the waist instead, square to the spine
  local hip = what == "limb" and best and best.bone:find("Thigh") and best.t < 0.25 and not down
  -- more cuts from one wide swing (multiCut): every other arm or leg the plane crosses within reach cm of the hit,
  -- and the neck when it crosses that near, after the first cut. One cut a death left a sweep through both arms
  -- taking one of them
  local mc = cfg().multiCut or {}
  -- a laser's beam (main.lua's sw.laser_hit) takes everything its plane goes through, however far from where it met her
  if h.laser then mc = setmetatable({ reach = 1e4, max = 8, bodyReach = 1e4 }, { __index = mc }) end
  -- followUpCuts off: the swing makes one cut, its body cut over the limbs it crossed (a laser still takes everything)
  local one = cfg().followUpCuts == false and not h.laser
  local reach, most = mc.reach or 40, mc.max or 3
  -- her body cut along the blade, where its plane goes through her spine below the neck within bodyReach cm of the
  -- hit, or passes within bodyGraze cm beside it, through her flank; nil when it doesn't or her body is cut already.
  -- The cut is made under her bust (PARTS), whatever height the blade crossed her at; a blade running down her
  -- length cuts square to the spine there instead
  local function body_blade()
    if already_cut(mesh, "Bip001-Spine1") then return nil end
    local near
    local under = PARTS["Bip001-Spine1"].at
    for i = 1, 4 do
      if (hs[i] < 0) ~= (hs[i + 1] < 0) then
        local a, b = bl(SPINE_CHAIN[i]), bl(SPINE_CHAIN[i + 1])
        local tt = hs[i] / (hs[i] - hs[i + 1])
        local x = a and b and add(a, scale(sub(b, a), tt))
        local dd = x and math.sqrt(dot(sub(x, at), sub(x, at)))
        if dd and dd < (mc.bodyReach or 60) and (not near or dd < near.d) then
          near = { bone = "Bip001-Spine1", t = under, d = dd, n = n }
        end
      end
    end
    if not near then
      local graze = mc.bodyGraze or 10
      for j = 1, 5 do
        local l = bl(SPINE_CHAIN[j])
        local dd = l and math.sqrt(dot(sub(l, at), sub(l, at)))
        if l and math.abs(hs[j]) <= graze and dd < (mc.bodyReach or 60) and (not near or math.abs(hs[j]) < near.off) then
          near = { bone = "Bip001-Spine1", t = under, d = dd, n = n, off = math.abs(hs[j]) }
        end
      end
    end
    if near then
      local a, b = bl("Bip001-Spine1"), bl("Bip001-Spine2")
      local sp = a and b and norm(sub(b, a))
      if sp and math.abs(dot(sp, n)) < M.ALONG then
        -- squared, a blade from above would cut her level: no body cut, the limbs alone
        if down then return nil end
        near.n, near.square = sp, true
      end
    end
    return near
  end
  local function limb_key(b) return b:match("Bip001%-(%a)%-") .. ((b:find("Arm") or b:find("Forearm")) and "arm" or "leg") end
  -- the limb h.second (main.lua: the swing's other blade) swept, crossed by its plane where it went through, else at
  -- the point of the limb nearest where it swept (a plane running down the limb), leaning with that blade
  local function second_blade(skip)
    local s2 = h.second
    if not (s2 and s2.n and s2.at and s2.part and (why == "death" or why == "after")) then return nil end
    local p2 = s2.part:match("Bip001%-%a%-") and s2.part
    if not p2 then return nil end
    local key2 = limb_key(p2)
    if key2 == skip then return nil end
    local n2, best
    n2 = norm(s2.n)
    for _, sg in ipairs(LIMB_SEGS) do
      if limb_key(sg[1]) == key2 and not already_cut(mesh, sg[1]) then
        local a, b = bl(sg[1]), bl(sg[2])
        if a and b and n2 then
          local ha, hb = dot(sub(a, s2.at), n2), dot(sub(b, s2.at), n2)
          local ab = sub(b, a)
          local t
          if (ha < 0) ~= (hb < 0) and math.abs(dot(norm(ab) or n2, n2)) > 0.3 then t = ha / (ha - hb)
          else t = math.max(0.2, math.min(0.9, dot(sub(s2.at, a), ab) / math.max(dot(ab, ab), 1e-4))) end
          local x = add(a, scale(ab, t))
          local dd = math.sqrt(dot(sub(x, s2.at), sub(x, s2.at)))
          if not best or dd < best.d then best = { bone = sg[1], t = t, d = dd, n = n2, second = true } end
        end
      end
    end
    return best
  end
  local function extras(first)
    local out = {}
    if mc.enabled == false or most <= 1 then return out end
    local skip = first and first.bone and (first.bone:match("Bip001%-(%a)%-") .. ((first.bone:find("Arm") or first.bone:find("Forearm")) and "arm" or "leg"))
    -- an arm or leg the swing met first (an arm raised to block, a leg in its way) doesn't stop it: where its plane
    -- goes on through her spine below the neck, within bodyReach cm of the hit, her body is cut too, across the chest
    -- or the waist along the blade (it took the arm alone before). A plane that passes within bodyGraze cm beside
    -- the spine goes through her flank too: the cut is put on the spine at the blade's angle (it took the limb alone,
    -- however the swing ran on into her, playtest 41; a leg's never went on). One running down her length is cut
    -- square to the spine instead
    if first and first.kind == "limb" and skip and mc.body ~= false then
      local near = body_blade()
      if near then out[#out + 1] = { kind = "torso", blade = near } end
    end
    local list = {}
    for limb, c in pairs(crossed) do if limb ~= skip and c.d < reach then list[#list + 1] = c end end
    table.sort(list, function(x, y) return x.d < y.d end)
    -- the swing's second blade (a cross slash with two): the arm or leg it swept comes off along its own plane, first
    -- of the rest (its first blade's plane rarely crossed that one too, and it stayed whole)
    local two = second_blade(skip)
    if two then
      local l2 = limb_key(two.bone)
      for i = #list, 1, -1 do if limb_key(list[i].bone) == l2 then table.remove(list, i) end end
      table.insert(list, 1, two)
    end
    -- with her body cut too, one leg at most comes off (the first cut's or the nearest): a swing through her hips
    -- took a thigh, the waist and the other thigh, her pelvis a lump of its own (fell apart like a lego set, playtest)
    local torso = (first and first.kind == "torso") or (out[1] and out[1].kind == "torso")
    local legs = skip and skip:find("leg") and 1 or 0
    for _, c in ipairs(list) do
      local leg = c.bone:find("Thigh") or c.bone:find("Calf")
      if #out < most - 1 and not (torso and leg and legs >= 1) then
        out[#out + 1] = { kind = "limb", blade = c }
        if leg then legs = legs + 1 end
      end
    end
    if first and first.kind ~= "head" and #out < most - 1 and (hs[5] < 0) ~= (hs[6] < 0) and not (out[1] and out[1].kind == "torso") then
      local nk = bl("Bip001-Neck")
      if nk and math.sqrt(dot(sub(nk, at), sub(nk, at))) < reach then out[#out + 1] = { kind = "head" } end
    end
    return out
  end
  -- the rest, queued in her own frame (the ragdoll moves on while the first cut opens)
  local function queue(list)
    if #list == 0 then return "" end
    if one then return string.format(" (%d more left whole: followUpCuts off)", #list) end
    M.queue_gap = cfg().queueGap or 1
    local f = body_frame(mesh)
    local names = {}
    for _, e in ipairs(list) do
      local rel = not P and f and e.blade and to_body(f, e.blade.n)
      local into = h.early and M.held or d.queued()
      into[#into + 1] = function()
        if e.kind == "head" then return go(bl("Bip001-Neck") or at, why, "head", h.dir) end
        local c = { bone = e.blade.bone, t = e.blade.t, d = e.blade.d, n = e.blade.n, square = e.blade.square }
        local fn = rel and body_frame(mesh)
        if fn then c.n = norm(from_body(fn, rel)) or c.n end
        if already_cut(mesh, c.bone) then return false end
        return go(bl(c.bone) or at, why, e.kind, nil, nil, c)
      end
      names[#names + 1] = e.kind == "head" and "head" or e.kind == "torso" and string.format("her body at %s %.0f cm in%s%s", e.blade.bone, e.blade.d,
        e.blade.off and string.format(", the blade %.0f cm beside her spine", e.blade.off) or "", e.blade.square and ", square" or "") or (e.blade.bone .. (e.blade.flat and " (lying in the blade)" or "") .. (e.blade.second and " (the second blade)" or ""))
    end
    return ", then " .. table.concat(names, ", ")
  end
  -- both arms the blade crosses within reach cm of the hit, nearest first, and no split: the first now, the other
  -- queued (armsOverSplit, h.armsOnly). A blade down her length through her arms raised split her nearly every time,
  -- the arms coming off only on the way, and a split rolled took her whatever the blade had crossed (playtest)
  local function both_arms()
    local arms = {}
    for limb, c in pairs(crossed) do if limb:find("arm") and c.d < reach then arms[#arms + 1] = c end end
    if #arms < 2 then return nil end
    table.sort(arms, function(x, y) return x.d < y.d end)
    return arms
  end
  local function arms_cut(arms, what)
    local first = table.remove(arms, 1)
    local list = {}
    for _, c2 in ipairs(arms) do list[#list + 1] = { kind = "limb", blade = c2 } end
    local more = queue(list)
    log(string.format("blade (%s): %s %s: both arms instead, %s at %.2f first%s", why, how, what, first.bone, first.t, more))
    return go(at, why, "limb", nil, nil, first)
  end
  if h.armsOnly then
    local arms = mc.enabled ~= false and not one and both_arms()
    if not arms then return false end
    return arms_cut(arms, "with a split rolled")
  end
  -- a cut down her length (the plane along her spine) at death is off (deathSplit false): the limbs it crosses near
  -- the hit come off instead, or the death's odds are rolled. An enemy is never split: the same for its corpse (a
  -- downward chop through one rolled its odds, whatever arm it went through)
  local axis = (function()
    local p0, p1 = bl("Bip001-Pelvis"), bl("Bip001-Neck")
    return p0 and p1 and norm(sub(p1, p0))
  end)()
  local lengthwise = axis and math.abs(dot(axis, n)) < M.ALONG
  -- (noSplits: never, at death, after it or alive)
  local nosplit = why == "enemy" or cfg().noSplits == true or ((why == "death" or why == "after") and cfg().deathSplit == false)
  if (what == "slice" or (not pos and not neg)) and lengthwise and nosplit then
    -- No Vertical Splits redirects an otherwise valid body split to the nearest neck or waist on the
    -- struck pose. Preserve normal multi-cut limits for limbs crossed by the original blade.
    if cfg().noSplits == true and why ~= "enemy" then
      local neck, waist = bl("Bip001-Neck"), bl("Bip001-Spine1")
      local headOK = neck and not already_cut(mesh, "Bip001-Head")
      local bodyOK = waist and not already_cut(mesh, "Bip001-Spine1")
      if headOK or bodyOK then
        local headFirst = headOK and (not bodyOK or math.abs(dot(sub(at, neck), axis)) < math.abs(dot(sub(at, waist), axis)))
        local kind = headFirst and "head" or "torso"
        local more = (why == "death") and queue(extras({ kind = kind })) or ""
        log(string.format("blade (%s): %s vertical split redirected to %s (noSplits)%s", why, how, kind, more))
        if headFirst then return go(neck, why, "head", h.dir) end
        return go(waist, why, "torso", nil, nil,
          { bone = "Bip001-Spine1", t = PARTS["Bip001-Spine1"].at, d = 0, n = axis, square = true })
      end
    end
    local list = extras(nil)
    if #list == 0 or list[1].kind ~= "limb" then
      log(string.format("blade (%s): %s plane down her length, no split %s", why, how,
        why == "enemy" and "on an enemy" or cfg().noSplits == true and "(noSplits on)" or "at death (deathSplit off)"))
      return false
    end
    local first = table.remove(list, 1)
    local more = queue(list)
    log(string.format("blade (%s): %s plane down her length, no split %s: %s at %.2f instead%s", why, how,
      why == "enemy" and "on an enemy" or "at death", first.blade.bone, first.blade.t, more))
    return go(at, why, "limb", nil, nil, first.blade)
  end
  -- a blade across her body cuts it along the blade (the chest or the waist), and every arm and leg it crossed comes
  -- off after it (multiCut); one down her length splits her along it. A bladeSplit roll split her a fifth of the time
  -- whichever way the blade went, and rolled the odds the rest (a waist cut square to her spine and nothing else,
  -- though the weapon went through her arms, playtest)
  local splits = what == "slice"
  -- a blade slanting across her body (diagonal.bladeFrom to bladeTo degrees off her spine), not facing her front or
  -- back: cut diagonally from over the shoulder it came down from (M.diagonal), the limbs going with the halves. Snapped
  -- to across or down her length at 45 degrees, a slash from her shoulder to her hip came out a waist cut or a split
  local dg = cfg().diagonal or {}
  if splits and not c.shave and dg.enabled ~= false and axis and not nosplit and not h.noSplit then
    local r = M.her_right(mesh, axis, bl)
    local deg, slab, side
    if r then deg, slab, side = M.blade_slant(axis, r, n) end
    if deg and not slab and deg >= (dg.bladeFrom or 20) and deg <= (dg.bladeTo or 60) then
      log(string.format("blade (%s): %s plane %.0f deg off her spine: a diagonal from over her %s shoulder", why, how, deg,
        side == "R" and "right" or "left"))
      return go(at, why, "split", nil, { at = at, n = n, diag = side })
    end
  end
  if splits and (not lengthwise or c.shave) then
    local body = not h.noSplit and mc.body ~= false and body_blade()
    if not body then
      log(string.format("blade (%s): %s plane across her body, too far from the hit or cut already", why, how))
      return false
    end
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "torso" })) or ""
    log(string.format("blade (%s): %s plane %s: her body at %s %.2f%s%s",
      why, how, c.shave and "down her length facing her front or back: no split" or "across her body",
      body.bone, body.t, body.square and ", square" or "", more))
    return go(bl(body.bone) or at, why, "torso", nil, nil, body)
  end
  -- a blow that would split her when she can't be split (h.noSplit: a hit after death on a body already cut; a split
  -- needs her whole): the arms and legs its plane crossed near the hit come off instead, else her body along the
  -- blade while it is whole; only with neither does main.lua mark her (every such hit was a mark, playtest)
  local knee = what == "limb" and best and off < (cfg().spineReach or 15) and best.bone:find("Calf") and not down
  if h.noSplit and (hip or knee
    or (what ~= "limb" and what ~= "head")) then
    local list = extras(nil)
    if list[1] and list[1].kind == "limb" then
      local first = table.remove(list, 1)
      local more = queue(list)
      log(string.format("blade (%s): %s plane through her body, she is cut already: no split, %s at %.2f instead%s",
        why, how, first.blade.bone, first.blade.t, more))
      return go(at, why, "limb", nil, nil, first.blade)
    end
    local body = mc.body ~= false and body_blade()
    if body then
      log(string.format("blade (%s): %s plane through her body, she is cut already: no split, her body at %s %.2f instead",
        why, how, body.bone, body.t))
      return go(bl(body.bone) or at, why, "torso", nil, nil, body)
    end
    log(string.format("blade (%s): %s plane through her body, she is cut already: no split, no arm, leg or body cut near it", why, how))
    return false
  end
  -- (an enemy: its waist cut square to the spine, as a body cut: it is never split)
  if (hip or knee) and why == "enemy" and not already_cut(mesh, "Bip001-Spine1") then
    local a, b = bl("Bip001-Spine1"), bl("Bip001-Spine2")
    local sp = a and b and norm(sub(b, a))
    if sp then
      log(string.format("blade (%s): it only met %s at %.2f, its waist cut square instead", why, best.bone, best.t))
      return go(a, why, "torso", nil, nil, { bone = "Bip001-Spine1", t = PARTS["Bip001-Spine1"].at, d = 0, n = sp, square = true })
    end
  end
  if why == "enemy" and (hip or knee or (what ~= "limb" and what ~= "head")) then
    log(string.format("blade (%s): %s plane through its body, no split on an enemy", why, how))
    return false
  end
  if hip or knee then
    local a, b = bl("Bip001-Spine"), bl("Bip001-Spine1")
    if a and b then
      at = add(a, scale(sub(b, a), 0.4))
      log(string.format("blade (%s): it only met %s at %.2f, cut across the waist at %s instead", why, best.bone,
        best.t, v3(at)))
      return go(at, why, "split", norm(sub(b, a)), { at = at, n = norm(sub(b, a)) })
    end
  end
  -- a plane that crosses no arm or leg past the spine: the one the blow was aimed at is cut square, when it has one
  -- (nineteenth playtest: a swing 279 cm off, moved onto her forearm, ran along it and the death rolled its odds)
  if what == "limb" and not best and h.bone and not already_cut(mesh, h.bone) then
    for _, sg in ipairs(LIMB_SEGS) do
      if sg[1] == h.bone then
        local a, b = bl(sg[1]), bl(sg[2])
        local ax = a and b and norm(sub(b, a))
        if ax then
          best = { bone = sg[1], t = CUT_AT_DEFAULT, d = 0, n = ax }
          how = how .. " (along the limb it was aimed at: cut square)"
        end
        break
      end
    end
  end
  local blade = what == "limb" and best or nil
  log(string.format("blade (%s): %s plane at %s normal %s, dir %s fwd %s attack %s, spine %s cm off it -> %s%s",
    why, how, v3(at), vs(n), vs(h.dir), vs(h.fwd), tostring(h.attack_dir), table.concat(spine, "/"), what,
    blade and (" " .. blade.bone .. string.format(" at %.2f", blade.t)) or ""))
  if what == "limb" then
    if not blade then return false end
    -- one cut a swing: her body when the plane goes on through it, else the limb
    local body = one and (why == "death" or why == "enemy") and mc.body ~= false and body_blade()
    if body then
      log(string.format("blade (%s): %s plane through %s and her body: her body at %s %.2f alone (followUpCuts off)",
        why, how, blade.bone, body.bone, body.t))
      return go(bl(body.bone) or at, why, "torso", nil, nil, body)
    end
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "limb", bone = blade.bone })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return go(at, why, "limb", nil, nil, blade)
  elseif what == "head" then
    local more = (why == "death" or why == "enemy") and queue(extras({ kind = "head" })) or ""
    if more ~= "" then log("blade (" .. why .. "): one swing" .. more) end
    return go(at, why, "head", h.dir)
  end
  -- down her length: through her middle, left from right, turned towards the blade at most splitYaw (split_plane;
  -- the blade's own plane split her anywhere: slivers off her flank, her hips flattened into the cut). The arms its
  -- plane crosses within reach cm of the hit (an arm raised to block, playtest: the split kept it whole) come off
  -- first along the blade, nearest first, then the split (splitArms; the split takes a body whose only cuts are arms,
  -- stage_split_prep). At the hit (h.early) the first one now and the rest with the split at her death
  local arms, names = {}, {}
  for limb, c in pairs(crossed) do
    if limb:find("arm") then
      names[#names + 1] = string.format("%s at %.2f, %.0f cm from the hit%s", c.bone, c.t, c.d, c.flat and " (lying in it)" or "")
      if c.d < reach then arms[#arms + 1] = c end
    end
  end
  table.sort(arms, function(x, y) return x.d < y.d end)
  -- and the arm the swing's second blade swept (a cross slash), along its own plane
  local two = mc.enabled ~= false and second_blade(nil)
  if two and limb_key(two.bone):find("arm") then
    for i = #arms, 1, -1 do if limb_key(arms[i].bone) == limb_key(two.bone) then table.remove(arms, i) end end
    arms[#arms + 1] = two
    names[#names + 1] = string.format("%s at %.2f (the second blade)", two.bone, two.t)
  end
  local cut_arms = #arms > 0 and why == "death" and cfg().splitArms ~= false and mc.enabled ~= false and not one
  if cut_arms and #arms >= 2 and math.random() < (cfg().armsOverSplit or 0.6) then
    local two2 = both_arms() or arms
    return arms_cut(two2, "plane down her length")
  end
  if #names > 0 then
    log(string.format("blade (%s): the split's plane crosses %s%s", why, table.concat(names, "; "),
      cut_arms and "" or " (kept whole by its half)"))
  end
  if cut_arms then
    local first = table.remove(arms, 1)
    local list = {}
    for _, c in ipairs(arms) do list[#list + 1] = { kind = "limb", blade = c } end
    local into = h.early and M.held or d.queued()
    local n0 = #into
    local more = queue(list)
    -- (the split itself: go refuses one at the hit, and the first cut took the throw's direction, M.aim)
    local current_aim = d.aimed()
    local fly = current_aim and current_aim.d
    into[#into + 1] = function()
      local e = h.early
      h.early = nil
      if fly then d.set_aimed({ d = fly, t = os.clock() }) end
      local ok, r = pcall(go, at, why, "split", n)
      h.early = e
      if not ok then error(r, 0) end
      return r
    end
    log(string.format("blade (%s): %s plane down her length: %s at %.2f first%s, then the split", why, how, first.bone,
      first.t, more))
    if go(at, why, "limb", nil, nil, first) then return true end
    -- the arm didn't come off: the split alone, as it was
    while #into > n0 do table.remove(into) end
  end
  return go(at, why, "split", n)
end

end
