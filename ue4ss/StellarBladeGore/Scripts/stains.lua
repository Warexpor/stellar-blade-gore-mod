-- Blood and dirt on Eve (tune.stains): the game's own, cut before its release and switched back on.
-- Her Blueprint (CH_P_EVE_01_Blueprint) still keeps BloodValue and DirtValue (0-1, its AddBlood(Blood, Dirt) adds to
-- them) and writes them into MPC_PCDirtyOffset's BloodOffset and DirtOffset; her skin's master material (MA_Skin, its
-- MF_SkinBloodFX) draws wet blood over the skin through a mask (BloodMask: T_A_NoiseDust_02 tiled BloodTile times),
-- the more of it the higher the offset (or the material's own CustomBloodOffset with UseCustomBloodOffset 1), and dirt
-- by DirtOffset. Nothing in play calls AddBlood any more. The two values are kept here and written (her variables and
-- the collection, which is per world) as they change:
--   blood: a hit that takes HP (base + perHp x the share of her bar lost), enemies hit near her (splash: their mesh's
--     physics hit, less the further off; a cut on one, more), her death (death.blood, perCut for each part off her)
--   dirt: a hard landing (dirt.land, past landSpeed cm/s down), a knockdown (her stance into one of DOWN), lying dead
--     (rising death.rate a second up to death.dirt)
--   washed off swimming (wash.rate a second), gone at a camp rest (rest) and at her next life, faded over fade minutes
--     (0: never)
-- Wounds (wounds): a hit she lives through also paints a wound where it landed. The DLL's skin query (sbslice "m",
-- gore.skin_query) gives the skin under the hit, its material slot and its UV; the slot's material (MA_Skin's) gets
-- a dynamic instance whose BloodMask is a mask drawn here (a canvas into a render target: the game loads no loose
-- image files): the wounds' cores bright, splatter round them, the game's own mask under it all a little dimmer, so
-- the wounds show first and the blood spreads from them as it rises. BloodTile 1 (the mask is in the UV's own space) and
-- CustomBloodOffset at least wounds.floor, so the wounds show at no blood at all.
-- Clothes (cloth): her outfit has no blood layer (its masters' grime layer is behind a static switch most outfits
-- leave off), so blood on it is painted into its colour: each stained slot gets a render target the size of its
-- Basecolor texture, that texture drawn into it and its marks (wounds where hits landed on it, soaked wider, and
-- drops) blended over it toward blood-red (a canvas: blobs multiplied, then added); the render target is the slot's
-- Basecolor then, the texture put back once it's clean. Dirt darkens and greys it
-- (Brightness, Desaturation, Base Color Tint, the outfit masters' own parameters).
-- Drops (spatter): blood lands as drops on the surface (skin or cloth) under random points round her parts, on the
-- side facing where it came from when that is known (an enemy hit near her, a wound's own hit), one skin query a tick
local M = {}
local ctx, try, valid, log
local MPC = "/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"
local KML = "/Script/Engine.Default__KismetMaterialLibrary"
local KRL = "/Script/Engine.Default__KismetRenderingLibrary"
-- her stance names a knockdown is in (the shared Down and Getup, her tumbles; hm.stance_of)
local DOWN = { "Down", "Tumbl" }

-- blood, dirt: 0-1; wounds: slot -> { list (wounds and drops), new (not drawn yet), dirty, full, cloth, rt (its
-- render target), fails }; blobs: what marks are drawn with
-- (on her mesh, one set: a new outfit or her next life starts clean); written: what was last written
local st = { pawn = 0, blood = 0, dirt = 0, wounds = {}, written = { b = -1, d = -1, t = 0 }, next = 0,
  last = os.clock(), pct = nil, dropT = 0, hitT = nil, q = {}, mm = nil, minVz = 0, stance = nil, stances = {},
  others = {}, mats = {}, kinds = {}, dead = false, cuts = 0, deadAt = nil, seat = nil, matNext = 0, blobs = nil,
  outfit = nil, uvTold = false, sq = {}, sAcc = 0 }

function M.init(c)
  ctx = c
  try, valid, log = c.try, c.valid, function(s) c.log("stains: " .. s) end
end

local function cfg() return ctx.tune.stains or {} end
local function on()
  local g = ctx.tune.gore or {}
  return cfg().enabled ~= false and g.enabled ~= false
end
local function clamp(x, a, b) return x < a and a or x > b and b or x end
local function vof(v) return v and { X = v.X, Y = v.Y, Z = v.Z } or nil end
local function dist(a, b) local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z; return math.sqrt(x * x + y * y + z * z) end
local function addr(o) return valid(o) and try(function() return o:GetAddress() end) or 0 end
-- found, never loaded: the libraries are native, and MPC_PCDirtyOffset is in memory with her (her Blueprint holds it;
-- a load on the game thread is what the async loads are there to avoid)
local function obj(path)
  local o = try(function() return StaticFindObject(path) end)
  return valid(o) and o or nil
end

-- any wound on her (an emptied slot's table stays till its material is put back)
local function wounded()
  for _, w in pairs(st.wounds) do if #w.list > 0 then return true end end
  return false
end

function M.add(blood, dirt, why)
  local mx = cfg().max or 1
  local b0, d0 = st.blood, st.dirt
  st.blood = clamp(st.blood + (blood or 0), 0, mx)
  st.dirt = clamp(st.dirt + (dirt or 0), 0, mx)
  if why and (st.blood ~= b0 or st.dirt ~= d0) then
    log(string.format("%s: blood %.2f -> %.2f, dirt %.2f -> %.2f", why, b0, st.blood, d0, st.dirt))
  end
end

-- everything off her (a camp rest, her next life, the menu's Clean Her); her materials go back as the next tick writes
function M.clean_all(why)
  local had = st.blood > 0 or st.dirt > 0 or wounded()
  st.blood, st.dirt, st.sq, st.sAcc, st.coatFail = 0, 0, {}, 0, nil
  for _, w in pairs(st.wounds) do w.list, w.new, w.dirty, w.full, w.fails, w.retry = {}, {}, true, true, 0, nil end
  if had then log("cleaned: " .. tostring(why or "?")) end
end

-- ---- the masks: drawn on the GPU, a canvas into render targets (no files: the game doesn't load loose images) ----
-- a render target, gamma 1 (the canvas writes values as given); clear: its colour to start
local function rt_new(mesh, w, h, fmt, clear)
  local krl = obj(KRL)
  local rt = krl and try(function() return krl:CreateRenderTarget2D(mesh, w, h, fmt, clear, false) end)
  if not valid(rt) then return nil end
  try(function() rt.TargetGamma = 1 end)
  return rt
end

-- fn(canvas) between BeginDrawCanvasToRenderTarget and its End (UE4SS hands the Canvas out-param back in its table).
-- False and why when it can't be
local function draw_on(mesh, rt, fn)
  local krl = obj(KRL)
  if not krl then return false, "no KismetRenderingLibrary" end
  local co, so, cx = {}, {}, {}
  local ok = try(function() krl:BeginDrawCanvasToRenderTarget(mesh, rt, co, so, cx); return true end)
  local canvas = co.Canvas
  if not ok or not valid(canvas) then
    if ok then try(function() krl:EndDrawCanvasToRenderTarget(mesh, cx) end) end
    return false, "no canvas"
  end
  local r, err = pcall(fn, canvas)
  try(function() krl:EndDrawCanvasToRenderTarget(mesh, cx) end)
  if not r then return false, "drawing: " .. tostring(err) end
  return true
end

-- the blobs a mark is drawn with, made once: concentric rings of a white texture tinted, each ring three squares
-- turned 0, 30 and 60 degrees (a 12-sided ring), opaque, soft at the edge (profile). (K2_DrawTexture only: the first
-- blobs were K2_DrawPolygon rings, and nothing painted with them ever showed in game.) One white on black, the amount p (her skin's mask: added over it,
-- BLEND_Additive, the tint its strength), and one for each of cloth.levels' strengths s, white outside and 1 - s x p
-- in the middle. Her outfit's colour goes toward the blood's by s x p: multiplied by the second (BLEND_Modulate),
-- then the first added tinted the blood's colour times s (most outfits are near black: blood only multiplied in
-- didn't show on them). Both write RGB only, so the colour texture's alpha is kept. A render target the canvas only draws from has nothing
-- referencing it, so each is also set on the instances drawn with it as a parameter no material reads ("SBGore_*"):
-- that keeps it from the garbage collector
local BLOB, RINGS = 64, 16
local function profile(t) return clamp((1 - t * t) * 2.5, 0, 1) end
local function blob(mesh, white, clear, col)
  local rt = rt_new(mesh, BLOB, BLOB, 2, clear)
  if not rt then return nil end
  local ok = draw_on(mesh, rt, function(cv)
    for k = 0, RINGS - 1 do
      local t = 1 - k / RINGS
      -- (a square of side 2r / 1.1 turned three ways: inside radius r about, its corners a little past)
      local side = t * BLOB / 1.1
      local pos, size = { X = (BLOB - side) / 2, Y = (BLOB - side) / 2 }, { X = side, Y = side }
      local c = col(profile(t - 0.5 / RINGS))
      for _, a in ipairs({ 0, 30, 60 }) do
        cv:K2_DrawTexture(white, pos, size, { X = 0, Y = 0 }, { X = 1, Y = 1 }, c, 0, a, { X = 0.5, Y = 0.5 })
      end
    end
  end)
  return ok and rt or nil
end

-- a render target's pixel read back (a GPU flush: only once, to check the drawing worked), as "r g b a" 0-255
local function px_at(mesh, rt, x, y)
  local krl = obj(KRL)
  local c = krl and try(function() return krl:ReadRenderTargetPixel(mesh, rt, math.floor(x), math.floor(y)) end)
  if type(c) ~= "table" and type(c) ~= "userdata" then return "?" end
  return string.format("%s %s %s %s", tostring(try(function() return c.R end)), tostring(try(function() return c.G end)),
    tostring(try(function() return c.B end)), tostring(try(function() return c.A end)))
end
local function levels() return (cfg().cloth or {}).levels or { 0.15, 0.3, 0.45, 0.6, 0.8, 1 } end
local function blobs(mesh)
  local key = table.concat(levels(), ",")
  local b = st.blobs
  if b and b.key == key then
    local ok = true
    for _, t in pairs(b.all) do if not valid(t) then ok = false end end
    if ok then return b end
  end
  st.blobs = nil
  local white = rt_new(mesh, 4, 4, 2, { R = 1, G = 1, B = 1, A = 1 })
  if not white then return nil, "no render target" end
  b = { key = key, cloth = {}, all = { White = white }, white = white }
  b.amt = blob(mesh, white, { R = 0, G = 0, B = 0, A = 1 }, function(p) return { R = p, G = p, B = p, A = 1 } end)
  if not b.amt then return nil, "no blob (canvas)" end
  b.all.Amount = b.amt
  for i, s in ipairs(levels()) do
    b.cloth[i] = blob(mesh, white, { R = 1, G = 1, B = 1, A = 1 }, function(p)
      local k = 1 - s * p
      return { R = k, G = k, B = k, A = 1 }
    end)
    if not b.cloth[i] then return nil, "no blob (canvas)" end
    b.all["Cloth" .. i] = b.cloth[i]
  end
  st.blobs = b
  log(string.format("blobs made (%d); check: the amount blob's middle %s, its edge %s (want 255 255 255 255, then 0 0 0 255); the strongest cloth blob's middle %s (want 0 0 0 255)",
    1 + #b.cloth, px_at(mesh, b.amt, BLOB / 2, BLOB / 2), px_at(mesh, b.amt, 1, 1), px_at(mesh, b.cloth[#b.cloth], BLOB / 2, BLOB / 2)))
  return b
end

-- one mark's draws, fn(u, v, rx, ry, ang, strength) in UV: an oval core along its angle and drops of splatter round
-- it (its own seeded positions, so a redraw puts them where they were); res: the target's size (a drop is
-- spatter.minPx px across at least: smaller ones came out as single pixels, playtest)
local function mark_draws(x, res, fn)
  local r = x.r
  local minR = ((cfg().spatter or {}).minPx or 2.5) / res
  fn(x.u, x.v, r * x.len, r, x.ang, x.a)
  local rnd = x.seed
  local function rand() rnd = (rnd * 1103515245 + 12345) % 2147483648; return rnd / 2147483648 end
  for _ = 1, x.drops do
    local d = (1.2 + rand() * 1.8) * r * x.len
    local an = x.ang + (rand() - 0.5) * 1.6 + (rand() < 0.5 and math.pi or 0)
    local rr = math.max(minR, r * (0.12 + rand() * 0.3))
    fn(x.u + math.cos(an) * d, x.v + math.sin(an) * d, rr, rr, 0, x.a * x.wet * (0.6 + rand() * 0.4))
  end
end

-- a blob drawn at (u, v) on a w x h canvas, rx x ry (UV) along ang, again across the UV's edges (it wraps)
local ZERO, ONE, MID = { X = 0, Y = 0 }, { X = 1, Y = 1 }, { X = 0.5, Y = 0.5 }
local function blit(cv, tex, w, h, u, v, rx, ry, ang, tint, blend)
  u, v = u % 1, v % 1
  local e = math.max(rx, ry)
  local us, vs = { 0 }, { 0 }
  if u - e < 0 then us[#us + 1] = 1 elseif u + e > 1 then us[#us + 1] = -1 end
  if v - e < 0 then vs[#vs + 1] = 1 elseif v + e > 1 then vs[#vs + 1] = -1 end
  local size = { X = 2 * rx * w, Y = 2 * ry * h }
  for _, ou in ipairs(us) do
    for _, ov in ipairs(vs) do
      cv:K2_DrawTexture(tex, { X = (u + ou - rx) * w, Y = (v + ov - ry) * h }, size, ZERO, ONE, tint, blend,
        math.deg(ang), MID)
    end
  end
end

-- ---- the coat: blood over all of her outfit as hers rises, the way the game's own layer covers her skin suit ----
-- (only wounds and drops on it looked like a few pixelated droplets next to the skin suit, playtest.) The game's own
-- noise (her skin's BloodMask, T_A_NoiseDust_02: its red channel the blotches) thresholded at her blood's level on the
-- GPU, a canvas only having blends that add and multiply: F (RGBA16f, nothing clamped) cleared to -k x t and the
-- noise's red added times k: k (r - t); G (R8) F drawn in, clamped 0-1 on the way: the coverage p (a one-channel
-- texture is drawn as grey); H (RGBA16f) cleared white and G added times -s: 1 - s p. A cloth slot's colour is
-- multiplied by H and G added tinted the blood's colour times s (as a mark's lerp), both tiled coat.tile times over its
-- UV. t and k: the noise's own levels (coat.from at no blood to coat.to at full), carried over to linear for an sRGB
-- texture. Made again when the blood moves a coat.step; kept from the GC on the instances as the blobs are
local NOISE = "/Game/Art/FX/Tex/Pattern/Noise/T_A_NoiseDust_02.T_A_NoiseDust_02"
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function coat_cfg() return (cfg().cloth or {}).coat or {} end
local function coat_level()
  local c = coat_cfg()
  if c.enabled == false or (cfg().cloth or {}).enabled == false then return 0 end
  local step = c.step or 0.08
  return math.floor(st.blood / step + 0.5) * step
end
-- the noise: a skin slot's own BloodMask (what the game draws her skin's blood with), else found by its path
local function noise_tex()
  for _, o in pairs(st.mats) do if type(o) == "table" and valid(o.mask) then return o.mask end end
  return obj(NOISE)
end
local function coat(mesh)
  local lv = coat_level()
  if lv <= 0 or st.coatFail then return nil end
  local c = st.coat
  local live = c and valid(c.F) and valid(c.G) and valid(c.H)
  if live and c.lv == lv then return c end
  local function fail(why)
    st.coatFail = true
    log("blood over her outfit not shown: " .. why .. " (till she's clean)")
    return nil
  end
  local cc = coat_cfg()
  local res = math.floor(cc.res or 512)
  if not live then
    local noise = noise_tex()
    if not noise then
      -- (not loaded yet, or not found: looked for again next time, told once)
      if not st.noiseTold then st.noiseTold = true; log("blood over her outfit waits: no noise texture yet (" .. NOISE .. ")") end
      return nil
    end
    c = { noise = noise, res = res, srgb = try(function() return noise.SRGB end) ~= false }
    c.F = rt_new(mesh, res, res, 6, { R = 0, G = 0, B = 0, A = 1 })
    c.G = rt_new(mesh, res, res, 0, { R = 0, G = 0, B = 0, A = 1 })
    c.H = rt_new(mesh, res, res, 6, WHITE)
    if not (c.F and c.G and c.H) then return fail("no render target") end
    c.all = { CoatF = c.F, CoatG = c.G, CoatH = c.H }
    st.coat = c
  end
  local from, to = cc.from or 1.05, cc.to or 0.2
  local ts = from - (from - to) * clamp(lv, 0, 1)
  local t, k = ts, cc.soft or 5
  if c.srgb and ts > 0 then t, k = ts ^ 2.2, k / (2.2 * ts ^ 1.2) end
  local s = clamp(cc.strength or 0.85, 0, 1)
  local krl = obj(KRL)
  local size = { X = c.res, Y = c.res }
  if not (krl and try(function() krl:ClearRenderTarget2D(mesh, c.F, { R = -k * t, G = -k * t, B = -k * t, A = 1 }); return true end)) then
    return fail("no clear")
  end
  local ok, why = draw_on(mesh, c.F, function(cv)
    cv:K2_DrawTexture(c.noise, ZERO, size, ZERO, ONE, { R = k, G = 0, B = 0, A = 1 }, 3, 0, MID)
  end)
  if ok then ok, why = draw_on(mesh, c.G, function(cv) cv:K2_DrawTexture(c.F, ZERO, size, ZERO, ONE, WHITE, 0, 0, MID) end) end
  if ok then
    try(function() krl:ClearRenderTarget2D(mesh, c.H, WHITE) end)
    ok, why = draw_on(mesh, c.H, function(cv)
      cv:K2_DrawTexture(c.G, ZERO, size, ZERO, ONE, { R = -s, G = -s, B = -s, A = 1 }, 3, 0, MID)
    end)
  end
  if not ok then return fail(tostring(why)) end
  c.lv, c.s = lv, s
  if not c.checked then
    -- (once: how much of G is covered over a row of its pixels, and H where it is; a covered spot's place for the
    -- slots' own check)
    c.checked = true
    local got, spot = {}, nil
    for j = 0, 7 do
      local x, y = (j + 0.5) * c.res / 8, (j * 3 % 8 + 0.5) * c.res / 8
      local g = px_at(mesh, c.G, x, y)
      got[#got + 1] = g:match("^(%S+)") or "?"
      if not spot and (tonumber(got[#got]) or 0) > 128 then spot = { x = x, y = y } end
    end
    c.spot = spot
    log(string.format("blood over her outfit at %.2f (noise %s, sRGB %s, the level %.3f, k %.2f): coverage at 8 points %s (0-255); H %s where covered (want %d)",
      lv, try(function() return c.noise:GetFName():ToString() end) or "?", tostring(c.srgb), t, k, table.concat(got, " "),
      spot and px_at(mesh, c.H, spot.x, spot.y) or "(none covered)", math.floor((1 - s) * 255 + 0.5)))
  end
  return c
end

-- a slot's marks drawn into its render target: all of them over what's under them (its own mask or colour) when
-- full, else only the new ones over what is there. bg(cv): the background; skin: her skin's amount, else a colour
-- (bc, the blood's) painted in
local function draw_marks(mesh, w, b, skin, full, bg, bc)
  local list = full and w.list or (w.new or {})
  local W, H = w.rw, w.rh
  local lv = levels()
  return draw_on(mesh, w.rt, function(cv)
    if full then bg(cv) end
    for _, x in ipairs(list) do
      mark_draws(x, math.min(W, H), function(u, v, rx, ry, ang, s)
        if s <= 0.005 then return end
        if skin then
          blit(cv, b.amt, W, H, u, v, rx, ry, ang, { R = s, G = s, B = s, A = 1 }, 3)
        else
          local bi, bd = 1, math.huge
          for i, l in ipairs(lv) do if math.abs(l - s) < bd then bi, bd = i, math.abs(l - s) end end
          local l = lv[bi]
          blit(cv, b.cloth[bi], W, H, u, v, rx, ry, ang, { R = 1, G = 1, B = 1, A = 1 }, 4)
          blit(cv, b.amt, W, H, u, v, rx, ry, ang, { R = bc[1] * l, G = bc[2] * l, B = bc[3] * l, A = 1 }, 3)
        end
      end)
    end
  end)
end

-- ---- her materials ----
-- slot i of her mesh: "paint" (a master in paintMasters: skin whose blood layer doesn't show on her body, painted
-- into its colour as cloth is, the marks shaped as on skin), "skin" (a master in skinMasters: MA_Skin's blood layer),
-- "cloth" or "other" (none of hers: translucent, hair). Kept by the material's address
local function kind_of(m)
  local a = addr(m)
  local k = st.kinds[a]
  if k then return k end
  local base = try(function() return m:GetBaseMaterial() end)
  local nm = valid(base) and try(function() return base:GetFName():ToString() end) or "?"
  local blend = valid(base) and try(function() return base.BlendMode end)
  k = "cloth"
  for _, s in ipairs(cfg().skinMasters or { "MA_Skin", "MA_CH_P_EVE_34_BB" }) do if nm == s then k = "skin" end end
  for _, s in ipairs(cfg().paintMasters or { "MA_Skin_EVE", "MA_Skin_EVE_Ver02", "MA_HumanSkin_Ver01" }) do if nm == s then k = "paint" end end
  if k == "cloth" and blend and blend ~= 0 and blend ~= 1 then k = "other" end
  local mn = try(function() return m:GetFName():ToString() end) or "?"
  if k == "cloth" and (mn:lower():find("hair") or mn:lower():find("eye")) then k = "other" end
  st.kinds[a] = k
  log(string.format("material %s (master %s, blend %s): %s", mn, nm, tostring(blend), k))
  return k
end

-- a dynamic instance on slot i (the one there if it is one already, else one made from the slot's material), and
-- its parameters as they were before this module touched them (kept by the slot and the instance's address). Never a
-- nil source material: UE4SS 3.1 crashes converting it (an access violation in UE4SS.dll, the game gone)
-- (the colour texture's parameter: the outfit masters' Basecolor, else the usual other names)
local BASE_NAMES = { "Basecolor", "BaseColor", "Base Color", "BaseColorTex", "Basecolor_Texture", "Albedo", "Diffuse" }
local function mid_of(mesh, i)
  local m = try(function() return mesh:GetMaterial(i) end)
  if not valid(m) then return nil end
  local isMid = (try(function() return m:GetClass():GetFName():ToString() end) or ""):find("MaterialInstanceDynamic")
  local mid = isMid and m or try(function() return mesh:CreateDynamicMaterialInstance(i, m, FName("None")) end)
  if not valid(mid) then return nil end
  local key = string.format("%x:%d:%x", addr(mesh), i, addr(mid))
  local o = st.mats[key]
  if not o then
    o = { key = key }
    o.bri = try(function() return mid:K2_GetScalarParameterValue(FName("Brightness")) end)
    o.des = try(function() return mid:K2_GetScalarParameterValue(FName("Desaturation")) end)
    o.tint = try(function() local t = mid:K2_GetVectorParameterValue(FName("Base Color Tint")); return { R = t.R, G = t.G, B = t.B, A = t.A } end)
    o.mask = try(function() return mid:K2_GetTextureParameterValue(FName("BloodMask")) end)
    o.tile = try(function() return mid:K2_GetScalarParameterValue(FName("BloodTile")) end)
    for _, n in ipairs(BASE_NAMES) do
      local t = try(function() return mid:K2_GetTextureParameterValue(FName(n)) end)
      if valid(t) then o.base, o.baseName = t, n; break end
    end
    st.mats[key] = o
  end
  return mid, o
end

-- dirt on her outfit: darker, greyer, a little brown (the masters' own Brightness, Desaturation, Base Color Tint)
local function apply_cloth(mid, o, dirt)
  local c = cfg().cloth or {}
  local dk = clamp((c.darken or 0.45) * dirt, 0, 0.9)
  if o.bri and o.bri ~= 0 then try(function() mid:SetScalarParameterValue(FName("Brightness"), o.bri * (1 - dk)) end) end
  if o.des then try(function() mid:SetScalarParameterValue(FName("Desaturation"), clamp(o.des + (c.desaturate or 0.35) * dirt, 0, 1)) end) end
  if o.tint then
    local bt, k = c.dirtTint or { 0.62, 0.52, 0.4 }, clamp(dirt * (c.tint or 0.5), 0, 1)
    try(function() mid:SetVectorParameterValue(FName("Base Color Tint"), { R = o.tint.R + (bt[1] - o.tint.R) * k,
      G = o.tint.G + (bt[2] - o.tint.G) * k, B = o.tint.B + (bt[3] - o.tint.B) * k, A = o.tint.A or 1 }) end)
  end
end

-- a slot's marks painted, its render target made the first time. Skin: its mask, the slot's own BloodMask under the
-- marks (tiled as it was, times wounds.background), the render target (wounds.res, linear) its BloodMask with
-- BloodTile 1. Cloth: its colour, the slot's Basecolor texture under them, the render target (the texture's size up
-- to cloth.res, sRGB) its Basecolor. False and why when it can't be
local function paint(mesh, mid, o, w, i, skin, bc, cz)
  local wc, cc = cfg().wounds or {}, cfg().cloth or {}
  if not skin and not valid(o.base) then return false, "no colour texture (" .. table.concat(BASE_NAMES, ", ") .. ")", true end
  local b, why = blobs(mesh)
  if not b then return false, why end
  local full = w.full
  if not valid(w.rt) then
    if skin then
      local res = math.floor(wc.res or 512)
      w.rw, w.rh = res, res
      w.rt = rt_new(mesh, res, res, 2, { R = 0, G = 0, B = 0, A = 1 })
      if not w.rt then return false, "no render target" end
      log(string.format("slot %d (BloodMask): a %d x %d render target", i, res, res))
    else
      local cap = math.floor(cc.res or 2048)
      local sx = try(function() return o.base:Blueprint_GetSizeX() end) or cap
      local sy = try(function() return o.base:Blueprint_GetSizeY() end) or cap
      local k = math.min(1, cap / math.max(sx, sy, 1))
      w.rw, w.rh = math.max(64, math.floor(sx * k)), math.max(64, math.floor(sy * k))
      w.rt = rt_new(mesh, w.rw, w.rh, cc.format or 3, { R = 1, G = 1, B = 1, A = 1 })
      if not w.rt then return false, "no render target" end
      -- (her textures' full mips in, so the copy isn't of a blurry one; drawn again a few s on in case)
      try(function() mesh:PrestreamTextures(10, true, 0) end)
      w.again = os.clock() + 3
      log(string.format("slot %d (%s): a %d x %d render target for its %s (%d x %d)", i, o.baseName, w.rw, w.rh,
        try(function() return o.base:GetFName():ToString() end) or "?", sx, sy))
    end
    full = true
  end
  local size = { X = w.rw, Y = w.rh }
  local ok, err = draw_marks(mesh, w, b, skin, full, function(cv)
    if not skin then
      cv:K2_DrawTexture(o.base, ZERO, size, ZERO, ONE, WHITE, 0, 0, MID)
      if cz then
        local tl = coat_cfg().tile or 4
        local uv = { X = tl, Y = tl }
        cv:K2_DrawTexture(cz.H, ZERO, size, ZERO, uv, WHITE, 4, 0, MID)
        cv:K2_DrawTexture(cz.G, ZERO, size, ZERO, uv, { R = bc[1] * cz.s, G = bc[2] * cz.s, B = bc[3] * cz.s, A = 1 }, 3, 0, MID)
      end
      return
    end
    local bg = wc.background or 0.8
    if valid(o.mask) then
      local t = (o.tile and o.tile > 0) and o.tile or 1
      cv:K2_DrawTexture(o.mask, ZERO, size, ZERO, { X = t, Y = t }, { R = bg, G = bg, B = bg, A = 1 }, 0, 0, MID)
    else
      cv:K2_DrawTexture(b.white, ZERO, size, ZERO, ONE, { R = bg * 0.5, G = bg * 0.5, B = bg * 0.5, A = 1 }, 0, 0, MID)
    end
  end, bc)
  if not ok then return false, err end
  w.full, w.new = false, {}
  if skin then
    try(function() mid:SetTextureParameterValue(FName("BloodMask"), w.rt) end)
    try(function() mid:SetScalarParameterValue(FName("BloodTile"), 1) end)
    try(function() mid:SetScalarParameterValue(FName("UseCustomBloodOffset"), 1) end)
  else
    try(function() mid:SetTextureParameterValue(FName(o.baseName), w.rt) end)
  end
  if not w.checked and (w.list[1] or (cz and cz.spot)) then
    -- (once a slot: its first mark's middle, or a spot the coat covers, against a corner, and whether the material
    -- took the render target)
    w.checked = true
    local x = w.list[1]
    local px, py, what
    if x then
      px, py, what = (x.u % 1) * w.rw, (x.v % 1) * w.rh, "its first mark"
    else
      local tl = coat_cfg().tile or 4
      px, py, what = cz.spot.x / cz.res / tl * w.rw, cz.spot.y / cz.res / tl * w.rh, "a spot the blood over it covers"
    end
    local pn = skin and "BloodMask" or o.baseName
    local got = try(function() return mid:K2_GetTextureParameterValue(FName(pn)) end)
    local cur = try(function() return mesh:GetMaterial(i) end)
    log(string.format("check slot %d: at %s %s, a corner %s; its %s ours %s, the slot's material our instance %s",
      i, what, px_at(mesh, w.rt, px, py), px_at(mesh, w.rt, 2, 2), pn,
      tostring(addr(got) == addr(w.rt)), tostring(addr(cur) == addr(mid))))
  end
  if o.rooted ~= b then
    o.rooted = b
    for k, t in pairs(b.all) do try(function() mid:SetTextureParameterValue(FName("SBGore_" .. k), t) end) end
  end
  if cz and o.rootedCoat ~= cz then
    o.rootedCoat = cz
    for k, t in pairs(cz.all) do try(function() mid:SetTextureParameterValue(FName("SBGore_" .. k), t) end) end
  end
  return true
end

-- painted when its marks changed (or its instance did), the blood over it moved, w.again's redraw is due, or a failed
-- one's retry (5 s on, 3 tries at most till she's clean: a failure every tick was a stutter). One slot drawn whole an
-- update (st.fullLeft), the rest 0.1 s on: the blood rising redraws all of her outfit)
local function repaint(mesh, mid, o, w, i, skin, now, kind, cz)
  if (w.fails or 0) >= 3 or (w.retry and now < w.retry) then return end
  local again = w.again and now >= w.again
  local lv = cz and cz.lv or 0
  local recoat = (w.coat or 0) ~= lv
  if not (w.dirty or w.mid ~= o.key or again or w.retry or recoat) then return end
  if w.full or w.mid ~= o.key or again or recoat then
    if (st.fullLeft or 1) <= 0 then
      st.matNext = math.min(st.matNext, now + 0.1)
      return
    end
    st.fullLeft = (st.fullLeft or 1) - 1
    w.full = true
  end
  if again then w.again = nil end
  w.retry, w.dirty = nil, false
  local t0 = os.clock()
  local bc = kind == "paint" and (cfg().wounds or {}).color or (cfg().cloth or {}).bloodColor
  local ok, why, final = paint(mesh, mid, o, w, i, skin, bc or { 0.2, 0.012, 0.01 }, cz)
  local what = kind == "cloth" and "blood" or "wounds"
  local where = kind == "cloth" and "her outfit" or kind == "paint" and "her skin, painted" or "her skin"
  if ok then
    w.fails, w.coat = 0, lv
    if not w.shown then log(string.format("%s on slot %d (%s): ours (%d marks, blood over it %.2f)", what, i, where, #w.list, lv)) end
    w.shown, w.mid = true, o.key
    if ctx.tune.verboseLog then log(string.format("slot %d painted: %.1f ms", i, (os.clock() - t0) * 1000)) end
  else
    -- (no colour texture: given up at once, trying again changes nothing)
    w.full, w.fails = true, final and 3 or (w.fails or 0) + 1
    if w.fails < 3 then w.retry = now + 5 end
    log(string.format("%s on slot %d not shown: %s (%s)", what, i, tostring(why),
      w.fails < 3 and "again in 5 s" or "given up till she's clean"))
  end
end

-- the slots: wounds on skin, stains on cloth, both put back as they go. Every matEvery s, or at once on a change
local function apply_mats(mesh, force)
  local now = os.clock()
  if not force and now < st.matNext then return end
  st.matNext = now + (cfg().matEvery or 0.5)
  local wc, cc = cfg().wounds or {}, cfg().cloth or {}
  local n = try(function() return mesh:GetNumMaterials() end) or 0
  local cz = on() and coat(mesh) or nil
  st.fullLeft = 1
  for i = 0, n - 1 do
    local m = try(function() return mesh:GetMaterial(i) end)
    if valid(m) then
      local k = kind_of(m)
      local w = st.wounds[i]
      if k == "skin" and w and (#w.list > 0 or w.shown) then
        local mid, o = mid_of(mesh, i)
        if mid and #w.list > 0 and wc.enabled ~= false then
          repaint(mesh, mid, o, w, i, true, now, k, nil)
          if w.shown then
            local off = clamp(math.max(st.blood, (wc.floor or 0.35)), 0, 1)
            try(function() mid:SetScalarParameterValue(FName("CustomBloodOffset"), off) end)
          end
        elseif mid and w.shown then
          -- no wounds left (or wounds off): the game's own mask and the collection's offset again
          if o.mask then try(function() mid:SetTextureParameterValue(FName("BloodMask"), o.mask) end) end
          if o.tile then try(function() mid:SetScalarParameterValue(FName("BloodTile"), o.tile) end) end
          try(function() mid:SetScalarParameterValue(FName("UseCustomBloodOffset"), 0) end)
          w.shown, w.mid, w.dirty, w.rt = false, nil, false, nil
          log(string.format("wounds on slot %d gone: the game's own mask back", i))
        end
      elseif k == "cloth" or k == "paint" then
        -- (paint: her skin, its blood painted in as on cloth; no dirt there, the game's own layer has it)
        local key = string.format("%x:%d", addr(mesh), i)
        local on2 = k == "cloth" and cc.enabled ~= false or k == "paint" and wc.enabled ~= false
        local want = k == "cloth" and on2 and st.dirt > 0.005
        local was = st.mats["c" .. key]
        -- (stained: marks on it, or blood over all of it)
        local stained = on2 and ((w and #w.list > 0) or cz ~= nil)
        if want or was or stained or (w and w.shown) then
          local mid, o = mid_of(mesh, i)
          if mid then
            if want or was then
              apply_cloth(mid, o, want and st.dirt or 0)
              st.mats["c" .. key] = want or nil
            end
            if stained then
              if not w then
                w = { list = {}, new = {}, full = true }
                st.wounds[i] = w
              end
              repaint(mesh, mid, o, w, i, false, now, k, cz)
            elseif w and w.shown then
              if o.base then try(function() mid:SetTextureParameterValue(FName(o.baseName), o.base) end) end
              w.shown, w.mid, w.dirty, w.rt = false, nil, false, nil
              log(string.format("%s on slot %d (%s) gone: its own colour back", k == "paint" and "wounds" or "blood", i,
                k == "paint" and "her skin, painted" or "her outfit"))
            end
          end
        end
      end
    end
  end
end

-- the global values: her Blueprint's variables (its tick works from them) and the collection
local function write(pawn, mesh)
  local w = st.written
  local now = os.clock()
  if math.abs(st.blood - w.b) < 0.002 and math.abs(st.dirt - w.d) < 0.002 and now - w.t < 0.5 then return end
  try(function() pawn.BloodValue = st.blood end)
  try(function() pawn.DirtValue = st.dirt end)
  local kml, mpc = obj(KML), obj(MPC)
  if kml and mpc then
    try(function() kml:SetScalarParameterValue(mesh, mpc, FName("BloodOffset"), st.blood) end)
    try(function() kml:SetScalarParameterValue(mesh, mpc, FName("DirtOffset"), st.dirt) end)
  elseif not st.mpcTold then
    st.mpcTold = true
    log("MPC_PCDirtyOffset not found: only her Blueprint's variables are written")
  end
  local moved = math.abs(st.blood - w.b) >= 0.05 or math.abs(st.dirt - w.d) >= 0.05
  w.b, w.d, w.t = st.blood, st.dirt, now
  if moved and ctx.tune.verboseLog then log(string.format("written: blood %.2f dirt %.2f", st.blood, st.dirt)) end
end

-- ---- what puts it on ----
-- a mark on slot k's mask (a wound or a drop); cloth slots keep their own, wider and softer
local function mark_on(slot, kind, x)
  local w = st.wounds[slot] or { list = {} }
  st.wounds[slot] = w
  if kind == "cloth" and not w.cloth then w.cloth, w.full = true, true end
  table.insert(w.list, x)
  w.new = w.new or {}
  w.new[#w.new + 1] = x
  local mx = (cfg().wounds or {}).max or 24
  if kind == "cloth" or x.drop then mx = mx + ((cfg().spatter or {}).max or 60) end
  -- (the oldest out: its blood stays drawn till the next full redraw)
  while #w.list > mx do table.remove(w.list, 1) end
  w.dirty = true
  -- (a wound at once; drops wait for the next update, every matEvery s, and go in together)
  if not x.drop then st.matNext = 0 end
  return w
end

-- a wound at a hit on her: the skin under it (the DLL), its slot and UV. On her outfit the blood soaks into the cloth
-- round it instead (cloth.soak times wider, no cut)
function M.wound(pawn, mesh, at, push, drop, why)
  local c = cfg().wounds or {}
  local g = ctx.gore
  if not (g and g.skin_query) then return false end
  local q, err = g.skin_query(mesh, at, push, 40)
  if not q then log("wound skipped (" .. why .. "): " .. tostring(err)); return false end
  if not (q.mat and q.u and q.v) then
    log(string.format("wound skipped (%s): no UV on her mesh's CPU copy (slot %s)", why, tostring(q.mat)))
    return false
  end
  local m = try(function() return mesh:GetMaterial(q.mat) end)
  local k = valid(m) and kind_of(m) or "?"
  if k ~= "skin" and k ~= "cloth" and k ~= "paint" then
    log(string.format("wound skipped (%s): slot %d is %s", why, q.mat, k))
    return false
  end
  local cc = cfg().cloth or {}
  if k == "cloth" and cc.enabled == false then return false end
  local size = (c.size or 6) * (0.8 + clamp(drop or 0.05, 0, 0.5) * 2) * (0.8 + math.random() * 0.4)
  if k == "cloth" then size = size * (cc.soak or 1.6) end
  local x = { u = q.u % 1, v = q.v % 1, r = size / (c.uvCm or 150), len = 1.6 + math.random() * 1.6,
    ang = math.random() * math.pi, a = 1, wet = 1, drops = math.floor((c.splatter or 8) * (0.5 + math.random())),
    seed = math.random(1, 2147483646) }
  if k == "cloth" then x.len = 1 + math.random() * 0.6 end
  local w = mark_on(q.mat, k, x)
  log(string.format("%s (%s) on %s: slot %d (%s) at uv %.3f,%.3f, %.1f cm, %d on that slot",
    k == "cloth" and "blood soaked in" or "wound", why, q.part.bone, q.mat, k, x.u, x.v, size, #w.list))
  -- its wet sound (the game's blood cues, over its own hit sound; tune.gore.sounds off: none)
  local sc = cfg().sound or {}
  if sc.enabled ~= false and g.sfx then pcall(g.sfx, "wound", pawn, q.hit or at, false, sc.volume or 0.7, true) end
  -- drops round it, on her near the hit
  M.spatter(((cfg().spatter or {}).hit or 3), at)
  return true
end

-- ---- drops ----
-- n drops queued, from: where the blood came from (world) or nil. Fractions carry over
function M.spatter(n, from)
  local c = cfg().spatter or {}
  if c.enabled == false or not on() then return end
  st.sAcc = st.sAcc + (n or 0)
  while st.sAcc >= 1 and #st.sq < (c.queue or 40) do
    st.sAcc = st.sAcc - 1
    st.sq[#st.sq + 1] = { from = vof(from) }
  end
  if #st.sq >= (c.queue or 40) then st.sAcc = 0 end
end

-- one queued drop: a point off one of her parts (the one nearest where it came from, facing it within ~60 degrees,
-- else any part from any side), the surface under it (the DLL), a drop on that slot's mask
local function drop_one(mesh)
  local d = table.remove(st.sq, 1)
  local g = ctx.gore
  if not (d and g and g.skin_query and g.MARK_AT) then return end
  local function bone(n) return try(function() return vof(mesh:GetSocketLocation(FName(n))) end) end
  local part, a, b
  if d.from then
    local bd
    for _, p in ipairs(g.MARK_AT) do
      local pa, pb = bone(p.bone), bone(p.to)
      if pa and pb then
        local mid = { X = (pa.X + pb.X) / 2, Y = (pa.Y + pb.Y) / 2, Z = (pa.Z + pb.Z) / 2 }
        local dd = dist(mid, d.from) * (0.7 + math.random() * 0.6)
        if not bd or dd < bd then part, a, b, bd = p, pa, pb, dd end
      end
    end
  else
    part = g.MARK_AT[math.random(#g.MARK_AT)]
    a, b = bone(part.bone), bone(part.to)
  end
  if not (part and a and b) then return end
  local t = 0.12 + math.random() * 0.76
  local p = { X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t, Z = a.Z + (b.Z - a.Z) * t }
  local ax = { X = b.X - a.X, Y = b.Y - a.Y, Z = b.Z - a.Z }
  local al = math.max(dist(a, b), 1e-3)
  ax = { X = ax.X / al, Y = ax.Y / al, Z = ax.Z / al }
  -- two directions square to the part's axis
  local ref = math.abs(ax.Z) < 0.9 and { X = 0, Y = 0, Z = 1 } or { X = 1, Y = 0, Z = 0 }
  local function cross(u, v) return { X = u.Y * v.Z - u.Z * v.Y, Y = u.Z * v.X - u.X * v.Z, Z = u.X * v.Y - u.Y * v.X } end
  local function unit(v) local l = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); return l > 1e-4 and { X = v.X / l, Y = v.Y / l, Z = v.Z / l } or nil end
  local e1 = unit(cross(ax, ref))
  local e2 = e1 and cross(ax, e1)
  if not e1 then return end
  local base = math.random() * 2 * math.pi
  if d.from then
    local to = { X = d.from.X - p.X, Y = d.from.Y - p.Y, Z = d.from.Z - p.Z }
    base = math.atan(to.X * e2.X + to.Y * e2.Y + to.Z * e2.Z, to.X * e1.X + to.Y * e1.Y + to.Z * e1.Z) + (math.random() - 0.5) * 2.1
  end
  local out = { X = e1.X * math.cos(base) + e2.X * math.sin(base), Y = e1.Y * math.cos(base) + e2.Y * math.sin(base),
    Z = e1.Z * math.cos(base) + e2.Z * math.sin(base) }
  local reach = (part.r or 5) + 8
  local at = { X = p.X + out.X * reach, Y = p.Y + out.Y * reach, Z = p.Z + out.Z * reach }
  local q = g.skin_query(mesh, at, { X = -out.X, Y = -out.Y, Z = -out.Z }, 40)
  if not (q and q.mat and q.u and q.v) then return end
  local m = try(function() return mesh:GetMaterial(q.mat) end)
  local k = valid(m) and kind_of(m) or "?"
  if k ~= "skin" and k ~= "cloth" and k ~= "paint" then return end
  if k == "cloth" and (cfg().cloth or {}).enabled == false then return end
  local c, wc = cfg().spatter or {}, cfg().wounds or {}
  local size = (c.size or 1.5) * (0.5 + math.random()) * (k == "cloth" and ((cfg().cloth or {}).soak or 1.6) or 1)
  mark_on(q.mat, k, { u = q.u % 1, v = q.v % 1, r = size / (wc.uvCm or 150), len = 1 + math.random() * 1.2,
    ang = math.random() * math.pi, a = 0.55 + math.random() * 0.4, wet = 1, drops = math.random(0, 3),
    seed = math.random(1, 2147483646), drop = true })
  if ctx.tune.verboseLog then log(string.format("drop on %s: slot %d (%s) at uv %.3f,%.3f", part.bone, q.mat, k, q.u % 1, q.v % 1)) end
end

-- blood flying onto her from a hit or a cut near her: at, where (world); kind "hit" or "cut"
function M.splash(at, kind)
  local c = cfg().splash or {}
  if not on() or c.enabled == false or st.dead or not st.her then return end
  local d = dist(at, st.her)
  local range = c.range or 350
  if d > range then return end
  local amt = (kind == "cut" and (c.cut or 0.12) or (c.amount or 0.04)) * (1 - d / range) * (cfg().scale or 1)
  M.add(amt, 0, ctx.tune.verboseLog and string.format("%s %.0f cm off her", kind, d) or nil)
  M.spatter(amt * ((cfg().spatter or {}).perBlood or 40), at)
end

-- hits on her: her HP bar's drops (blood), her mesh's hits a moment later (a wound if the bar dropped with it)
local function hits(pawn, mesh, now)
  local c = cfg()
  local hc = c.hit or {}
  local gl = ctx.glass
  -- (looked for when not found yet: glass.lua spaces its looks out itself, up to a minute apart; nothing else looks
  -- for it with the hit marks parked)
  local pct = gl and gl.bar_pct(false)
  if pct then
    if st.pct and pct < st.pct - 0.002 then
      local drop = st.pct - pct
      -- (one blow's bar may slide down over a few ticks: base once a blow)
      local base = now - st.dropT > 0.4 and (hc.base or 0.04) or 0
      st.dropT = now
      M.add((base + (hc.perHp or 0.9) * drop) * (c.scale or 1), 0,
        string.format("hit, %.0f%% of her HP", drop * 100))
      st.lastDrop = { t = now, drop = drop }
    end
    st.pct = pct
  end
  local mh = ctx.mesh_hit and ctx.mesh_hit()
  if mh and mh.t ~= st.hitT then
    st.hitT = mh.t
    if mh.loc then st.q[#st.q + 1] = { due = now + 0.35, t = mh.t, loc = mh.loc, push = mh.push } end
    if #st.q > 4 then table.remove(st.q, 1) end
  end
  local q = st.q[1]
  if q and now >= q.due then
    table.remove(st.q, 1)
    local ld = st.lastDrop
    local drop = ld and math.abs(ld.t - q.t) < 0.8 and ld.drop or nil
    if (c.wounds or {}).enabled ~= false and now - q.due < 1 and (drop or not pct) then
      M.wound(pawn, mesh, q.loc, q.push, drop, string.format("a hit, %s", drop and string.format("%.0f%% HP", drop * 100) or "HP unknown"))
    end
  end
end

-- hits on the characters near her (their mesh's physics hit, as hers is read): blood flies onto her
local function near_hits(pawn)
  local c = cfg().splash or {}
  if c.enabled == false or not ctx.live_chars then return end
  local me = addr(pawn)
  local range = c.range or 350
  local seen = {}
  for _, e in ipairs(ctx.live_chars()) do
    if e.addr ~= me then
      local p = ctx.char_at(e)
      if p and st.her and dist(p, st.her) < range + 200 then
        local m = try(function() return e.obj.Mesh end)
        local at = valid(m) and try(function() return vof(m.PhysicalHitForceLocation) end)
        local key = at and string.format("%.0f %.0f %.0f", at.X, at.Y, at.Z)
        seen[e.addr] = true
        local was = st.others[e.addr]
        st.others[e.addr] = key or was
        if key and was and key ~= was and dist(at, p) < 250 then M.splash(at, "hit") end
      end
    end
  end
  for a in pairs(st.others) do if not seen[a] then st.others[a] = nil end end
end

local function stance_down(s)
  for _, d in ipairs(DOWN) do if s:find(d, 1, true) then return true end end
  return false
end

-- landings, knockdowns, water
local function moves(pawn, dt)
  local c = cfg()
  local dc = c.dirt or {}
  local cm = try(function() return pawn.CharacterMovement end)
  local mm = valid(cm) and try(function() return cm.MovementMode end)
  local vz = valid(cm) and try(function() return cm.Velocity.Z end) or 0
  if mm == 3 then
    st.minVz = math.min(st.minVz, vz)
  else
    if st.mm == 3 and (mm == 1 or mm == 2) and dc.enabled ~= false then
      local sp, need = -st.minVz, dc.landSpeed or 900
      if sp > need then M.add(0, (dc.land or 0.15) * clamp((sp - need) / need + 0.5, 0.5, 1.5), string.format("landed at %.0f cm/s", sp)) end
    end
    st.minVz = 0
  end
  st.mm = mm
  -- swimming: blood and dirt wash off, the wounds' blood with it (their cuts stay)
  if mm == 4 and (c.wash or {}).enabled ~= false then
    local r = ((c.wash or {}).rate or 0.35) * dt
    if st.blood > 0 or st.dirt > 0 then
      local was = st.blood + st.dirt
      st.blood, st.dirt = math.max(0, st.blood - r), math.max(0, st.dirt - r)
      if was > 0.01 and st.blood + st.dirt <= 0.01 then log("washed off in the water") end
    end
    -- (a wound's cut stays, paler; blood soaked into cloth leaves a faint stain; drops on skin wash off)
    for _, w in pairs(st.wounds) do
      for j = #w.list, 1, -1 do
        local x = w.list[j]
        local floor = w.cloth and 0.15 or x.drop and 0 or 0.5
        local wet = math.max(0, x.wet - r)
        local a = math.max(floor, x.a - r * (x.drop and 1 or 0.5))
        if math.floor(wet * 5) ~= math.floor(x.wet * 5) or math.floor(a * 5) ~= math.floor(x.a * 5) then w.dirty, w.full = true, true end
        x.wet, x.a = wet, a
        if a <= 0.01 then table.remove(w.list, j); w.dirty, w.full = true, true end
      end
    end
  end
  local s = try(function() return pawn:GetCurrentStanceName():ToString() end)
  if s and s ~= st.stance then
    if stance_down(s) and not (st.stance and stance_down(st.stance)) and dc.enabled ~= false then
      M.add(0, dc.knock or 0.12, "knocked down (" .. s .. ")")
    end
    if ctx.tune.verboseLog and not st.stances[s] then st.stances[s] = true; log("stance seen: " .. s) end
    st.stance = s
  end
end

-- a camp rest: sat down out of battle, and the camp's chair or the rest's sequence playing (hm.rest_seq)
local function rest(pawn, now)
  if cfg().rest == false or not ctx.rest_seq then return end
  if st.blood <= 0 and st.dirt <= 0 and not wounded() then st.seat = nil; return end
  local seated = st.mm == 0 and try(function() return pawn:IsBattle() end) ~= true
  if not seated then st.seat = nil; return end
  st.seat = st.seat or { next = now }
  if now < st.seat.next then return end
  st.seat.next = now + 1
  local rested, seen = ctx.rest_seq()
  local chair = false
  for _, n in ipairs(seen or {}) do if n == "Interaction_Camp_Chair" or n == "Interaction_Camp_Chair_End" then chair = true end end
  if rested or chair then
    M.clean_all(rested and "a camp rest" or "sat at a camp")
    st.matNext = 0
  end
end

-- her death: blood at once, more for each part cut off her as they come, dirt as she lies there
local function death(pawn, mesh, now, dt)
  local c = cfg()
  local dc, dd = c.death or {}, c.dirt or {}
  if not st.dead then
    st.dead, st.cuts, st.deadAt = true, 0, now
    st.deadLoc = try(function() return vof(pawn:K2_GetActorLocation()) end)
    M.add((dc.blood or 0.35) * (c.scale or 1), 0, "her death")
    M.spatter((c.spatter or {}).death or 14)
  end
  local g = ctx.gore
  local parts = g and g.cut_parts and try(function() return g.cut_parts(mesh) end)
  if parts and #parts > st.cuts then
    M.add((dc.perCut or 0.15) * (#parts - st.cuts) * (c.scale or 1), 0, string.format("%d part(s) off her", #parts - st.cuts))
    M.spatter(((c.spatter or {}).perCut or 6) * (#parts - st.cuts))
    st.cuts = #parts
  end
  if dd.enabled ~= false and now - st.deadAt > 1.5 and st.dirt < (dd.death or 0.6) then
    st.dirt = math.min(dd.death or 0.6, st.dirt + (dd.rate or 0.08) * dt)
  end
end

-- each tick, alive (main.lua's alive watch) or dead (its death frame); every 0.1 s
function M.tick(pawn, mesh, dead)
  if not valid(pawn) then return end
  local now = os.clock()
  if now < st.next then return end
  st.next = now + 0.1
  local dt = math.min(now - st.last, 0.5)
  st.last = now
  mesh = mesh or try(function() return pawn.Mesh end)
  if not valid(mesh) then return end
  local pa = addr(pawn)
  -- a new Eve: her next life (or a level), clean
  if pa ~= st.pawn then
    if st.pawn ~= 0 then M.clean_all("a new Eve") end
    st.pawn, st.pct, st.q, st.hitT, st.dead, st.kinds, st.mats, st.wounds, st.blobs, st.coat = pa, nil, {}, nil, false, {}, {}, {}, nil, nil
    st.written.t = 0
  end
  -- a new outfit: its slots are other materials
  local sk = addr(try(function() return mesh.SkeletalMesh end))
  if sk ~= st.outfit then
    if st.outfit then log("outfit changed: wounds and stains on the new one start over") end
    st.outfit, st.wounds, st.mats, st.sq, st.blobs = sk, {}, {}, {}, nil
  end
  st.her = try(function() return vof(pawn:K2_GetActorLocation()) end)
  if not on() then
    if st.blood > 0 or st.dirt > 0 or wounded() then M.clean_all("Blood and Dirt turned off") end
    write(pawn, mesh)
    apply_mats(mesh, false)
    return
  end
  if dead then
    death(pawn, mesh, now, dt)
  else
    if st.dead then
      -- up again: where she died (a revive item) she keeps it; somewhere else (a respawn at a camp) it's her next life
      local far = st.deadLoc and st.her and dist(st.deadLoc, st.her) > 1500
      st.dead = false
      if far or not st.deadLoc then M.clean_all("her next life"); st.matNext = 0 end
      st.pct = nil
    end
    hits(pawn, mesh, now)
    near_hits(pawn)
    moves(pawn, dt)
    rest(pawn, now)
  end
  local fade = cfg().fade or 0
  if fade > 0 then
    local r = dt / (fade * 60)
    st.blood, st.dirt = math.max(0, st.blood - r), math.max(0, st.dirt - r)
  end
  if ctx.uv and ctx.uv() and not st.uvTold then
    st.uvTold = true
    log("Ultra Violence is on too: its blood and this one both go on her (turn one off: stains.enabled in settings.lua)")
  end
  -- the queued drops, one skin query each (perTick a tick)
  for _ = 1, math.max(1, math.floor((cfg().spatter or {}).perTick or 1)) do
    if #st.sq == 0 then break end
    drop_one(mesh)
  end
  write(pawn, mesh)
  apply_mats(mesh, false)
end

-- ---- the F3 menu's buttons ----
function M.test_blood(pawn)
  M.add(0.25, 0, "menu: Add Blood")
  M.spatter((cfg().spatter or {}).menu or 12)
  st.matNext = 0
end
function M.test_dirt(pawn) M.add(0, 0.25, "menu: Add Dirt"); st.matNext = 0 end
function M.clean(pawn) M.clean_all("menu: Clean Her"); st.matNext = 0 end
-- a wound on a part at random, on its side facing the camera (as F10's hit mark)
function M.test_wound(pawn)
  local g = ctx.gore
  local mesh = valid(pawn) and try(function() return pawn.Mesh end)
  if not (g and g.MARK_AT and valid(mesh)) then log("menu: Add Wound: no mesh"); return end
  local w = g.MARK_AT[math.random(#g.MARK_AT)]
  local a = try(function() return vof(mesh:GetSocketLocation(FName(w.bone))) end)
  local b = try(function() return vof(mesh:GetSocketLocation(FName(w.to))) end)
  local cam = try(function() return vof(ctx.statics():GetPlayerCameraManager(pawn, 0):GetCameraLocation()) end)
  if not (a and b and cam) then log("menu: Add Wound: no part or camera"); return end
  local t = 0.3 + math.random() * 0.4
  local p = { X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t, Z = a.Z + (b.Z - a.Z) * t }
  local d = dist(cam, p)
  local out = { X = (cam.X - p.X) / d, Y = (cam.Y - p.Y) / d, Z = (cam.Z - p.Z) / d }
  local at = { X = p.X + out.X * 10, Y = p.Y + out.Y * 10, Z = p.Z + out.Z * 10 }
  M.add(0.05, 0, nil)
  M.wound(pawn, mesh, at, { X = -out.X, Y = -out.Y, Z = -out.Z }, 0.1, "menu: Add Wound")
end

-- (test harness)
M._st = st
return M
