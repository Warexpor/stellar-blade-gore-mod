-- Blood and dirt on her (stains.lua): a hit bloodies her (her Blueprint's BloodValue and MPC_PCDirtyOffset's
-- BloodOffset) and leaves a wound in her skin material's own blood mask (a dynamic instance on the slot the DLL's
-- skin query names, its BloodMask a render target the wound is drawn into over the game's own mask, BloodTile 1,
-- CustomBloodOffset on), its wet sound and drops round it,
-- a hit on cloth soaks it there (blood-red blobs multiplied over its Basecolor drawn in a render target that becomes
-- its Basecolor; her blood rising bloodies all of her outfit and bare skin over, the game's noise thresholded in
-- 16f, R8 and 16f render targets), a canvas that fails is tried again 5 s on and not every tick, Add Blood scatters drops, a hard landing dirties her, water washes it off, a camp rest cleans her (her materials back as
-- they were), her death bloodies and dirties her, and her next life starts clean
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
-- (parked: off by default, on here)
local sf = assert(io.open(DIR .. "settings.lua", "w"))
sf:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.stains.enabled = true
return s
]])
sf:close()

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

-- the collection, the libraries
local mpcVals = {}
F.objects["/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"] = F.obj("MPC_PCDirtyOffset", "MaterialParameterCollection")
F.objects["/Script/Engine.Default__KismetMaterialLibrary"] = F.obj("Default__KismetMaterialLibrary", "KismetMaterialLibrary", {
  SetScalarParameterValue = function(_, ctx, mpc, name, v) mpcVals[name:ToString()] = v end,
})
local rts, draws, polys, begins = {}, {}, {}, 0
local canvas = F.obj("Canvas", "Canvas", {
  K2_DrawTexture = function(_, tex, pos, size, cpos, csize, color, blend, rot, pivot)
    draws[#draws + 1] = { rt = draws.open, tex = tex, x = pos.X + size.X / 2, y = pos.Y + size.Y / 2, w = size.X,
      h = size.Y, cw = csize.X, color = color, blend = blend }
  end,
  K2_DrawPolygon = function(_, tex, pos, radius, sides, color)
    assert(tex ~= nil, "a polygon's texture (nil crashes UE4SS)")
    polys[#polys + 1] = { rt = draws.open, r = radius.X, color = color }
  end,
})
local failCanvas, failRt = false, function() end
F.objects["/Script/Engine.Default__KismetRenderingLibrary"] = F.obj("Default__KismetRenderingLibrary", "KismetRenderingLibrary", {
  ImportFileAsTexture2D = function() error("ImportFileAsTexture2D: the game loads no loose files") end,
  ReadRenderTargetPixel = function(_, ctx, rt) if rt and rt.fmt == 0 then return { R = 200, G = 0, B = 0, A = 255 } end return { R = 1, G = 2, B = 3, A = 4 } end,
  ClearRenderTarget2D = function(_, ctx, rt, c) rt.cleared = c end,
  CreateRenderTarget2D = function(_, ctx, w, h, fmt, clear, mips)
    local t = F.obj("TextureRenderTarget2D_" .. #rts, "TextureRenderTarget2D", { w = w, h = h, fmt = fmt, clear = clear })
    rts[#rts + 1] = t
    return t
  end,
  -- (UE4SS: an object out param comes back in its table under its name, a struct's fields in its table)
  BeginDrawCanvasToRenderTarget = function(_, ctx, rt, co, so, cx)
    assert(type(co) == "table" and type(so) == "table" and type(cx) == "table", "out params need tables")
    assert(draws.open == nil, "a canvas inside another")
    if failCanvas then
      if rt == failRt() then begins = begins + 1 end
      return
    end
    co.Canvas, so.X, so.Y, cx.RenderTarget = canvas, rt.w, rt.h, rt
    draws.open = rt
  end,
  EndDrawCanvasToRenderTarget = function(_, ctx, cx)
    assert(cx.RenderTarget == draws.open, "the context's render target")
    draws.open = nil
  end,
})

-- the sounds: the game's blood cues, played where she was hit
local played = {}
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("Default__GameplayStatics", "GameplayStatics", {
  PlaySoundAtLocation = function(_, ctx, snd, at, rot, vol) played[#played + 1] = { snd = snd, vol = vol } end,
})
for _, c in ipairs({ "hit_Linkskill_Blood_01_Cue", "hit_common_blood_power_00_Cue" }) do
  F.objects["/Game/Sound/Character/Hit/" .. c .. "." .. c] = F.obj(c, "SoundCue")
end

-- her materials: slot 0 her skin (MA_Skin's), slot 1 her suit, 2 her hair, 3 more suit
local function base(name, blend) return F.obj(name, "Material", { BlendMode = blend or 0 }) end
-- (MA_Skin_EVE: her body skin's master on most outfits, the same blood layer as MA_Skin)
local skinBase, suitBase, hairBase = base("MA_Skin"), base("MA_CH_EVE_01"), base("MA_Hair", 2)
-- (MA_Skin_EVE: her body skin on most outfits; its blood layer showed nothing on her body in game, so it's painted)
local bodyBase = base("MA_Skin_EVE")
local gameMask = F.obj("T_A_NoiseDust_02", "Texture2D")
F.objects["/Game/Art/FX/Tex/Pattern/Noise/T_A_NoiseDust_02.T_A_NoiseDust_02"] = gameMask
local mats = {}
local function mi(name, b, params)
  return F.obj(name, "MaterialInstanceConstant", { GetBaseMaterial = function() return b end, params = params })
end
mats[0] = mi("MI_Skin", skinBase, { BloodTile = 4, BloodMask = gameMask })
local suitTex = F.obj("T_Suit_D", "Texture2D", { Blueprint_GetSizeX = function() return 4096 end, Blueprint_GetSizeY = function() return 4096 end })
mats[1] = mi("MI_Suit", suitBase, { Brightness = 1.2, Desaturation = 0.1, ["Base Color Tint"] = { R = 1, G = 1, B = 1, A = 1 }, Basecolor = suitTex })
mats[2] = mi("MI_Hair", hairBase, {})
mats[3] = mi("MI_Suit2", suitBase, { Brightness = 1, Desaturation = 0, Basecolor = suitTex })
local bodyTex = F.obj("CH_P_EVE_BaseBody_A", "Texture2D", { Blueprint_GetSizeX = function() return 4096 end, Blueprint_GetSizeY = function() return 4096 end })
mats[4] = mi("MI_CH_P_EVE_BB_V01", bodyBase, { BaseColor = bodyTex, BloodMask = gameMask, BloodTile = 4 })
local mids = {}
local mesh = E.mesh
rawset(mesh, "SkeletalMesh", F.obj("CH_P_EVE_01", "SkeletalMesh"))
rawset(mesh, "GetMaterial", function(_, i) return mats[i] end)
rawset(mesh, "GetNumMaterials", function() return 5 end)
-- (a nil source material is what crashed UE4SS 3.1 in game: refused here)
rawset(mesh, "CreateDynamicMaterialInstance", function(_, i, src)
  if src == nil then error("CreateDynamicMaterialInstance with a nil source material (crashes UE4SS)") end
  local m = mats[i]
  if m.__cls == "MaterialInstanceDynamic" then return m end
  local p = {}
  for k, v in pairs(m.params) do p[k] = v end
  local b = m.GetBaseMaterial()
  local mid = F.obj("MID_" .. i, "MaterialInstanceDynamic", {
    GetBaseMaterial = function() return b end, params = p,
    SetScalarParameterValue = function(_, k, v) p[k:ToString()] = v end,
    SetVectorParameterValue = function(_, k, v) p[k:ToString()] = v end,
    SetTextureParameterValue = function(_, k, v) p[k:ToString()] = v end,
    K2_GetScalarParameterValue = function(_, k) return p[k:ToString()] or 0 end,
    K2_GetVectorParameterValue = function(_, k) return p[k:ToString()] or { R = 0, G = 0, B = 0, A = 0 } end,
    K2_GetTextureParameterValue = function(_, k) return p[k:ToString()] end,
  })
  mats[i], mids[i] = mid, mid
  return mid
end)
rawset(pawn, "GetCurrentStanceName", function() return F.fname(E.s.stance or "Idle") end)
rawset(pawn, "IsBattle", function() return false end)

-- the DLL's skin query: the skin under the hit, its slot and UV (slot answered from E.s.mslot)
F.sbslice.m = function()
  local p = E.bone("Bip001-Spine1")
  return string.format("ok hit=%.1f,%.1f,%.1f n=100.0,0.0,0.0 bone=4 out=9.0 mat=%d uv=0.400,0.300", p.X + 9, p.Y, p.Z,
    E.s.mslot or 0)
end

-- (stains.lua's table kept as main.lua loads it: its state and the menu's buttons)
local stains
local realDofile = dofile
dofile = function(path, ...)
  local r = realDofile(path, ...)
  if tostring(path):find("stains%.lua$") then stains = r end
  return r
end
local function require_st() return stains._st end
local function goreCtx_call(name) stains[name:match("%.(.+)$")](pawn) end
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(8, pawn)
F.sbslice_ready()
F.run(3, pawn)

-- 1: clean to start, the values written
check(mpcVals.BloodOffset == 0 and mpcVals.DirtOffset == 0, "the collection written clean (" .. tostring(mpcVals.BloodOffset) .. ")")
check(pawn.BloodValue == 0, "her Blueprint's BloodValue 0")

-- 2: a hit on her skin taking a fifth of her HP: blood, and a wound on slot 0
local n = 0
local function hit(hp, slot)
  n = n + 1
  E.s.mslot = slot
  local p = E.bone("Bip001-Spine1")
  rawset(mesh, "PhysicalHitForceVector", { X = -100 - n, Y = 0, Z = 0 })
  rawset(mesh, "PhysicalHitForceLocation", { X = p.X + 10, Y = p.Y, Z = p.Z })
  rawset(mesh, "PhysicalHitForceTargetBone", F.fname("Bip001-Spine1"))
  F.run(0.1, pawn)
  E.s.hp = hp
  F.run(1.5, pawn)
end
local at = mark()
hit(0.8, 0)
local b = pawn.BloodValue or 0
check(b > 0.2 and b < 0.26, string.format("a hit for 20%% HP: blood %.3f (0.04 + 0.9 x 0.2)", b))
check(math.abs((mpcVals.BloodOffset or 0) - b) < 0.01, "the collection's BloodOffset follows it")
check(F.find("wound %(a hit, 20%% HP%) on Bip001%-Spine", at) ~= nil, "a wound made on the hit part")
check(F.find("sound wound: hit_", at) ~= nil and #played >= 1 and math.abs(played[1].vol - 0.7) < 1e-6, "its wet sound, at 0.7")
local mid = mids[0]
check(mid ~= nil, "a dynamic instance on her skin's slot")
local skinRt = mid and mid.params.BloodMask
check(skinRt and skinRt.__cls == "TextureRenderTarget2D" and skinRt.w == 512 and skinRt.fmt == 2 and skinRt.TargetGamma == 1,
  "its BloodMask a 512 linear render target, gamma 1")
-- (the blobs: one amount, six cloth strengths, 16 rings each, on a white texture)
local blobDraws = 0
for _, d in ipairs(draws) do if d.rt and d.rt.w == 64 then blobDraws = blobDraws + 1 end end
check(#polys == 0 and blobDraws == 7 * 16 * 3, "the blobs drawn, textures only (" .. blobDraws .. " squares)")
check(F.find("check slot 0: at its first mark 1 2 3 4, a corner 1 2 3 4; its BloodMask ours true, the slot's material our instance true") ~= nil,
  "a slot's first paint checked")
check(mid and mid.params.SBGore_Amount ~= nil and mid.params.SBGore_Cloth1 ~= nil, "the blobs kept by the instance (from the GC)")
local function on(rt) local r = {} for _, d in ipairs(draws) do if d.rt == rt then r[#r + 1] = d end end return r end
local sd = on(skinRt)
check(sd[1] and sd[1].tex == gameMask and sd[1].blend == 0 and sd[1].cw == 4 and math.abs(sd[1].color.R - 0.8) < 1e-6,
  "the game's own mask under it (tiled 4 times, at 0.8)")
local core = sd[2]
check(core and core.blend == 3 and math.abs(core.x - 0.4 * 512) < 1 and math.abs(core.y - 0.3 * 512) < 1 and core.color.R == 1,
  "the wound added at its UV (" .. (core and string.format("%.0f, %.0f", core.x, core.y) or "none") .. ")")
check(mid and mid.params.BloodTile == 1 and mid.params.UseCustomBloodOffset == 1, "BloodTile 1, its own offset on")
check(mid and (mid.params.CustomBloodOffset or 0) >= 0.35 - 1e-6, "the wounded skin's offset at least the floor")
check(F.find("drop on Bip001", at) ~= nil or #(require_st().wounds[0] or { list = {} }).list > 1, "drops round the wound")
-- (her blood risen: her suit bloodied all over, not wounded)
check(mids[1] ~= nil and #((require_st().wounds[1] or {}).list or {}) == 0, "her suit bloodied over, no wound on it from her skin's")
check(mids[2] == nil, "her hair left alone")

-- 3: a second hit, on her suit: the cloth soaks there; its own colour mask over its Basecolor in a render target
at = mark()
hit(0.7, 1)
check(F.find("blood soaked in %(a hit, 10%% HP%) on Bip001%-Spine1: slot 1", at) ~= nil, "a hit on slot 1 soaks her outfit there")
local rt = mids[1] and mids[1].params.Basecolor
check(rt and rt.__cls == "TextureRenderTarget2D" and rt.w == 2048 and rt.h == 2048 and rt.fmt == 3 and rt.TargetGamma == 1,
  "a 2048 sRGB render target (its 4096 texture capped), gamma 1, her suit's Basecolor")
local cd = on(rt)
check(cd[1] and cd[1].tex == suitTex and cd[1].blend == 0 and cd[1].w == 2048, "its Basecolor drawn first")
-- (the blood over all of it: the game's noise thresholded at her blood's level, F 16f -> G R8 -> H 16f)
local cz = require_st().coat
check(cz and cz.F.fmt == 6 and cz.G.fmt == 0 and cz.H.fmt == 6 and cz.F.w == 512, "the blood over her outfit: 16f, R8, 16f, 512")
local fd, gd, hd = on(cz and cz.F), on(cz and cz.G), on(cz and cz.H)
local t = cz and cz.F.cleared and -cz.F.cleared.R
check(fd[1] and fd[1].tex == gameMask and fd[1].blend == 3 and fd[1].color.R > 1 and fd[1].color.G == 0 and t and t > 0,
  "the noise's red added times k over -k x t")
check(gd[1] and gd[1].tex == cz.F and gd[1].blend == 0, "G: F drawn in (clamped)")
check(hd[1] and hd[1].tex == cz.G and hd[1].blend == 3 and math.abs(hd[1].color.R + 0.85) < 1e-6 and cz.H.cleared.R == 1,
  "H: white less G times its strength")
check(cd[2] and cd[2].tex == cz.H and cd[2].blend == 4 and cd[2].cw == 4 and cd[3] and cd[3].tex == cz.G and cd[3].blend == 3
  and math.abs(cd[3].color.R - 0.2 * 0.85) < 1e-6, "the suit multiplied by H and G added blood-red, tiled 4 times")
check(F.find("blood over her outfit at 0%.%d+ %(noise T_A_NoiseDust_02, sRGB true") ~= nil, "the blood over it checked once")
check(mids[1].params.SBGore_CoatG == cz.G, "kept by the instance (from the GC)")
local function after(list, test) for j, d in ipairs(list) do if test(d) then return d, j end end end
local soak, si = after(cd, function(d) return d.blend == 4 and d.tex ~= cz.H end)
check(soak and soak.blend == 4 and math.abs(soak.x - 0.4 * 2048) < 1 and math.abs(soak.y - 0.3 * 2048) < 1,
  "the soak multiplied over it at its UV")
-- (then the blood's colour added in: on her mostly black outfits blood only multiplied in didn't show, playtest)
local add = si and cd[si + 1]
check(add and add.blend == 3 and add.x == soak.x and add.color.R > add.color.G * 5 and add.color.R > 0.1,
  "then blood-red added there (" .. (add and string.format("%.3f %.3f %.3f", add.color.R, add.color.G, add.color.B) or "none") .. ")")
local blobRt = soak and soak.tex
local ring = nil
for _, p in ipairs(draws) do if p.rt == blobRt then ring = ring or p end end
check(ring and ring.color.G > 0.8 or false, "its blob near white at the edge")
-- a black suit with blood on it (lerp: base x (1 - s p) + blood x s p) comes out red
local inner0 = nil
for _, p in ipairs(draws) do if p.rt == blobRt then inner0 = p end end
local k = inner0 and inner0.color.R or 1
check(k < 0.2 and math.abs(inner0.color.G - k) < 1e-6, string.format("the blob dark grey in the middle (%.2f): the cloth's own colour mostly out", k))
check(draws.open == nil, "the canvas ended")
-- 4: a third hit, on her skin again: only the new wound drawn over the mask
local nd = #on(skinRt)
hit(0.6, 0)
local sd2 = on(skinRt)
check(#sd2 > nd and sd2[nd + 1].tex ~= gameMask, "the new wound drawn over what's there (" .. #sd2 - nd .. " draws)")
-- 4b: Add Blood: drops on her skin and outfit, one query a tick
at = mark()
local nl = #(require_st().wounds[1].list)
E.s.mslot = 1
goreCtx_call("stains.test_blood")
F.run(2, pawn)
check(#(require_st().wounds[1].list) >= nl + 10, "Add Blood: a dozen drops on her outfit (" .. #(require_st().wounds[1].list) - nl .. ")")
E.s.mslot = 0
-- 4b2: a hit on her bare body (MA_Skin_EVE): a wound painted into its colour, shaped as on skin, not soaked
at = mark()
hit(0.58, 4)
check(F.find("wound %(a hit, 2%% HP%) on Bip001%-Spine1: slot 4 %(paint%)", at) ~= nil, "a wound on her body's skin, not a soak")
local brt = mids[4] and mids[4].params.BaseColor
check(brt and brt.__cls == "TextureRenderTarget2D" and brt.fmt == 3, "its BaseColor a render target")
check(mids[4] and mids[4].params.BloodMask == gameMask and mids[4].params.UseCustomBloodOffset == nil, "its blood layer left alone")
local bd = on(brt)
local bw, bi = after(bd, function(d) return d.blend == 4 and d.tex ~= cz.H end)
check(bd[1] and bd[1].tex == bodyTex and bd[2] and bd[2].tex == cz.H and bw and bd[bi + 1] and bd[bi + 1].blend == 3
  and bd[bi + 1].color.R > bd[bi + 1].color.G * 5, "her skin drawn, the blood over it, the wound multiplied in and blood-red added")
check(F.find("wounds on slot 4 %(her skin, painted%): ours") ~= nil, "told painted")
check(mids[3] and mids[3].params.Basecolor and mids[3].params.Basecolor.__cls == "TextureRenderTarget2D" and #require_st().wounds[3].list == 0,
  "her other suit slot bloodied all over with no hit on it")
-- 4c: a canvas that fails (slot 3, more suit): logged, tried again 5 s on, never every tick, given up after 3
at = mark()
failCanvas = true
failRt = function() local w = require_st().wounds[3]; return w and w.rt end
local b0 = begins
hit(0.55, 3)
F.run(2, pawn)
local b1 = begins
check(F.find("blood on slot 3 not shown: no canvas %(again in 5 s%)", at) ~= nil, "a failed canvas logged")
check(b1 - b0 <= 1, "slot 3 not tried again every tick (" .. b1 - b0 .. " tries in 3.5 s)")
F.run(12, pawn)
check(F.find("given up till she's clean", at) ~= nil and begins - b0 == 3, "given up after 3 tries (" .. begins - b0 .. ")")
failCanvas = false

-- 5: a hard landing dirties her
at = mark()
local d0 = pawn.DirtValue or 0
E.fall(400, 0.7, 0.6)
F.run(0.5, pawn)
check((pawn.DirtValue or 0) > d0 + 0.1, string.format("a hard landing: dirt %.2f -> %.2f", d0, pawn.DirtValue or 0))

-- 6: swimming washes it off; the wounds stay, paler
at = mark()
E.s.mode = 4
F.run(3, pawn)
E.s.mode = 1
F.run(0.5, pawn)
check((pawn.BloodValue or 1) < 0.01 and (pawn.DirtValue or 1) < 0.01, string.format("washed off (blood %.2f, dirt %.2f)", pawn.BloodValue or -1, pawn.DirtValue or -1))
check(mid.params.BloodMask ~= gameMask, "the wounds still on her mask")
check(math.abs(mids[1].params.Brightness - 1.2) < 1e-6, "her suit's dirt gone")
check(mids[1].params.Basecolor == rt, "a faint stain left on it")

-- 7: a camp rest heals the wounds: the game's own mask and offset back
at = mark()
hit(0.5, 0)
local seq = F.obj("Interaction_Camp_Chair", "LevelSequence", {
  GetFullName = function() return "LevelSequence /Game/Sequence/Interaction_Camp_Chair.Interaction_Camp_Chair" end,
})
local player = F.obj("SequencePlayer", "LevelSequencePlayer", { IsPlaying = function() return true end, GetSequence = function() return seq end })
F.classes.LevelSequenceActor = { F.obj("Interaction_Camp_Chair_Actor", "LevelSequenceActor", { SequencePlayer = player }) }
E.s.mode = 0
F.run(3, pawn)
E.s.mode = 1
F.classes.LevelSequenceActor = {}
F.run(1, pawn)
check(F.find("cleaned: sat at a camp", at) ~= nil, "a camp rest cleans her")
check(mid.params.BloodMask == gameMask and mid.params.BloodTile == 4 and mid.params.UseCustomBloodOffset == 0,
  "her skin's own mask, tiling and offset back")
check(mids[1].params.Basecolor == suitTex, "her suit's own Basecolor back")
check((pawn.BloodValue or 1) == 0, "no blood left")

-- 8: her death bloodies her, lying there dirties her
at = mark()
E.s.hp = 0
E.die(true)
F.run(8, pawn)
check((pawn.BloodValue or 0) >= 0.34, string.format("her death: blood %.2f", pawn.BloodValue or -1))
check((pawn.DirtValue or 0) > 0.2, string.format("lying dead: dirt %.2f", pawn.DirtValue or -1))
-- 9: her next life (somewhere else) is clean
E.s.z = 0
pawn.K2_GetActorLocation = function() return { X = 9000, Y = 9000, Z = 90 } end
E.respawn()
F.run(3, pawn)
check((pawn.BloodValue or 1) == 0 and (pawn.DirtValue or 1) == 0, "her next life starts clean")

if #F.errors > 0 then for _, e in ipairs(F.errors) do print("FAIL " .. e) end; fails = fails + #F.errors end
dump(1, "^.-stains")
print(fails == 0 and "PASS" or "FAIL")
