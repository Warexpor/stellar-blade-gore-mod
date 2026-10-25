-- struggle.lua: a maimed Eve fighting on the floor after a ragdoll death (tune.struggle), the convulsions' body side
-- once a cut has left her something to fight with or against. Not an animation: every movement is the ragdoll itself,
-- steered.
--
-- She bleeds out over the struggle (bleed): frantic at first (faster, stronger than her usual), weakening steadily,
-- moving slower and less, and at the end dying: a few last tremors in her hands and feet, one last breath, her head
-- rolling aside, still. Through it she breathes, fast and deep at first, slower and shallower as she goes, and the
-- stump of a cut-off limb jerks and quivers on its own (reflex).
--
-- What she does is a run of acts, each picked by what the cuts left her and how she lies, weighted (acts), and
-- shorter or longer as she weakens:
--   * clutch: an arm still on and a stump: the hand goes to the stump and holds it, shaking, slipping and taking hold
--     again, while she rolls over towards her side and back (the wound up) and her legs draw up and kick out in turn.
--     A leg's stump takes both hands when she has both.
--   * reach: a hand stretching towards her cut-off arm or leg lying near, straining, falling short and dropping.
--   * turn: on her back with an arm: reaching across her and rolling over onto her front (a crawl comes next).
--   * crawl: face down with an arm: the hand reaching out past her head, planting, and dragging her forward, the
--     other one after it, her legs scrabbling.
--   * rise: on her back: her belly tenses and curls her chest and head up off the floor, shaking, her feet braced, a
--     strain on her face and a groan, until it gives out and she drops back.
--   * prop: the same with an arm: the elbow got under her, pushing her chest up, held shaking, collapsing.
--   * push: no arm left: on her back her knees bend and her heels drive into the floor, shoving her along; face down
--     her legs scrabble and she tries to turn over; on her side she first rolls onto her back.
--   * curl: curling up tight, the knees drawn to her chest, the arms in round her head.
--   * lie: a moment lying still, only breathing.
-- A death with no limb cut (rise.alone of them) only tries to sit up or prop up, between convulse.lua's arm swings.
-- Nothing on a beheading, a split, a waist cut, or an animated death (her fall's end pose) unless animated is on.
--
-- How: each joint moved has a target direction for its bone (a hand's or foot's place solved into its two bones
-- with two-bone IK, the elbow or knee bent the way the joint goes), and the bone's turn against its parent is steered
-- towards the speed that closes the gap (gain times the angle, at most speed), by velocity-change impulses on it and
-- its parent, so she moves herself. A velocity servo instead of a spring: at the game's frame rate a stiff spring
-- overshot and shook (active.lua's tone towards a standing pose jittered against the floor), while a speed asked for
-- can't run away, and the floor, the joint limits and her own body still stop her. Each step's change is capped at
-- accel times its time (her muscles' strength). The roll is the same, about the length of her body, on the torso's
-- bodies. Breathing, reflexes and tremors are pulses: a turn whose speed rises and falls as a sine, as convulse.lua's.
-- Steered at most `rate` times a second (each step reads her bones once).

local M = {}
local ctx, try, valid
local function cfg() return ctx.tune.struggle or {} end
local function sub_cfg(k) return (ctx.tune.struggle or {})[k] or {} end
local function log(s) ctx.log("struggle: " .. s) end

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function scale(a, k) return vec(a.X * k, a.Y * k, a.Z * k) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
local function len(a) return math.sqrt(dot(a, a)) end
local function norm(a)
  local l = len(a)
  return l > 1e-4 and scale(a, 1 / l) or nil
end
local function perp(a, n) return sub(a, scale(n, dot(a, n))) end
local function rnd(a, b) return a + math.random() * (b - a) end
local function range(t, d) t = t or d; return rnd(t[1], t[2] or t[1]) end
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function smooth(x) x = clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local function lerp(a, b, k) return add(a, scale(sub(b, a), k)) end
local function sum(...) local o = vec(0, 0, 0); for _, v in ipairs({ ... }) do o = add(o, v) end; return o end
local UP = vec(0, 0, 1)

local P = "Bip001-"
local ARM = { "Clavicle", "UpperArm", "Forearm", "Hand" }
local LEG = { "Thigh", "Calf", "Foot" }
local TORSO = { P .. "Pelvis", P .. "Spine", P .. "Spine1", P .. "Spine2" }
local CORE = { P .. "Pelvis", P .. "Spine", P .. "Spine1", P .. "Spine2", P .. "Neck", P .. "Head" }
-- each bone moved: the body it turns against
local PARENT = {}
for _, s in ipairs({ "L", "R" }) do
  local b = P .. s .. "-"
  PARENT[b .. "Clavicle"], PARENT[b .. "UpperArm"], PARENT[b .. "Forearm"], PARENT[b .. "Hand"] =
    P .. "Spine2", b .. "Clavicle", b .. "UpperArm", b .. "Forearm"
  PARENT[b .. "Thigh"], PARENT[b .. "Calf"], PARENT[b .. "Foot"] = P .. "Pelvis", b .. "Thigh", b .. "Calf"
end
PARENT[P .. "Spine1"], PARENT[P .. "Spine2"], PARENT[P .. "Neck"], PARENT[P .. "Head"] =
  P .. "Spine", P .. "Spine1", P .. "Spine2", P .. "Neck"
-- the bone a bone's far end is (for its direction)
local TIP = {}
for _, s in ipairs({ "L", "R" }) do
  local b = P .. s .. "-"
  TIP[b .. "Clavicle"], TIP[b .. "UpperArm"], TIP[b .. "Forearm"] = b .. "UpperArm", b .. "Forearm", b .. "Hand"
  TIP[b .. "Thigh"], TIP[b .. "Calf"] = b .. "Calf", b .. "Foot"
end
TIP[P .. "Spine1"], TIP[P .. "Spine2"], TIP[P .. "Neck"] = P .. "Spine2", P .. "Neck", P .. "Head"
-- the bodies below a bone that turn with it, down the limb: an upper arm turned alone dragged its forearm and hand,
-- which outweigh it about the shoulder, and they held it still (playtest: 0% of each turn kept)
local DOWN = { [P .. "Spine1"] = { P .. "Spine2", P .. "Neck", P .. "Head" }, [P .. "Spine2"] = { P .. "Neck", P .. "Head" },
  [P .. "Neck"] = { P .. "Head" } }
for _, s in ipairs({ "L", "R" }) do
  local b = P .. s .. "-"
  DOWN[b .. "Clavicle"] = { b .. "UpperArm", b .. "Forearm", b .. "Hand" }
  DOWN[b .. "UpperArm"], DOWN[b .. "Forearm"] = { b .. "Forearm", b .. "Hand" }, { b .. "Hand" }
  DOWN[b .. "Thigh"], DOWN[b .. "Calf"] = { b .. "Calf", b .. "Foot" }, { b .. "Foot" }
end
-- a sit-up's curl: each spine bone (and the bone its far end is), and how far forward it turns at full effort, deg
local CURL = { { P .. "Spine1", P .. "Spine2", 20 }, { P .. "Spine2", P .. "Neck", 40 }, { P .. "Neck", P .. "Head", 60 } }
-- a cut's root: the stub left on her (the bone it was cut from) that jerks on its own. None at a hip or a clavicle
local STUB = { Forearm = "UpperArm", Hand = "Forearm", UpperArm = "Clavicle", Calf = "Thigh", Foot = "Calf" }

local st = nil -- this death: { pawn, mesh, t, plan, act, ... }

function M.init(c)
  ctx = c
  try, valid = c.try, c.valid
end

local function rag() return ctx.rag end
-- (read once a step: st.seen is emptied at each)
local function loc(comp, b)
  local c = st and st.seen
  if c and c[b] ~= nil then return c[b] or nil end
  local v = try(function() local x = comp:GetSocketLocation(FName(b)); return vec(x.X, x.Y, x.Z) end)
  if c then c[b] = v or false end
  return v
end
local function spin(comp, b)
  local c = st and st.spun
  if c and c[b] ~= nil then return c[b] or nil end
  local v = try(function() local x = comp:GetPhysicsAngularVelocityInDegrees(FName(b)); return vec(x.X, x.Y, x.Z) end)
  if c then c[b] = v or false end
  return v
end
-- a change of a body's turn, deg/s: added to its angular velocity (AddAngularImpulseInDegrees as a velocity change did
-- nothing in game: none of a step's turn was there the next, playtest; active.lua's spin cap sets it the same way and
-- holds). The first failure is logged
local function com(comp, b)
  local c, k = st and st.seen, b .. "@com"
  if c and c[k] ~= nil then return c[k] or nil end
  local v = try(function() local x = comp:GetCenterOfMass(FName(b)); return vec(x.X, x.Y, x.Z) end)
  if c then c[k] = v or false end
  return v
end
-- ...and its centre of mass moved round the joint with it (w x r): turned about its middle alone, the joint dragged
-- it back and her limbs kept none of a turn (playtest: 0% kept, an arm swing turned 0 deg). The bodies below it on her
-- (DOWN, up to a cut) turn with it about the same joint, unless alone (a parent's push back, the torso's roll)
local function cut(mesh, b) local r = rag(); return r and r.severed(mesh, b) end
local function push(comp, b, dv, alone)
  local ok, err = pcall(function() comp:SetPhysicsAngularVelocityInDegrees(dv, true, FName(b)) end)
  if not ok and not M.pushFailed then M.pushFailed = true; log("turning a body failed: " .. tostring(err)) end
  if b == P .. "Pelvis" then return end
  local at = loc(comp, b)
  if not at then return end
  local wr, r = scale(dv, math.pi / 180), rag()
  local c = com(comp, b)
  if c then try(function() comp:SetPhysicsLinearVelocity(cross(wr, sub(c, at)), true, FName(b)) end) end
  if alone then return end
  for _, x in ipairs(DOWN[b] or {}) do
    if cut(comp, x) or (r and not r.live(comp, x)) then break end
    try(function() comp:SetPhysicsAngularVelocityInDegrees(dv, true, FName(x)) end)
    local cx = com(comp, x)
    if cx then try(function() comp:SetPhysicsLinearVelocity(cross(wr, sub(cx, at)), true, FName(x)) end) end
  end
end
local function share(b, p)
  local mass = rag() and rag().MASS or {}
  return (mass[b] and mass[p]) and math.min(0.6, mass[b] / mass[p]) or 0.3
end

-- a limb's first bone a cut took (the piece's root), or nil when it is all on her
local function cut_at(mesh, s, parts)
  for _, x in ipairs(parts) do if cut(mesh, P .. s .. "-" .. x) then return P .. s .. "-" .. x end end
end
local function whole(mesh, s, parts)
  if cut_at(mesh, s, parts) then return false end
  local r = rag()
  for i = 2, #parts do if r and not r.live(mesh, P .. s .. "-" .. parts[i]) then return false end end
  return true
end

-- her frame from what is still on her: up her spine, her right, her front. A cut-off arm's or leg's bones lie apart
-- with the piece, so a pair counts only whole, and a single side by where it sits off her middle
local function frame(mesh)
  local p, n = loc(mesh, P .. "Pelvis"), loc(mesh, P .. "Neck")
  local up = p and n and norm(sub(n, p))
  if not up then return nil end
  local r = vec(0, 0, 0)
  for _, set in ipairs({ { "UpperArm", ARM, n }, { "Thigh", LEG, p } }) do
    local onL, onR = not cut_at(mesh, "L", set[2]), not cut_at(mesh, "R", set[2])
    local a, b = onL and loc(mesh, P .. "L-" .. set[1]), onR and loc(mesh, P .. "R-" .. set[1])
    if a and b then r = add(r, sub(b, a))
    elseif a then r = add(r, scale(sub(set[3], a), 2))
    elseif b then r = add(r, scale(sub(b, set[3]), 2)) end
  end
  r = norm(perp(r, up))
  if not r then return nil end
  return { up = up, right = r, front = cross(r, up), pelvis = p, neck = n }
end
-- the way out to a side: her right for R, her left for L
local function out(f, s) return s == "R" and f.right or scale(f.right, -1) end

-- how far round she lies about her length: 0 on her back, +90 on her right side, -90 on her left, 180 face down
local function roll_of(f)
  local z = norm(perp(UP, f.up))
  if not z then return nil end
  return math.deg(math.atan(dot(cross(z, f.front), f.up), dot(z, f.front)))
end
local function wrap(d) return (d + 180) % 360 - 180 end

-- where a stump is: a shoulder or hip by the other side's, mirrored across her; an elbow, wrist, knee or ankle at
-- the far end of the bone it was cut from (along its centre of mass, as long as the other side's)
local function stump(mesh, f, root)
  local s, part = root:match("^Bip001%-(%a)%-(%a+)$")
  if not s then return nil end
  local o = s == "L" and "R" or "L"
  if part == "Clavicle" or part == "UpperArm" or part == "Thigh" then
    local mid = part == "Thigh" and f.pelvis or loc(mesh, P .. "Spine2")
    local other = mid and loc(mesh, P .. o .. "-" .. part)
    if other and not cut(mesh, P .. o .. "-" .. part) then
      local d = sub(other, mid)
      return add(mid, sub(d, scale(f.right, 2 * dot(d, f.right))))
    end
    return mid
  end
  local up = STUB[part]
  local base, c = loc(mesh, P .. s .. "-" .. up), com(mesh, P .. s .. "-" .. up)
  if not base then return nil end
  local dir = c and norm(sub(c, base))
  if not dir then return base end
  local a, b = loc(mesh, P .. o .. "-" .. up), loc(mesh, P .. o .. "-" .. part)
  local l = (a and b and not cut_at(mesh, o, (part == "Calf" or part == "Foot") and LEG or ARM)) and len(sub(b, a))
    or 2 * len(sub(c, base))
  return add(base, scale(dir, l))
end

-- two-bone IK: from the joint at s, bones l1 and l2 long, the end towards t, the middle joint bent towards pole.
-- The two bones' directions and where the end gets to
local function ik(s, t, l1, l2, pole)
  local d = sub(t, s)
  local u = norm(d)
  if not u then return nil end
  local D = clamp(len(d), 0.25 * (l1 + l2), 0.97 * (l1 + l2))
  local ca = clamp((l1 * l1 + D * D - l2 * l2) / (2 * l1 * D), -1, 1)
  local n = norm(perp(pole, u)) or norm(perp(UP, u)) or vec(1, 0, 0)
  local e = add(add(s, scale(u, l1 * ca)), scale(n, l1 * math.sqrt(1 - ca * ca)))
  local tip = add(s, scale(u, D))
  return norm(sub(e, s)), norm(sub(tip, e)), tip
end

-- one bone steered towards direction t against its parent, at strength k (0-1 and over). The speed asked is gain x
-- the angle off plus what the gap has summed to (hold: gravity, the floor and her joints' damping take a steady share
-- of every step's turn, and without it an arm sagged short of where it was sent; the first playtest's limbs barely
-- moved). How much of the turn it set a step is still there the next (kept) is summed for the log: little kept says
-- something else holds the joint, a lot kept and the limb still short says it is too weak
local function servo(mesh, b, t, k, dt)
  local c = cfg()
  local at, tip = loc(mesh, b), TIP[b] and loc(mesh, TIP[b])
  local d = at and tip and norm(sub(tip, at))
  if not (d and t) or k <= 0 then return nil end
  local ang = math.deg(math.acos(clamp(dot(d, t), -1, 1)))
  local ax = norm(cross(d, t))
  local p = PARENT[b]
  local wb, wp = spin(mesh, b), spin(mesh, p)
  if not (wb and wp) then return ang end
  local rel = perp(sub(wb, wp), d) -- (its twist about itself left alone)
  local tr = st.trace[b]
  if tr and st.step == tr.step + 1 then
    local l = len(tr.set)
    if l > 20 then st.kept, st.keptN = st.kept + dot(rel, tr.set) / (l * l), st.keptN + 1 end
  end
  local hold = st.hold[b] or vec(0, 0, 0)
  if ax and ang > 2 then
    hold = add(hold, scale(ax, (c.hold or 8) * ang * dt))
    local hl = len(hold)
    if hl > (c.holdMax or 200) then hold = scale(hold, (c.holdMax or 200) / hl) end
  else
    hold = scale(hold, math.exp(-dt / 0.3))
  end
  st.hold[b] = hold
  local want = add(ax and scale(ax, (c.gain or 8) * ang) or vec(0, 0, 0), hold)
  local wl, top = len(want), (c.speed or 320) * k
  if wl > top then want = scale(want, top / wl) end
  local dv = sub(want, rel)
  if (c.response or 0) > 0 then dv = scale(dv, 1 - math.exp(-dt / c.response)) end
  local cap = (c.accel or 6000) * k * dt
  if len(dv) > cap then dv = scale(dv, cap / len(dv)) end
  push(mesh, b, dv)
  push(mesh, p, scale(dv, -share(b, p)), true)
  st.trace[b] = { step = st.step, set = add(rel, dv) }
  st.err, st.errN = st.err + ang, st.errN + 1
  return ang
end

-- a limb (s, "arm" or "leg") with its end towards point t, the middle joint bent towards pole. How far off the end is
local LIMB = { arm = { "UpperArm", "Forearm", "Hand" }, leg = { "Thigh", "Calf", "Foot" } }
local function reach(mesh, s, kind, t, pole, k, dt)
  local b = P .. s .. "-"
  local j = LIMB[kind]
  local a, m, e = loc(mesh, b .. j[1]), loc(mesh, b .. j[2]), loc(mesh, b .. j[3])
  if not (a and m and e) then return nil end
  local d1, d2 = ik(a, t, len(sub(m, a)), len(sub(e, m)), pole)
  if not d1 then return nil end
  servo(mesh, b .. j[1], d1, k, dt)
  servo(mesh, b .. j[2], d2, k, dt)
  return len(sub(e, t))
end
-- a limb's length, shoulder or hip to wrist or ankle
local function limb_len(mesh, s, kind)
  local b, j = P .. s .. "-", LIMB[kind]
  local a, m, e = loc(mesh, b .. j[1]), loc(mesh, b .. j[2]), loc(mesh, b .. j[3])
  return a and m and e and (len(sub(m, a)) + len(sub(e, m))), a
end

-- her torso rolled about her length towards `want` degrees (roll_of's)
local function roll(mesh, f, want, k, dt)
  local c = sub_cfg("roll")
  local now = roll_of(f)
  if not now then return nil end
  local err = wrap(want - now)
  local sp = clamp(err * (c.gain or 2.5), -(c.speed or 70) * k, (c.speed or 70) * k)
  local w = spin(mesh, P .. "Spine1")
  local cur = w and dot(w, f.up) or 0
  local dv = (sp - cur) * (1 - math.exp(-dt / 0.15))
  local cap = (c.accel or 400) * k * dt
  dv = clamp(dv, -cap, cap)
  for _, b in ipairs(TORSO) do push(mesh, b, scale(f.up, dv), true) end
  st.rollMin, st.rollMax = math.min(st.rollMin or now, now), math.max(st.rollMax or now, now)
  return now
end

-- ---- pulses: a bone turned about an axis, its speed a sine over dur (breaths, reflexes, tremors) ----
local function pulse(b, axis, amp, dur, at, trem, hz)
  if not (PARENT[b] and axis) then return end
  st.pulses[#st.pulses + 1] = { b = b, p = PARENT[b], a = axis, amp = amp, dur = dur, at = at, v = 0, trem = trem, hz = hz,
    ph = math.random() * 2 * math.pi }
end
-- each pulse steers its bone's turn against its parent along its axis to the speed asked now (closed loop, at most
-- accel deg/s^2): adding only the change of it, gravity took the lot (convulse.lua's arm swings showed none, playtest).
-- Pulses on one bone in the same step add up
local function pulses_tick(mesh, dt)
  local keep, now, seen = {}, st.t, {}
  local cap = (cfg().accel or 6000) * math.max(dt or 0, 1 / 120)
  for _, p in ipairs(st.pulses) do
    if now >= p.at then
      local x = math.min(1, (now - p.at) / p.dur)
      local v = p.amp * math.sin(math.pi * x)
      if p.trem then v = v + p.trem * math.sin(math.pi * x) ^ 0.5 * math.sin(2 * math.pi * p.hz * (now - p.at) + p.ph) end
      local dv = v - p.v
      p.v = v
      local sb = seen[p.b]
      if not sb then
        local wb, wp = spin(mesh, p.b), spin(mesh, p.p)
        sb = { rel = wb and sub(wb, wp or vec(0, 0, 0)) or vec(0, 0, 0), T = vec(0, 0, 0), A = vec(0, 0, 0) }
        seen[p.b] = sb
      end
      local d = clamp(v + dot(sb.T, p.a) - dot(add(sb.rel, sb.A), p.a), -cap, cap)
      sb.T, sb.A = add(sb.T, scale(p.a, v)), add(sb.A, scale(p.a, d))
      push(mesh, p.b, scale(p.a, d))
      -- (the parent pushed back for the change asked, not for what gravity took)
      push(mesh, p.p, scale(p.a, -dv * share(p.b, p.p)), true)
      if x < 1 then keep[#keep + 1] = p end
    else
      keep[#keep + 1] = p
    end
  end
  st.pulses = keep
end
-- a random direction square to bone b
local function across(mesh, b)
  local a, t = loc(mesh, b), TIP[b] and loc(mesh, TIP[b])
  local d = a and t and norm(sub(t, a))
  local r = vec(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))
  return d and norm(perp(r, d)) or norm(r)
end

-- ---- what she has: limbs on, stumps, the pieces cut off her ----
-- (alone: the roll for a plan of sit-up tries only, made already: an animated fall's, before her bodies simulated,
-- when every limb read as off her)
local function pick(mesh, alone)
  for _, b in ipairs(CORE) do if cut(mesh, b) then return nil, "her body is cut through" end end
  local g = ctx.gore
  if g and g.cuts_on and select(2, g.cuts_on(mesh)) == true then return nil, "split" end
  local arms, legs, stumps = {}, {}, {}
  for _, s in ipairs({ "L", "R" }) do
    if whole(mesh, s, ARM) then arms[#arms + 1] = s end
    if whole(mesh, s, LEG) then legs[#legs + 1] = s end
    local a, l = cut_at(mesh, s, ARM), cut_at(mesh, s, LEG)
    if a then stumps[#stumps + 1] = a end
    if l then stumps[#stumps + 1] = l end
  end
  -- the worst first (a shoulder over a hip over an elbow, ...)
  local function rank(x)
    for i, p in ipairs({ "Clavicle", "UpperArm", "Thigh", "Forearm", "Calf", "Hand", "Foot" }) do if x:find(p) then return i end end
    return 9
  end
  table.sort(stumps, function(a, b) return rank(a) < rank(b) end)
  if #stumps == 0 then
    if alone == nil then alone = math.random() < (sub_cfg("rise").alone or 0.5) end
    if alone then return { alone = true, arms = arms, legs = legs, stumps = stumps } end
    return nil, "no limb cut"
  end
  return { arms = arms, legs = legs, stumps = stumps, wound = stumps[1] }
end

local function side_name(s) return s == "L" and "left" or "right" end
local function wound_name(root)
  local s, part = root:match("^Bip001%-(%a)%-(%a+)$")
  local where = ({ Clavicle = "shoulder", UpperArm = "shoulder", Forearm = "elbow", Hand = "wrist", Thigh = "hip",
    Calf = "knee", Foot = "ankle" })[part] or part
  return side_name(s) .. " " .. where
end
local function piece_name(root)
  local s, part = root:match("^Bip001%-(%a)%-(%a+)$")
  local what = ({ Clavicle = "arm", UpperArm = "arm", Forearm = "forearm", Hand = "hand", Thigh = "leg", Calf = "shin",
    Foot = "foot" })[part] or part
  return side_name(s) .. " " .. what
end

-- ---- her legs ----
-- drawn up towards her chest (d 1) or kicked out (0), the knee to her front
local function leg_to(mesh, f, ls, d, k, dt, front)
  local L, hip = limb_len(mesh, ls, "leg")
  if not L then return end
  local o = add(hip, add(scale(f.up, -0.92 * L), scale(f.front, 0.05 * L)))
  local drawn = add(hip, add(scale(f.up, -0.45 * L), scale(f.front, (front or 0.4) * L)))
  reach(mesh, ls, "leg", lerp(o, drawn, d), f.front, k, dt)
end
-- each leg drawing up and kicking out on its own clock
local function kick(mesh, f, legs, k, dt)
  for _, ls in ipairs(legs) do
    local l = st.legClock[ls]
    if st.t >= l.next then
      l.drawn = not l.drawn
      l.next = st.t + (l.drawn and rnd(0.9, 2.2) or rnd(0.6, 1.4)) / st.pace
      l.from, l.at = l.k or 0, st.t
      if l.drawn then st.draws = st.draws + 1 end
    end
    l.k = (l.from or 0) + ((l.drawn and 1 or 0) - (l.from or 0)) * smooth((st.t - (l.at or 0)) / 0.5)
    leg_to(mesh, f, ls, l.k, k * 0.8, dt)
  end
end
-- braced: knees up, feet flat on the floor near her
local function brace(mesh, f, legs, k, dt)
  for _, ls in ipairs(legs) do
    local L, hip = limb_len(mesh, ls, "leg")
    if L then reach(mesh, ls, "leg", add(hip, add(scale(f.up, -0.5 * L), scale(f.front, -0.12 * L))), f.front, k, dt) end
  end
end
-- face down, one after the other: a knee drawn in under her and shoved back
local function scrabble(mesh, f, legs, x, k, dt)
  for i, ls in ipairs(legs) do
    local L, hip = limb_len(mesh, ls, "leg")
    if L then
      local y = i == 2 and (x + 0.5) % 1 or x
      local d = y < 0.5 and smooth(y / 0.5) or 1 - smooth((y - 0.5) / 0.5)
      local t = add(lerp(add(hip, scale(f.up, -0.95 * L)), add(hip, scale(f.up, -0.4 * L)), d), scale(f.front, 0.3 * L * d))
      reach(mesh, ls, "leg", t, f.front, k, dt)
    end
  end
end

-- ---- the acts: each { start(a, f), tick(a, f, k, dt) -> true when done, done(a) -> its log line } ----
local ACT = {}

-- the hand on the stump, rolling, the legs kicking
ACT.clutch = {
  start = function(a, f)
    a.dur = range(sub_cfg("acts").clutch, { 3, 5 }) / st.pace
    a.slip, a.from, a.to, a.st, a.next = vec(0, 0, 0), vec(0, 0, 0), vec(0, 0, 0), 0, rnd(0.8, 1.6)
    a.shake = norm(vec(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))) or UP
    a.rockT = rnd(2.2, 3.4)
    return string.format("%s hand to the %s stump", side_name(st.plan.arms[1]), wound_name(st.plan.wound))
  end,
  tick = function(a, f, k, dt)
    local mesh, s = st.mesh, st.plan
    local spot = stump(mesh, f, s.wound)
    if not spot then return true end
    local ws = s.wound:match("^Bip001%-(%a)%-")
    local leg = s.wound:find("Thigh") or s.wound:find("Calf") or s.wound:find("Foot")
    if a.t >= a.next then
      a.next = a.t + rnd(1.2, 2.8)
      a.from, a.to, a.st = a.slip, vec(rnd(-5, 5), rnd(-5, 5), rnd(-5, 5)), a.t
    end
    a.slip = lerp(a.from, a.to, smooth((a.t - a.st) / 0.4))
    local tremor = scale(a.shake, (cfg().shake or 1.2) * math.sin(2 * math.pi * 7 * a.t) * math.min(k, 1))
    for i, h in ipairs(s.arms) do
      local sh = loc(mesh, P .. h .. "-UpperArm")
      if sh and (leg or i == 1) then
        local toward = norm(sub(spot, sh))
        local t = add(add(spot, a.slip), tremor)
        if toward then t = sub(t, scale(toward, 7)) end
        if i == 2 then t = add(t, scale(f.right, h == "R" and 6 or -6)) end
        local off = reach(mesh, h, "arm", t, add(scale(f.up, -1), scale(f.front, 0.6)), k, dt)
        if off and off < (a.closest or 1e9) then a.closest = off end
      end
    end
    local rc = sub_cfg("roll")
    local wave = math.sin(2 * math.pi * a.t / a.rockT)
    roll(mesh, f, leg and 0.4 * (rc.rock or 25) * wave
      or (ws == "L" and 1 or -1) * ((rc.side or 55) - (rc.rock or 25) * (0.5 + 0.5 * wave)), k, dt)
    kick(mesh, f, s.legs, k, dt)
    return a.t >= a.dur
  end,
  done = function(a) return string.format("hand came within %.0f cm of the stump", a.closest or -1) end,
}

-- a hand stretching towards a piece cut off her, falling short
ACT.reach = {
  start = function(a, f)
    local mesh = st.mesh
    local best
    for _, root in ipairs(st.plan.stumps) do
      local at = loc(mesh, root)
      for _, h in ipairs(st.plan.arms) do
        local L, sh = limb_len(mesh, h, "arm")
        local d = at and sh and len(sub(at, sh))
        if d and d < L * (sub_cfg("reach").within or 3) and d > L * 0.4 and (not best or d < best.d) then
          best = { root = root, h = h, d = d, L = L }
        end
      end
    end
    if not best then st.reached = 2; return nil end
    a.root, a.h, a.d = best.root, best.h, best.d
    a.dur = range(sub_cfg("acts").reach, { 2.5, 3.5 }) / st.pace
    st.reached = (st.reached or 0) + 1
    local cv = ctx.convulse
    local said = cv and cv.effort and (try(function() return cv.effort(a.dur * 0.8, 0.6) end) or "") or ""
    return string.format("%s hand reaching for her %s, %.0f cm off%s", side_name(a.h), piece_name(a.root), a.d, said)
  end,
  tick = function(a, f, k, dt)
    local mesh = st.mesh
    local at = loc(mesh, a.root)
    if not at then return true end
    local x = a.t / a.dur
    -- (out over the first part, straining, then let go: the arm drops)
    local e = x < 0.8 and smooth(x / 0.25) or 1 - smooth((x - 0.8) / 0.2)
    local t = add(add(at, vec(0, 0, 8)), scale(UP, 1.5 * math.sin(2 * math.pi * 9 * a.t)))
    local pole = add(scale(out(f, a.h), 0.6), scale(f.up, -0.6))
    local off = reach(mesh, a.h, "arm", t, pole, k * 1.1 * e, dt)
    if off and off < (a.closest or 1e9) then a.closest = off end
    -- (leaning over towards it)
    local toward = dot(sub(at, f.neck), f.right) > 0 and 1 or -1
    roll(mesh, f, toward * 35 * e, k, dt)
    kick(mesh, f, st.plan.legs, k * 0.5, dt)
    return a.t >= a.dur
  end,
  done = function(a) return string.format("her hand got within %.0f cm of it", a.closest or -1) end,
}

-- on her back: an arm across her, rolling over onto her front
ACT.turn = {
  start = function(a, f)
    a.h = st.plan.arms[math.random(#st.plan.arms)]
    a.way = a.h == "R" and -1 or 1 -- (the right arm reaching over to her left rolls her onto her left side)
    a.dur = range(sub_cfg("acts").turn, { 2.5, 3.5 }) / st.pace
    return string.format("turning onto her front, %s arm across", side_name(a.h))
  end,
  tick = function(a, f, k, dt)
    local mesh = st.mesh
    local L, sh = limb_len(st.mesh, a.h, "arm")
    if L then
      local t = sum(sh, scale(out(f, a.h), -0.8 * L), scale(f.front, -0.2 * L), scale(f.up, 0.1 * L))
      reach(mesh, a.h, "arm", t, add(scale(f.up, -0.7), scale(f.front, 0.5)), k, dt)
    end
    local now = roll(mesh, f, a.way * 175, k * 1.3, dt)
    kick(mesh, f, st.plan.legs, k * 0.6, dt)
    if now and math.abs(now) > 140 then a.over = true; st.force = "crawl"; return true end
    return a.t >= a.dur
  end,
  done = function(a) return a.over and "over onto her front" or "didn't get over" end,
}

-- face down: a hand reaching out past her head, planting, dragging her forward, the other after it
ACT.crawl = {
  start = function(a, f)
    a.dur = range(sub_cfg("acts").crawl, { 3.5, 5.5 }) / st.pace
    a.T = rnd(1.1, 1.5) / st.pace
    a.from = loc(st.mesh, P .. "Pelvis")
    return string.format("crawling, %s", #st.plan.arms > 1 and "both arms" or (side_name(st.plan.arms[1]) .. " arm"))
  end,
  tick = function(a, f, k, dt)
    local mesh = st.mesh
    local r = roll_of(f) or 180
    if math.abs(r) < 110 then return true end -- (rolled off her front)
    local away = scale(f.front, -1) -- (up off the floor: face down her front is the floor)
    for i, h in ipairs(st.plan.arms) do
      local L, sh = limb_len(mesh, h, "arm")
      if L then
        local x = (a.t / a.T + (i - 1) * 0.5) % 1
        local ahead = sum(sh, scale(f.up, 0.8 * L), scale(out(f, h), 0.15 * L))
        local pulled = sum(sh, scale(f.up, -0.1 * L), scale(out(f, h), 0.3 * L), scale(f.front, 4))
        local t, kk
        if x < 0.35 then t, kk = add(lerp(pulled, ahead, smooth(x / 0.35)), scale(away, 10 * math.sin(math.pi * x / 0.35))), 1
        elseif x < 0.45 then t, kk = add(ahead, scale(f.front, 4)), 1
        else t, kk = lerp(add(ahead, scale(f.front, 4)), pulled, smooth((x - 0.45) / 0.55)), 1.3 end
        local pole = sum(scale(out(f, h), 0.7), scale(away, 0.5), scale(f.up, -0.3))
        reach(mesh, h, "arm", t, pole, k * kk, dt)
      end
    end
    scrabble(mesh, f, st.plan.legs, (a.t / (a.T * 1.3)) % 1, k * 0.8, dt)
    roll(mesh, f, (r > 0 and 1 or -1) * 180, k * 0.5, dt)
    return a.t >= a.dur
  end,
  done = function(a)
    local p = loc(st.mesh, P .. "Pelvis")
    return string.format("dragged herself %.0f cm", p and a.from and len(sub(p, a.from)) or -1)
  end,
}

-- on her back: trying to sit up (or prop up on an elbow, a.h), her belly curling her chest and head up, shaking,
-- feet braced, giving out. The curl's directions are fixed in the world as she lay at its start (her own frame turns
-- with the curl, and a target riding it ran on ahead)
local function rise_start(a, f, prop)
  local c = sub_cfg("rise")
  st.tries = st.tries + 1
  a.dur, a.hz = range(c.time, { 1.0, 1.8 }), rnd(8, 11)
  a.give = c.give or 0.4
  a.up, a.front, a.right = f.up, f.front, f.right
  a.k = (0.75 ^ (st.tries - 1)) * rnd(0.85, 1.1)
  a.top = 0
  if prop then a.h = st.plan.arms[math.random(#st.plan.arms)] end
  local cv = ctx.convulse
  a.said = cv and cv.effort and (try(function() return cv.effort(a.dur + a.give, a.k) end) or "") or ""
  return (prop and string.format("propping up on her %s elbow", side_name(a.h)) or "trying to sit up") .. a.said
end
local function rise_tick(a, f, k, dt)
  local c, mesh = sub_cfg("rise"), st.mesh
  local e = a.t < a.dur and smooth(a.t / 0.35) or 1 - smooth((a.t - a.dur) / a.give)
  local pk = k * a.k * (c.power or 1.5) * e
  local shake = (c.shake or 4) * math.sin(2 * math.pi * a.hz * a.t)
  for i, cl in ipairs(CURL) do
    local ang = math.rad(cl[3] * (c.curl or 1) * (a.h and 0.8 or 1) + (i > 1 and shake or 0))
    servo(mesh, cl[1], add(scale(a.up, math.cos(ang)), scale(a.front, math.sin(ang))), pk, dt)
  end
  if a.h then
    -- the elbow under her: the upper arm down to the floor beside her, the forearm flat along it towards her feet
    local o = a.h == "R" and a.right or scale(a.right, -1)
    local b = P .. a.h .. "-"
    servo(mesh, b .. "UpperArm", norm(sum(scale(a.front, -0.85), scale(a.up, -0.35), scale(o, 0.25))), pk, dt)
    servo(mesh, b .. "Forearm", norm(sum(scale(a.up, -0.7), scale(o, 0.35), scale(a.front, -0.25))), pk, dt)
    roll(mesh, f, (a.h == "R" and 1 or -1) * 25, k, dt)
  else
    roll(mesh, f, 0, k, dt)
  end
  brace(mesh, f, st.plan.legs, k, dt)
  local s2, n = loc(mesh, P .. "Spine2"), loc(mesh, P .. "Neck")
  local d = s2 and n and norm(sub(n, s2))
  if d then a.top = math.max(a.top, math.deg(math.acos(clamp(dot(d, a.up), -1, 1)))) end
  return a.t >= a.dur + a.give
end
local function rise_done(a)
  st.risen = math.max(st.risen or 0, a.top)
  return string.format("her chest turned up to %.0f deg off the floor", a.top)
end
ACT.rise = { start = function(a, f) return rise_start(a, f, false) end, tick = rise_tick, done = rise_done, effort = true }
ACT.prop = { start = function(a, f) return rise_start(a, f, true) end, tick = rise_tick, done = rise_done, effort = true }

-- no arm: heels shoving her along on her back; face down, scrabbling and trying to turn over; on her side, onto her
-- back first
ACT.push = {
  start = function(a, f)
    a.dur = range(sub_cfg("acts").push, { 3.5, 5.5 }) / st.pace
    a.from = loc(st.mesh, P .. "Pelvis")
    a.period, a.cycle, a.n = rnd(1.5, 2.1) / st.pace, -1, 0
    a.turnAt, a.turnTo = rnd(1, 2), 0
    a.rockT = rnd(2.2, 3.4)
    return string.format("pushing with %d leg%s", #st.plan.legs, #st.plan.legs == 1 and "" or "s")
  end,
  tick = function(a, f, k, dt)
    local mesh, c, legs = st.mesh, sub_cfg("push"), st.plan.legs
    local r = roll_of(f) or 0
    local down = math.abs(r) > 110
    if math.abs(r) > 50 and not down then
      roll(mesh, f, 0, k, dt)
    elseif down then
      if a.t >= a.turnAt then a.turnAt, a.turnTo = a.t + rnd(2.5, 4.5), (math.random() < 0.5 and 1 or -1) * rnd(70, 110) end
      roll(mesh, f, a.t < a.turnAt - 1.5 and a.turnTo or r, k, dt)
    else
      roll(mesh, f, 6 * math.sin(2 * math.pi * a.t / a.rockT), k, dt)
    end
    if down then
      scrabble(mesh, f, legs, (a.t / a.period) % 1, k, dt)
      return a.t >= a.dur
    end
    -- one push: bend (feet drawn up, lifted off the floor) then drive (heels pressed down and shoved out)
    local x = (a.t % a.period) / a.period
    local cycle = math.floor(a.t / a.period)
    if cycle ~= a.cycle then a.cycle, a.n = cycle, a.n + 1 end
    local bend = c.bend or 0.55
    for _, ls in ipairs(legs) do
      local L, hip = limb_len(mesh, ls, "leg")
      if L then
        local d, lift
        if x < bend then d, lift = smooth(x / bend), 8 * math.sin(math.pi * x / bend)
        else d, lift = 1 - smooth((x - bend) / (1 - bend)), -(c.press or 10) end
        local t = add(lerp(add(hip, scale(f.up, -0.95 * L)), add(hip, scale(f.up, -0.4 * L)), d), scale(f.front, lift - 4))
        reach(mesh, ls, "leg", t, f.front, k, dt)
      end
    end
    return a.t >= a.dur
  end,
  done = function(a)
    local p = loc(st.mesh, P .. "Pelvis")
    return string.format("%d pushes, her pelvis moved %.0f cm", a.n, p and a.from and len(sub(p, a.from)) or -1)
  end,
}

-- curling up tight: knees to her chest, arms in round her head, rocking a little
ACT.curl = {
  start = function(a, f)
    a.dur = range(sub_cfg("acts").curl, { 2, 3.5 }) / st.pace
    a.rockT = rnd(1.6, 2.4)
    a.way = math.random() < 0.5 and 1 or -1
    -- (her back's rounding fixed in the world as she lay: a target riding her own frame ran on ahead)
    a.back = norm(add(scale(f.up, math.cos(math.rad(20))), scale(f.front, math.sin(math.rad(20)))))
    return "curling up"
  end,
  tick = function(a, f, k, dt)
    local mesh = st.mesh
    local e = smooth(a.t / 0.6)
    local head = loc(mesh, P .. "Head")
    for _, h in ipairs(st.plan.arms) do
      if head then
        local t = sum(head, scale(f.front, 14), scale(out(f, h), 8), scale(f.up, -6))
        reach(mesh, h, "arm", t, add(scale(f.up, -1), scale(out(f, h), 0.4)), k * e, dt)
      end
    end
    for _, ls in ipairs(st.plan.legs) do leg_to(mesh, f, ls, 1, k * e, dt, 0.55) end
    roll(mesh, f, a.way * (60 + 15 * math.sin(2 * math.pi * a.t / a.rockT)), k * 0.8, dt)
    -- (her back rounding a little)
    servo(mesh, P .. "Spine2", a.back, k * 0.6 * e, dt)
    return a.t >= a.dur
  end,
  done = function() return "" end,
}

-- lying still a moment, only breathing
ACT.lie = {
  start = function(a) a.dur = range(sub_cfg("acts").lie, { 0.8, 1.8 }) / st.pace; return "lying still" end,
  tick = function(a) return a.t >= a.dur end,
  done = function() return "" end,
}

-- which acts she can do now, weighted (tune.struggle.weights), the last one less likely again
local function choose(f, v)
  local s = st.plan
  local r = roll_of(f) or 0
  local back, down = math.abs(r) < 60, math.abs(r) > 120
  local w = sub_cfg("weights")
  local arms, legs = #s.arms > 0, #s.legs > 0
  -- (sitting up takes what she has: not once she has faded below rise.least)
  local tries = st.tries < (st.triesMax or 0) and v >= (sub_cfg("rise").least or 0.4)
  local opts = {}
  local function opt(name, ok, weight) if ok and (weight or 0) > 0 then opts[#opts + 1] = { name, weight } end end
  if s.alone then
    opt("rise", back and tries, w.rise or 1)
    opt("prop", back and tries and arms, w.prop or 1)
    opt("lie", true, 1.5)
  else
    opt("clutch", arms and s.wound, w.clutch or 3)
    opt("reach", arms and (st.reached or 0) < 2, w.reach or 1.5)
    opt("turn", arms and back and not st.dimmed, w.turn or 0.8)
    opt("crawl", arms and down, w.crawl or 3)
    opt("rise", back and tries, w.rise or 1)
    opt("prop", back and tries and arms, w.prop or 1)
    opt("push", not arms, w.push or 3)
    opt("curl", arms or legs, w.curl or 0.8)
    opt("lie", true, w.lie or 0.6)
  end
  if st.force then
    for _, o in ipairs(opts) do if o[1] == st.force then st.force = nil; return o[1] end end
    st.force = nil
  end
  local total = 0
  for _, o in ipairs(opts) do
    if o[1] == st.lastAct and o[1] ~= "clutch" and o[1] ~= "crawl" and o[1] ~= "push" then o[2] = o[2] * 0.3 end
    total = total + o[2]
  end
  local x = math.random() * total
  for _, o in ipairs(opts) do x = x - o[2]; if x <= 0 then return o[1] end end
  return opts[#opts] and opts[#opts][1] or "lie"
end

-- ---- her life running out ----
-- how much she has left at t (bleed): above 1 in the first frantic share, down to bleed.low by bleed.last, then to
-- nothing as she dies. raw: without the strength setting and the half second her strength comes up over (the pace
-- of her acts goes by it: an act picked as the struggle began ran twice as long)
local function vitality(t, raw)
  local c, x = sub_cfg("bleed"), t / st.total
  local fr, last, low = c.frantic or 0.25, c.last or 0.85, c.low or 0.25
  local v
  if x < fr then v = 1 + (c.surge or 0.3) * (1 - x / fr)
  elseif x < last then v = 1 - (1 - low) * smooth((x - fr) / (last - fr))
  else v = low * (1 - smooth((x - last) / (1 - last))) end
  if raw then return v end
  return v * smooth(t / 0.5) * (cfg().strength or 1.0)
end

-- breathing: the chest heaving (her upper spine tilting back and forth against the lower), fast and deep while she
-- fights, slow and shallow as she fades; a last deep one as she dies, then none
local function breathe(mesh, f, v, dt)
  local c = sub_cfg("breath")
  if c.enabled == false or st.breathless then return end
  local frac = clamp(v, 0, 1.3)
  local T = (c.slow or 2.6) + ((c.fast or 0.75) - (c.slow or 2.6)) * clamp(frac, 0, 1)
  local A = (c.depth or 4) * (0.35 + 0.65 * clamp(frac, 0, 1.3))
  if st.lastBreath then T, A = 1.6, (c.depth or 4) * 1.6 end
  st.breathPh = (st.breathPh or 0) + dt * 2 * math.pi / T
  local w = A * (2 * math.pi / T) * math.cos(st.breathPh)
  local dv = w - (st.breathW or 0)
  st.breathW = w
  push(mesh, P .. "Spine2", scale(f.right, dv))
  push(mesh, P .. "Spine1", scale(f.right, -dv * 0.5), true)
  if st.lastBreath and st.breathPh >= st.lastBreath then st.breathless = true; log(string.format("%.1f s: her last breath", st.t)) end
end

-- the stumps' reflexes: the stub left on her jerking and quivering on its own, more often while she is strong
local function reflexes(mesh, v)
  local c = sub_cfg("reflex")
  if c.enabled == false or v < 0.05 then return end
  for _, root in ipairs(st.plan.stumps) do
    local s, part = root:match("^Bip001%-(%a)%-(%a+)$")
    local stub = s and STUB[part] and (P .. s .. "-" .. STUB[part])
    if stub and not cut(mesh, stub) then
      local at = st.reflexAt[root] or rnd(0.2, 1.0)
      if st.t >= at then
        local n = math.random(1, 3)
        local t0 = st.t
        for i = 1, n do
          pulse(stub, across(mesh, stub), (c.speed or 140) * math.min(v, 1.2) * rnd(0.7, 1.1), rnd(0.1, 0.18), t0,
            (c.quiver or 40) * math.min(v, 1), rnd(10, 14))
          t0 = t0 + rnd(0.15, 0.3)
        end
        st.reflexAt[root] = t0 + rnd(0.4, 1.4) / math.max(v, 0.25)
        st.reflexes = st.reflexes + n
      else
        st.reflexAt[root] = at
      end
    end
  end
end

-- dying: a few last tremors in the hands and feet still on her, a last breath, her head rolling aside
local function die_start(mesh, f)
  st.dying = true
  local ends = {}
  for _, s in ipairs(st.plan.arms) do ends[#ends + 1] = P .. s .. "-Hand" end
  for _, s in ipairs(st.plan.legs) do ends[#ends + 1] = P .. s .. "-Foot" end
  local n = 0
  for i = 1, math.min(#ends, math.random(2, 4)) do
    local b = ends[math.random(#ends)]
    pulse(b, across(mesh, b) or f.front, rnd(60, 110), rnd(0.08, 0.12), st.t + rnd(0, 0.9), 30, rnd(9, 13))
    n = n + 1
  end
  -- (at least half a breath more, ending where her chest stands still, at most 1.6 s off)
  st.lastBreath = math.pi / 2 + math.ceil(((st.breathPh or 0) + math.pi / 2) / math.pi) * math.pi
  -- (her face turning away: a turn of the head about her neck, gravity takes it on)
  if not cut(mesh, P .. "Head") then
    pulse(P .. "Head", scale(f.up, math.random() < 0.5 and 1 or -1), rnd(90, 130), rnd(0.6, 0.8), st.t + rnd(0.4, 0.8))
  end
  log(string.format("%.1f s: dying, %d last tremors, her head rolling aside", st.t, n))
end

-- a struggle still to come or running (active.lua keeps her bodies awake for it)
function M.due() return st ~= nil and not st.done end
function M.busy()
  if not (st and st.began and not st.done) then return false end
  return not st.plan.alone or (st.act ~= nil and ACT[st.act.name].effort == true)
end
function M.rising() return st ~= nil and st.act ~= nil and ACT[st.act.name].effort == true end

-- ---- the death ----
function M.start(pawn, mesh)
  M.stop()
  if cfg().enabled == false or ctx.tune.deathMoves ~= true then return end -- (parked: tune.deathMoves)
  st = { pawn = pawn, mesh = mesh, t = 0, last = os.clock(), acc = 0 }
end

local function begin(mesh, plan)
  local tt = cfg().time or { 8, 12 }
  st.plan, st.began, st.t = plan, true, 0
  st.total = rnd(tt[1], tt[2] or tt[1])
  st.legClock = { L = { next = rnd(0.2, 0.8) }, R = { next = rnd(0.5, 1.3) } }
  st.pulses, st.reflexAt, st.reflexes, st.draws, st.tries = {}, {}, 0, 0, 0
  st.trace, st.hold, st.step, st.kept, st.keptN, st.err, st.errN = {}, {}, 0, 0, 0, 0, 0
  local tries = sub_cfg("rise").tries or { 1, 3 }
  st.triesMax = math.random(tries[1], tries[2] or tries[1])
  st.acts, st.pace, st.nextTry = {}, 1, rnd(1.0, 2.5)
  st.start = loc(mesh, P .. "Pelvis")
  try(function() mesh:WakeAllRigidBodies() end)
  local f = frame(mesh)
  local r = f and roll_of(f)
  local arms = {}
  for _, h in ipairs(plan.arms) do arms[#arms + 1] = side_name(h) end
  log(string.format("%s, %s arm%s and %d leg%s on, for %.1f s, lying at %.0f deg (0 on her back, 180 face down)",
    plan.alone and "no limb cut: tries to sit up only" or ("stumps: " .. table.concat((function()
      local o = {}; for _, x in ipairs(plan.stumps) do o[#o + 1] = wound_name(x) end; return o end)(), ", ")),
    #arms > 0 and table.concat(arms, " and ") or "no", #arms == 1 and "" or "s", #plan.legs, #plan.legs == 1 and "" or "s",
    st.total, r or -1))
end

local function step(mesh, dt)
  local r = rag()
  local v = vitality(st.t)
  st.pace = 0.5 + 0.5 * clamp(vitality(st.t, true), 0, 1.3)
  if st.plan.alone and not st.act then
    -- (between its tries she settles as she would)
  else
    r.twitch(0.6)
    st.wake = (st.wake or 0) - dt
    if st.wake <= 0 then st.wake = 0.5; try(function() mesh:WakeAllRigidBodies() end) end
  end
  local f = frame(mesh)
  if not f then return end
  if not st.plan.alone then breathe(mesh, f, v, dt) end
  pulses_tick(mesh, dt)
  if st.dying then return end
  if st.t >= st.total * (sub_cfg("bleed").last or 0.85) then
    if st.act then log(string.format("%.1f s: %s cut short", st.t, st.act.name)); st.act = nil end
    if not st.plan.alone then die_start(mesh, f) end
    st.dying = true
    return
  end
  if not st.plan.alone then reflexes(mesh, v) end
  local a = st.act
  if not a then
    if st.plan.alone and st.t < st.nextTry then return end
    local name = choose(f, vitality(st.t, true))
    if st.plan.alone and name == "lie" then st.nextTry = st.t + rnd(1.5, 3.0); return end
    a = { name = name, t = 0 }
    local what = ACT[name].start(a, f)
    if not what then st.lastAct = name; return end -- (nothing to do it with: picked again next step)
    st.act = a
    st.acts[#st.acts + 1] = name
    st.kept, st.keptN, st.err, st.errN = 0, 0, 0, 0
    if cfg().log ~= false then log(string.format("%.1f s: %s (strength %.2f)", st.t, what, v)) end
    if (name == "rise" or name == "prop") and st.plan.alone then r.twitch(0.6); try(function() mesh:WakeAllRigidBodies() end) end
  end
  a.t = a.t + dt
  if ACT[a.name].tick(a, f, v, dt) then
    local line = ACT[a.name].done(a)
    -- (how her joints followed: the angle they were off by on average, the share of each step's turn still there
    -- the next)
    local how = st.errN > 0 and string.format("joints off by %.0f deg on average, %.0f%% of each turn kept", st.err / st.errN,
      st.keptN > 0 and 100 * st.kept / st.keptN or -1) or "no joint steered"
    if cfg().log ~= false then log(string.format("%.1f s: %s over: %s%s", st.t, a.name, line ~= "" and (line .. "; ") or "", how)) end
    st.act, st.lastAct = nil, a.name
    if a.name == "turn" and not a.over then st.dimmed = true end
    if st.plan.alone then st.nextTry = st.t + rnd(2.0, 4.0) end
  end
end

function M.tick(paused)
  if not st or st.done then return end
  local now = os.clock()
  local dt = math.min(now - st.last, 0.1)
  st.last = now
  if not valid(st.gs) then st.gs = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
  paused = paused or (valid(st.gs) and try(function() return st.gs:IsGamePaused(st.pawn) end))
  if paused or not valid(st.mesh) or dt <= 0 then return end
  local r = rag()
  local v = r and r.view()
  local mesh = st.mesh
  if not st.began then
    st.wait = (st.wait or 0) + dt
    if ctx.animated and ctx.animated() then
      -- her animated fall's end pose: once it rests (the convulsions began on it), a maimed one goes limp as she
      -- lies (a quiet ragdoll: no blow, no momentum), to struggle from there
      local cv = ctx.convulse
      if st.quietTried or not (cv and cv.resting and cv.resting()) then return end
      st.quietTried = true
      local plan, why = pick(mesh)
      if not plan then st.done = true; log("none: " .. why .. " (an animated death)"); return end
      if cfg().animated == false or not ctx.ragdoll_quiet then st.done = true; log("none: an animated death (struggle.animated off)"); return end
      st.plan0 = plan
      log("her animated fall has come to rest: going limp as she lies, to struggle")
      ctx.ragdoll_quiet("to struggle")
      return
    end
    if not (v and v.mesh == mesh) then return end
    -- (from a quiet ragdoll she lies as she fell: a moment for her to sag into the floor)
    if st.plan0 then
      if v.t < (cfg().quietWait or 0.4) then return end
    elseif not v.settled and v.t < (cfg().startMax or 2.5) then return end
    local alone = nil
    if st.plan0 then alone = st.plan0.alone == true end
    local plan, why = pick(mesh, alone)
    if not plan then
      st.done = true
      log("none: " .. why)
      return
    end
    begin(mesh, plan)
  end
  if not (v and v.mesh == mesh) then
    st.done = true
    log(string.format("stopped after %.1f s: her ragdoll ended", st.t))
    return
  end
  st.t = st.t + dt
  if st.t >= st.total then
    st.done = true
    local p = loc(mesh, P .. "Pelvis")
    log(string.format("over after %.1f s: %s; rolled %.0f to %.0f deg, %d stump reflexes, %d leg draws, chest up to %.0f deg, moved %.0f cm in all",
      st.t, #st.acts > 0 and table.concat(st.acts, ", ") or "no acts", st.rollMin or 0, st.rollMax or 0, st.reflexes, st.draws,
      st.risen or 0, p and st.start and len(sub(p, st.start)) or -1))
    return
  end
  -- (steered at most `rate` times a second, each step reading her bones once)
  st.acc = st.acc + dt
  if st.acc < 1 / (cfg().rate or 40) then return end
  local sdt = st.acc
  st.acc = 0
  st.seen, st.spun = {}, {}
  st.step = st.step + 1
  step(mesh, sdt)
  st.seen, st.spun = nil, nil
end

-- she got up, or the death ended
function M.stop()
  if st and st.began and not st.done then log(string.format("stopped after %.1f s", st.t)) end
  st = nil
end

-- a new Eve (the level reloaded): drop the old one's without touching it
function M.forget() st = nil end

return M
