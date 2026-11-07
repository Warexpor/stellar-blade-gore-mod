-- Hit-size collection, area-based local targeting, and footprint-weighted full-body eligibility.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false\ns.gore.torsoLegs = { enabled = false }')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local sw, s = T.state.sw, T.ctx.tune.gore.smash
local print, fails = F.say, 0
local function check(c, label)
  print((c and "ok   " or "FAIL ") .. label)
  if not c then fails = fails + 1 end
end
local function close(a, b) return math.abs(a-b) < 0.00001 end
check(s.fullBody == true and dofile(T.dir .. "settings.default.lua").gore.smash.fullBody == true,
  "full-body eligibility is on in both shipped defaults")
check(s.fullBodyChance == 0.5 and dofile(T.dir .. "settings.default.lua").gore.smash.fullBodyChance == 0.5,
  "full-body chance defaults to 0.5 in both shipped defaults")
check(close(G.smashed.overlap(10,10,0),math.pi*100), "coincident contact circles cover the full area")
check(G.smashed.overlap(10,10,20) == 0, "tangent circles have no contact area")
check(close(G.smashed.overlap(5,10,0),math.pi*25), "contained footprint uses the smaller area")
check(G.smashed.overlap(10,10,5) > G.smashed.overlap(10,10,15), "contact area falls as the hit moves away")
local candidates = { {bone="arm",d=0,surface=0,radius=4}, {bone="torso",d=15,surface=1,radius=14} }
check(G.smash_choose(candidates,4).bone == "arm", "small contact stays on the directly struck arm")
check(G.smash_choose(candidates,30).bone == "torso", "broad contact favours the larger covered body surface")
check(close(sw.cross_radius(v(500,4,9)),6), "weapon shaft length cannot inflate its striking cross-section")
check(close(sw.cross_radius(v(500,4,9),v(2,3,4)),math.sqrt(12*36)), "world scaling changes cross-section area")
check(sw.cross_radius(v(0,4,9)) == nil, "degenerate bounds do not invent a hit size")

local head, chest = E.bone("Bip001-Head"), E.bone("Bip001-Spine2")
check(G.smashed.coverage(E.mesh,{loc=head,impactRadius=6}) == 0, "small face hit has no full-body eligibility")
check(G.smashed.coverage(E.mesh,{loc=chest,impactRadius=8}) == 0, "small chest hit has no full-body eligibility")
local medium = G.smashed.coverage(E.mesh,{loc=chest,impactRadius=40})
local broad = G.smashed.coverage(E.mesh,{loc=chest,impactRadius=200})
check(medium > 0 and medium < broad and close(broad,1), "full-body weight grows with covered body area")
check(G.smashed.coverage(E.mesh,{loc=v(5000,5000,5000),impactRadius=200}) == 0,
  "the same broad footprint cannot roll full-body far from Eve")
for _, radius in ipairs({0,-1,0/0,math.huge}) do
  check(G.smashed.coverage(E.mesh,{loc=chest,impactRadius=radius}) == 0, "invalid or empty radius cannot promote full-body")
end
local pose = G.pose(E.mesh)
local socket = E.mesh.GetSocketLocation
E.mesh.GetSocketLocation = function() error("coverage must use captured pose") end
check(close(G.smashed.coverage(E.mesh,{loc=chest,impactRadius=200,pose=pose}),1),
  "coverage uses the impact-time pose without rereading moving bones")
E.mesh.GetSocketLocation = socket

local sphere = F.obj("RockSphere", "SphereComponent", {GetScaledSphereRadius=function() return 90 end})
local rock = F.obj("Rock", "M_GorillaB_S18_ThrowStone_Projectile1_C", {PhysicsShapeComponent=sphere})
local radius = sw.impact_radius(rock)
check(radius == 90, "projectile footprint reads its scaled collision sphere")
local box = F.obj("Box", "BoxComponent", {GetScaledBoxExtent=function() return v(100,4,9) end})
check(close(sw.impact_radius(rock,box),6), "actual hitting component takes priority over a larger actor shape")
check(sw.impact_radius(F.obj("UnknownProjectile", "SBProjectile")) == nil,
  "missing projectile dimensions stay unknown")
for i = 1, 100 do
  local name = debug.getupvalue(sw.rock_event, i)
  if not name then break end
  if name == "pawnSeen" then debug.setupvalue(sw.rock_event,i,os.clock()); break end
end
local originalPose, poseReads = G.pose, 0
G.pose = function(mesh) poseReads = poseReads + 1; return originalPose(mesh) end
sw.rock_event(F.param(rock),F.param(chest),F.param(1))
sw.projectile_blueprint_event(F.param(rock),F.param(chest),F.param(1))
check(poseReads == 1, "generic rock callback reuses the same impact-time pose")
G.pose = originalPose
local hit = T.state.death_hit(pawn,E.mesh)
check(hit and hit.rock and hit.impactRadius == 90 and hit.impactSizeSource == "collision radius",
  "rock correction preserves measured footprint through generic projectile selection")
sw.projectile_collision(F.param(rock),F.param(box),F.param(pawn),F.param(nil),F.param(0),F.param(true),F.param({ImpactPoint=chest}))
check(close(sw.projectileLast.impactRadius,6), "native target-aware collision records the contacting component's area")
check(sw.projectileLast.pose and sw.projectileLast.pose["Bip001-Pelvis"],
  "generic projectile collision also retains an impact-time body pose")

local function run() for _ = 1,100 do F.step(1/60); G.tick(pawn); G.pump() end end
local function smash(label, h, full, bone)
  E.s.sim = true
  check(G.smash(pawn,E.mesh,h,"death"),label .. ": smash starts")
  run()
  check(E.hiddenBones[bone] == true and (E.hiddenBones["Bip001-Pelvis"] == true) == full,
    label .. ": expected local/full result")
  G.cleanup(pawn,E.mesh)
end
s.fullBody, s.fullBodyChance = true, 1
smash("small face hit even at maximum chance",{loc=head,impactRadius=6},false,"Bip001-Head")
smash("unknown footprint",{loc=chest},false,"Bip001-Spine1")
smash("body-covering impact",{loc=chest,impactRadius=200},true,"Bip001-Spine1")
s.fullBody = false
smash("disabled full-body with broad volley",{loc=chest,impactRadius=200,projectile=true,volley=2},false,"Bip001-Spine1")
s.fullBody = true
smash("two narrow shots do not invent broad contact",{loc=chest,impactRadius=6,projectile=true,volley=2},false,"Bip001-Spine1")
s.fullBodyChance = 0.7
smash("a four-hit volley promotes a broad impact (0.7 + 0.3 bonus)",{loc=chest,impactRadius=200,projectile=true,volley=4},true,"Bip001-Spine1")
s.fullBodyChance = 0
smash("zero maximum chance",{loc=chest,impactRadius=200},false,"Bip001-Spine1")
smash("zero maximum chance ignores even a volley",{loc=chest,impactRadius=200,projectile=true,volley=2},false,"Bip001-Spine1")
s.fullBodyChance = 1
E.s.sim = true
G.slice_bone(pawn,E.mesh,"Bip001-L-Forearm",nil,"test")
run()
G.smash(pawn,E.mesh,{loc=chest,impactRadius=200},"death")
check(not G.full_smash_active(E.mesh), "prior cuts still prevent full-body promotion")
run(); G.cleanup(pawn,E.mesh)
for _, err in ipairs(F.errors) do print("FAIL hook: " .. err); fails = fails + 1 end
print(fails == 0 and "PASS" or "FAIL")
