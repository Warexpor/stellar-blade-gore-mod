-- Native skin-layer behaviour: no replacement materials/painting; damage, healing, water, range and no cut flash.
local F = require("fake")
local values, writes = {}, {}
F.objects["/Game/Art/FX/MPC/MPC_PCDirtyOffset.MPC_PCDirtyOffset"] = F.obj("SkinCollection", "MaterialParameterCollection")
F.objects["/Script/Engine.Default__KismetMaterialLibrary"] = F.obj("KML", "KismetMaterialLibrary", {
  SetScalarParameterValue = function(_, _, _, name, value)
    values[tostring(name)] = value
    writes[#writes + 1] = { name = tostring(name), value = value, at = F.t }
  end,
  GetScalarParameterValue = function(_, _, _, name) return values[tostring(name)] or 0 end,
})
local T = require("smash_world").boot([[
s.stains.enabled = true
s.gore.bodyBlood = { enabled = true, factor = 1, offset = 1, time = 0.1 }
s.stains.cloth = { enabled = true }
s.stains.wounds = { enabled = true }
s.stains.spatter = { enabled = true }
s.gore.blood = false
s.gore.torsoLegs = { enabled = false }
]])
local E, G, pawn, S, c = T.E, T.G, T.pawn, T.ctx.stains, T.ctx.tune.stains
rawset(pawn, "GetCurrentStanceName", function() return F.fname(E.s.stance or "Idle") end)
rawset(pawn, "IsBattle", function() return false end)
local state, fails = S._st, 0
local function check(ok, what)
  F.say((ok and "ok   " or "FAIL ") .. what)
  if not ok then fails = fails + 1 end
end
local function close(a,b) return math.abs(a-b) < 0.0001 end
local function run(seconds, dead)
  for _ = 1, math.floor(seconds * 60 + 0.5) do
    F.step(1/60); S.tick(pawn, E.mesh, dead == true); G.tick(pawn); G.pump()
  end
end
local function clean()
  E.s.hp, E.s.mode, E.s.stance = 1, 1, "Idle"
  S.clean_all("test"); run(4)
end
check(close(values.BloodOffset,0) and close(values.DirtOffset,0), "native skin collection starts clean")
check(close(pawn.BloodValue,0) and close(pawn.DirtValue,0), "Blueprint values agree with native offsets")
check(c.splash.range == 1000, "default enemy splatter range increased to 10 m")
local paints, queries = 0, 0
F.objects["/Script/Engine.Default__KismetRenderingLibrary"] = F.obj("NoPaint", "KismetRenderingLibrary", {
  CreateRenderTarget2D = function() paints = paints + 1; error("native skin must not paint") end,
})
local skin_query = G.skin_query
G.skin_query = function() queries = queries + 1; error("native skin must not query/paint wounds") end
local materialCalls = 0
local create = E.mesh.CreateDynamicMaterialInstance
E.mesh.CreateDynamicMaterialInstance = function(...) materialCalls = materialCalls + 1; return create(...) end
E.s.hp = 0.7
run(0.12)
check(state.goalB > 0.25 and state.blood > 0 and state.blood < state.goalB, "HP damage accumulates blood with gradual visible buildup")
local last = state.blood
local smooth = true
for _ = 1,20 do run(0.12); smooth = smooth and state.blood >= last and state.blood-last <= 0.081; last = state.blood end
check(smooth and close(state.blood,state.goalB), "buildup is monotone and reaches the accumulated level")
local before = state.blood
E.s.hp = 0.85; run(0.12)
check(close(state.goalB,before*0.5) and state.blood > state.goalB, "half of missing HP healed removes half the target, with a visible fade")
run(1)
E.s.hp = 1; run(0.12)
check(close(state.goalB,0) and state.blood > 0, "full heal targets clean without an instant pop")
run(1)
check(close(state.blood,0), "full heal finishes clearing native blood")
-- Repeated tiny healing steps must not be discarded by a per-frame HP threshold.
E.s.hp = 0.9; run(0.2)
S.add(0.5,0.3,"test"); run(1)
for i=1,200 do E.s.hp = math.min(1,0.9+i*0.0005); run(0.12) end
run(3)
check(close(state.blood,0) and close(state.dirt,0), "small regeneration steps eventually clear blood and dirt")
E.s.hp=0.99998; run(0.2)
S.add(0.4,0,"tiny regeneration"); run(1)
for i=1,200 do E.s.hp=math.min(1,0.99998+i*0.0000001); run(0.12) end
E.s.hp=1; run(2)
check(close(state.blood,0), "sub-threshold regeneration accumulates and reaching full HP always clears blood")
S.add(0.8,0.6,"water test"); run(2)
local wetB,wetD = state.blood,state.dirt
E.s.mode = 4; run(0.2)
check(state.blood > 0 and state.blood < wetB and state.dirt > 0 and state.dirt < wetD, "water clears both gradually")
run(4)
check(close(state.blood,0) and close(state.dirt,0), "swimming washes both layers completely clean")
check(paints==0 and queries==0 and materialCalls==0, "native layer only: no masks, wound queries, outfit paint or material replacements, even with old options saved")
G.skin_query, E.mesh.CreateDynamicMaterialInstance = skin_query, create
E.s.mode = 1
-- Actual nearby enemy hit polling, including repeated blows at the same point with changing force.
local at = { X = state.her.X + 800, Y = state.her.Y, Z = state.her.Z }
local em = F.obj("MonsterMesh","SkeletalMeshComponent", {
  PhysicalHitForceLocation = at, PhysicalHitForceVector = {X=1,Y=0,Z=0},
})
local enemy = F.obj("Monster","SBCharacter", { Mesh = em })
local chars, char_at = T.ctx.live_chars, T.ctx.char_at
T.ctx.live_chars = function() return { {addr=enemy:GetAddress(),obj=enemy} } end
T.ctx.char_at = function() return at end
run(0.2)
local b = state.goalB
em.PhysicalHitForceVector = {X=2,Y=0,Z=0}; run(0.2)
check(state.goalB > b, "enemy hit at 8 m adds blood (outside the former 3.5 m range)")
b = state.goalB
run(0.5)
check(close(state.goalB,b), "an unchanged enemy hit is counted once")
em.PhysicalHitForceVector = {X=3,Y=0,Z=0}; run(0.2)
check(state.goalB > b, "another hit at the same location still counts")
b = state.goalB
S.splash({X=state.her.X+1100,Y=state.her.Y,Z=state.her.Z},"cut")
check(close(state.goalB,b), "hits/cuts outside 10 m add no blood")
S.splash({X=state.her.X+500,Y=state.her.Y,Z=state.her.Z},"cut")
check(state.goalB > b, "enemy cut inside range adds blood gradually")
-- A crowded scene processes at most eight enemies per update, but eventually observes all of them.
local crowd, reads = {}, 0
for i=1,20 do
  local m = F.obj("CrowdMesh"..i,"SkeletalMeshComponent",{PhysicalHitForceLocation=at, PhysicalHitForceVector={X=1,Y=0,Z=0}})
  local o = F.obj("Crowd"..i,"SBCharacter",{Mesh=m})
  crowd[i] = {addr=o:GetAddress(),obj=o}
end
T.ctx.live_chars = function() return crowd end
T.ctx.char_at = function() reads=reads+1; return at end
local t0=F.t
F.step(0.11); S.tick(pawn,E.mesh,false)
check(reads<=8, "crowded scene: nearby-hit reads bounded per update")
run(0.5)
local observed=0; for _ in pairs(state.others) do observed=observed+1 end
check(observed==20, "crowded scene: all nearby enemies eventually observed")
T.ctx.live_chars, T.ctx.char_at = chars, char_at
clean()
-- Dirt uses the game's own layer, without changing any outfit materials.
E.s.mode = 3; E.s.falling = true; run(0.2)
E.s.mode = 1; E.s.falling = false; run(0.2)
check(state.goalD > 0 and state.dirt > 0, "hard landing adds native dirt")
local d = state.goalD
E.s.stance = "Down"; run(0.2)
check(state.goalD > d, "knockdown adds dirt")
run(0.4); d = state.goalD
run(0.5)
check(close(state.goalD,d), "one knockdown is not reapplied every tick")
clean()
-- No HP lost: a cut/smash must never flash the global skin blood, even when legacy bodyBlood is explicitly on.
T.ctx.tune.gore.blood = true
S.add(0.2,0,"preexisting blood"); run(1)
local stable = state.blood
for _, smash in ipairs({false,true}) do
  for _, bone in ipairs({"Bip001-L-UpperArm","Bip001-Head","Bip001-Spine1"}) do
    E.s.sim = true
    local n0 = #writes
    if smash then G.smash_once = true end
    G.slice_bone(pawn,E.mesh,bone,nil,"test")
    G.smash_once = nil
    run(1)
    local noFlash = true
    for i=n0+1,#writes do
      local w=writes[i]
      if w.name=="BloodOffset" then noFlash=noFlash and close(w.value,stable) end
      if w.name=="BloodFactor" then noFlash=false end
    end
    check(noFlash and close(state.blood,stable), (smash and "smash " or "cut ")..bone..": no global skin-blood jump or competing ramp")
    G.cleanup(pawn,E.mesh)
    run(0.2)
    check(close(values.BloodOffset,stable), "gore cleanup leaves accumulated native stains alone")
  end
end
G.blood_restore={BloodOffset=1,BloodFactor=1}
run(0.2)
check(G.blood_restore==nil and close(values.BloodOffset,stable), "stale reload blood restore cannot overwrite native stains")
T.ctx.tune.gore.blood = false
clean()
S.add(0.5,0.5,"rest"); run(1)
local rest = T.ctx.rest_seq
T.ctx.rest_seq = function() return true end
E.s.mode=0; run(2)
check(close(state.blood,0) and close(state.dirt,0), "camp rest clears both layers")
T.ctx.rest_seq=rest
E.s.mode=1
-- Water also washes a dead body, without re-adding floor dirt under water.
S.add(0.6,0.6,"dead water"); run(1)
E.s.mode=4; run(5,true)
check(close(state.blood,0) and close(state.dirt,0), "underwater dead body washes clean without new floor dirt")
-- Toggle off releases ownership instead of continually zeroing the game's collection.
c.enabled=false; run(0.2)
values.BloodOffset,values.DirtOffset=0.19,0.21
run(1)
check(values.BloodOffset==0.19 and values.DirtOffset==0.21, "feature off leaves native values alone")
-- A new world may have freed every old UObject; the skin system must drop them without querying them.
c.enabled=true
F.free_world()
T.ctx.glass.forget()
S.forget()
pawn=E.make(F)
S.tick(pawn,E.mesh,false)
check(state.blood==0 and state.dirt==0, "new pawn/world starts clean")
check(#F.errors==0, "no errors or reads of freed world objects")
for _,e in ipairs(F.errors) do F.say("FAIL "..e); fails=fails+1 end
F.say(fails==0 and "PASS" or "FAIL")
