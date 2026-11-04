-- Main.lua's actual classifier and death selection: sharp precedence, attacker isolation, early torso, options.
local T = require("smash_world").boot('s.gore.smash = { enabled = true }\ns.gore.blood = false')
local F, E, G, pawn, v = T.F, T.E, T.G, T.pawn, T.v
local print, fails = F.say, 0
local function check(c, what) print((c and "ok   " or "FAIL ") .. what); if not c then fails = fails + 1 end end
local sw, swing, hm, cut = T.state.sw, T.state.swing, T.state.hm, T.state.gore_cut
assert(sw and swing and hm and cut, "main.lua closure state not found")
local g = T.ctx.tune.gore
local function classify(label, want, opts)
  opts = opts or {}
  g.smash.enabled, g.smash.always, g.bluntRagdoll = opts.enabled ~= false, opts.always == true, opts.ragdoll == true
  g.smash.bareHands = opts.bare ~= false
  swing.who, swing.cls, swing.weapons = opts.who or "Unknown_1", opts.cls or "Unknown_C", {}
  for _, n in ipairs(opts.weapons or {}) do swing.weapons[#swing.weapons + 1] = { name = n } end
  local hit = { attacker = opts.attacker or swing.who, wbone = opts.bone, dir = opts.dir }
  local actual, why = sw.blunt_of(hit, opts.real)
  check(actual == want, label .. ": " .. tostring(why))
end
classify("hammer", true, { weapons = { "SM_HAMMER_Heavy" } })
classify("sword on brute", false, { who = "Brute_1", weapons = { "Sword" } })
classify("sharp wins within one name", false, { weapons = { "HammerBlade" } })
classify("sharp wins across weapon slots", false, { weapons = { "Hammer", "Sword" } })
classify("sharp precedence independent of slot order", false, { weapons = { "Sword", "Hammer" } })
classify("unknown mesh doesn't mask a later hammer", true, { weapons = { "MetalUnknown", "Hammer" } })
classify("weapon bone sharp before blunt enemy", false, { who = "Gorilla_1", bone = "SwordTip" })
classify("weapon bone blunt", true, { bone = "HammerEnd" })
for _, bone in ipairs({ "Bip001-R-Hand", "Bip001-L-Foot", "Toe01", "Knee", "Elbow", "Fist" }) do
  classify("unarmed " .. bone, true, { bone = bone })
end
classify("unarmed disabled", false, { bone = "Hand", bare = false })
classify("unknown weapon with hand bone: do not invent a fist", false, { bone = "Hand", weapons = { "MetalUnknown" } })
classify("stomp", true, { dir = v(0, 0, -1) })
classify("unarmed disabled also excludes a downward unarmed hit", false, { bare = false, dir = v(0, 0, -1) })
classify("level unknown blow", false, { dir = v(1, 0, 0) })
classify("zero direction", false, { dir = v(0, 0, 0) })
classify("weapon from another enemy ignored", false, { who = "Brute_1", attacker = "Unknown_2", weapons = { "Hammer" } })
classify("own weapon overrides nearest enemy", true, { who = "Raven_1", attacker = "Unknown_2", bone = "HammerEnd", weapons = { "Sword" } })
classify("blunt enemy class", true, { cls = "CH_Gorilla_C" })
classify("sharp enemy class", false, { cls = "CH_Raven_C" })
classify("actual Skull Hammer Blueprint", true, { who = "CH_M_NA_16_Blueprint_C_7", weapons = { "CH_M_NA_16_Weapon" } })
classify("actual Skull Sword Blueprint", false, { who = "CH_M_NA_17_Blueprint_C_3", weapons = { "CH_M_NA_17_Weapon" } })
classify("actual Statue Blueprint", true, { who = "CH_M_NA_40_Type_B_Blueprint_C_2" })
check(sw.blunt_alias("CH_M_NA_160_Blueprint_C_1") == nil, "Blueprint mapping respects numeric name boundaries")
classify("off", false, { enabled = false, weapons = { "Hammer" } })
classify("ragdoll can classify with smash off", true, { enabled = false, ragdoll = true, weapons = { "Hammer" } })
classify("always overrides blade", true, { always = true, weapons = { "Sword" } })
classify("real judgement ignores always", false, { always = true, real = true, weapons = { "Sword" } })
classify("always alone cannot enable smash", false, { enabled = false, always = true, weapons = { "Hammer" } })
-- The rock reports its own impact, independently of a misleading mesh shake on the leg.
g.smash.enabled, g.smash.always, g.bluntRagdoll = true, false, false
for _, asset in ipairs({ "M_GorillaB_S18_ThrowStone_Projectile1", "M_GorillaB_S18_ThrowStone2_Projectile1" }) do
  local cls = asset .. "_C"
  local path = "/Game/Art/Character/Monster/CH_M_NA_05/Projectile/" .. asset .. "." .. cls .. ":EventOnHit"
  local projectile = F.obj("Rock", cls)
  sw.rock_watch(projectile); sw.rock_watch(projectile)
  check(F.hooks[path] and #F.hooks[path] == 1, asset .. ": hit hook registered once")
end
local leg = E.bone("Bip001-L-Thigh")
local head, chest = E.bone("Bip001-Head"), E.bone("Bip001-Spine2")
sw.projectileLast = nil
sw.projectile_blueprint_event(F.param(nil), F.param(head), F.param(2))
check(not sw.projectile_hit(), "blueprint projectile miss does not classify")
sw.projectile_blueprint_event(F.param(nil), F.param(v(10000, 10000, 10000)), F.param(1))
check(not sw.projectile_hit(), "distant blueprint hit does not classify")
sw.projectile_blueprint_event(F.param(nil), F.param(head), F.param(1))
check(sw.projectile_hit() and sw.blunt_of(sw.projectile_hit()), "nearby successful blueprint projectile hit can select smash")
sw.projectileLast = nil
sw.rockLast = { t = os.clock(), loc = head }
local rockTarget = sw.rock_hit(E.mesh, { t = os.clock(), loc = leg })
check(rockTarget and G.smash_part(E.mesh, rockTarget) == "Bip001-Head", "rock near head ignores misleading leg shake")
sw.rockLast = { t = os.clock(), loc = chest }
rockTarget = sw.rock_hit(E.mesh, { t = os.clock(), loc = leg })
check(rockTarget and G.smash_part(E.mesh, rockTarget) == "Bip001-Spine1", "rock near chest targets upper body")
check(sw.blunt_of({ rock = true }) == true, "identified rock is blunt even without a synthetic downward swing")
check(sw.rock_hit(E.mesh, { t = os.clock() - 1, loc = leg }) == nil, "old shake cannot be paired with rock")
sw.rockLast = { t = os.clock() - 2, loc = head }
check(sw.rock_hit(E.mesh, { t = os.clock() - 2, loc = leg }) == nil, "old rock cannot affect a later death")
sw.rockLast = { t = os.clock(), loc = v(10000, 10000, 10000) }
check(sw.rock_hit(E.mesh, { t = os.clock(), loc = leg }) == nil, "distant rock cannot override an unrelated hit")
sw.rockLast = nil
-- The generic broadcast includes target, result, point and projectile identity from the SDK.
local function projectile(target, result, point)
  F.fire("/Script/SB.SBNetworkPlayerController:ClientBroadcast_ProjectileHitResult", F.param(nil), F.param(1),
    F.param(991), F.param(target), F.param(F.fname("Result")), F.param(result), F.param(point),
    F.param(v(0,0,1)), F.param(F.fname("Bip001-Head")), F.param(v(1,0,0)), F.param(F.fname("None")))
end
sw.projectileLast = nil
local impactProjectile = F.obj("Projectile", "SBProjectile", {
  K2_GetActorLocation = function() return head end,
  GetVelocity = function() return v(10, 0, 0) end,
})
local collision = "/Script/SB.SBProjectile:OnCollisionOriginBeginOverlap"
check(F.hooks[collision] and #F.hooks[collision] > 0, "single-player projectile overlap hook registered")
F.fire(collision, F.param(impactProjectile), F.param(nil), F.param(F.obj("Other", "Actor")), F.param(nil),
  F.param(0), F.param(true), F.param({ ImpactPoint = head }))
check(not sw.projectile_hit(), "collision on another actor does not mark Eve")
F.fire(collision, F.param(impactProjectile), F.param(nil), F.param(pawn), F.param(nil),
  F.param(0), F.param(true), F.param({ ImpactPoint = head }))
check(sw.projectile_hit() and sw.projectile_hit().loc.Z == head.Z, "projectile overlap on Eve records impact")
sw.projectileLast = nil
projectile(9999, 1, head)
check(sw.projectile_hit() == nil, "projectile hitting another actor is ignored")
projectile(4242, 2, head)
check(sw.projectile_hit() == nil, "projectile miss is ignored")
projectile(4242, 1, head)
local projectileHit = sw.projectile_hit()
check(projectileHit and projectileHit.projectile and sw.blunt_of(projectileHit), "a projectile hit on Eve classifies as smash")
check(projectileHit and projectileHit.loc.Z == head.Z, "projectile result supplies the impact location")
local savedSmash, observed = G.smash, nil
G.smash = function(_, _, hit) observed = hit; return true end
hm.lethal = {t=F.t, projectile=projectileHit}
cut(pawn,E.mesh,nil,nil)
check(observed == projectileHit, "deferred projectile hit reaches the death smash path")
G.smash, hm.lethal = savedSmash, nil
F.t = F.t + 0.7
check(sw.projectile_hit() == nil, "old projectile result does not classify a later hit")
sw.projectileLast = nil
hm.deadMsg={t=F.t,proj=42,effect=0}
check(sw.death_projectile(E.mesh) and sw.blunt_of(sw.death_projectile(E.mesh)), "projectile ID in death broadcast selects smash")
hm.deadMsg={t=F.t,proj=0,effect=0}
check(sw.death_projectile(E.mesh)==nil, "empty death projectile ID does not select smash")
hm.deadMsg={t=F.t,proj=42,effect=8000005}
check(sw.death_projectile(E.mesh)==nil, "fall-damage effect retains priority over projectile ID")
hm.deadMsg=nil
-- An option which needs blunt detection must not silently enable a disabled feature.
g.smash.enabled, g.smash.always, g.bluntRagdoll = false, false, true
swing.who, swing.weapons = "Gorilla_1", {}
local called, smash = 0, G.smash
G.smash = function() called = called + 1; return true end
check(not sw.smash_kill(pawn, E.mesh, { attacker = "Gorilla_1" }, "death") and called == 0,
  "smash_kill refuses when Blunt Smash is off, even with blunt detection active")
g.smash.enabled, g.bluntRagdoll = true, false
g.enabled = false
check(not sw.smash_kill(pawn, E.mesh, { attacker = "Gorilla_1" }, "death") and called == 0, "all gore off prevents smash")
g.enabled = true
-- The early torso path must defer, then replay the same hit at death without retaining h.early.
G.smash = smash
local h = { t = F.t, loc = E.bone("Bip001-Spine2"), attacker = "Gorilla_1", early = true }
local done, wait = sw.smash_kill(pawn, E.mesh, h, "death")
check(not done and wait == "later", "torso hit deferred until death")
hm.lethal = { t = F.t, held = h }
-- In a grab the real deferred-hit helper clears early as soon as it stores the hit.
hm.lethal = { t = F.t, grab = {} }
hm.grab_keep(h)
check(hm.lethal.held == h and not h.early, "grab helper preserves the hit and releases the early-only restriction")
E.s.sim = true
cut(pawn, E.mesh, nil, nil)
for _ = 1, 30 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] == true, "deferred early torso hit smashes at death")
G.cleanup(pawn, E.mesh)
-- Selection must respect the same death chance gate as a normal cut.
hm.lethal = nil
g.smash.always, g.sliceChance = true, 0
called = 0
G.smash = function() called = called + 1; return true end
cut(pawn, E.mesh, nil, nil)
check(called == 0, "zero death slice chance prevents smash too")
g.sliceChance, g.sliceOnDeath = 1, false
cut(pawn, E.mesh, nil, nil)
check(called == 0, "death cuts off prevents smash")
g.sliceOnDeath, g.bluntRagdoll = true, true
cut(pawn, E.mesh, { t = F.t, attacker = "Gorilla_1" }, nil)
check(called == 0, "Blunt Kills Only Ragdoll takes priority over Smash Every Death")
g.bluntRagdoll = false
hm.fellAt = F.t
cut(pawn, E.mesh, nil, nil)
check(called == 0, "fall damage never smashes, even with Smash Every Death")
local laser, blow = sw.laser_hit, G.blow
sw.laser_hit = function() return { laser = true } end
G.blow = function() return true end
cut(pawn, E.mesh, nil, nil)
check(called == 0, "laser cuts take priority over Smash Every Death")
sw.laser_hit, G.blow = laser, blow
G.smash = smash
g.smash.always, g.smash.fullBody, g.smash.fullBodyChance = false, true, 1
local full = { attacker = "Gorilla_1", loc = chest, dir = v(1, 0, 0), impactRadius = 200 }
swing.who, swing.cls, swing.weapons = "Gorilla_1", "Unknown_C", {}
g.smash.fullBodyChance=0
check(sw.smash_kill(pawn, E.mesh, full, "death"), "zero full-body chance still starts torso smash")
for _ = 1, 100 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] and not E.hiddenBones["Bip001-Pelvis"], "zero chance retains the lower body")
G.cleanup(pawn, E.mesh)
g.smash.fullBodyChance=1
full.loc = E.bone("Bip001-L-Forearm")
full.smashFullRoll = nil
check(sw.smash_kill(pawn, E.mesh, full, "death"), "full-body smash starts on a limb hit")
for _ = 1, 100 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] and E.hiddenBones["Bip001-Pelvis"], "full-body smash hides torso and pelvis")
check(G.has_cut(E.mesh, "Bip001-L-Thigh") and G.has_cut(E.mesh, "Bip001-Head"), "full-body smash rejects later cuts on all body parts")
G.cleanup(pawn, E.mesh)
check(not E.hiddenBones["Bip001-Spine1"] and not E.hiddenBones["Bip001-Pelvis"], "full-body recovery restores both")
g.smash.fullBody=false
sw.projectileVolley={}
sw.projectile_record({t=F.t,loc=chest,src="blueprint",projectile=true},"volley1")
local firstVolleyHit=sw.projectileLast
sw.projectile_record({t=F.t,loc=chest,src="blueprint",projectile=true},"volley1")
check(sw.projectileLast.volley==1, "duplicate projectile callback does not make a volley")
sw.projectile_record({t=F.t,loc=chest,src="blueprint",projectile=true},"volley2")
local volleyHit=sw.projectileLast
check(volleyHit.volley==2, "two distinct simultaneous projectiles form a volley")
check(firstVolleyHit.volley==2, "a previously saved lethal hit learns about the later volley impact")
check(G.smash(pawn,E.mesh,volleyHit,"death"), "projectile volley starts a smash with full-body override off")
for _ = 1, 100 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] and not E.hiddenBones["Bip001-Pelvis"], "projectile count alone cannot bypass disabled full-body or missing footprint")
G.cleanup(pawn, E.mesh)
F.step(0.4)
sw.projectile_record({t=F.t,loc=chest,src="blueprint",projectile=true},"volley3")
check(sw.projectileLast.volley==1, "old impacts do not make a later shot a volley")
g.smash.fullBody=true
check(G.slice_bone(pawn, E.mesh, "Bip001-L-Thigh", nil, "test"), "prior leg cut starts")
for _ = 1, 40 do F.step(1/60); G.tick(pawn); G.pump() end
check(sw.smash_kill(pawn, E.mesh, { attacker = "Gorilla_1", loc = chest, dir = v(0, 0, -1) }, "death"), "smash after a prior cut starts")
for _ = 1, 100 do F.step(1/60); G.tick(pawn); G.pump() end
check(E.hiddenBones["Bip001-Spine1"] and not E.hiddenBones["Bip001-Pelvis"], "prior cut keeps its piece: only the upper body is smashed")
G.cleanup(pawn, E.mesh)
-- A player who sets only vertical split must not have the split replaced by the two-arm override.
local savedDeath, savedSplit, savedBlow, savedLaser = g.death, G.split, G.blow, sw.laser_hit
g.smash.enabled, g.noSplits, g.deathSplit, g.armsOverSplit = false, false, true, 1
g.death={limb=0,head=0,torso=0,diagonal=0,split=100}
check(G.only_split(), "split-only configuration detected")
g.death.diagonal=15; g.diagonal.enabled=false
check(G.only_split(), "a parked diagonal weight does not override split-only odds")
local random = math.random
math.random = function() return 0.1 end
check(hm.death_roll(true, {limb=1,head=1,torso=1,split=0,diagonal=0}) == "split",
  "disabled diagonal weight cannot send a vertical-only death to the blade")
math.random = function() return 0.99 end
local savedFollow = g.bladeFollow
g.bladeFollow = 0
check(hm.death_roll(true, {limb=1,head=1,torso=1,split=1,diagonal=100}) == "split",
  "disabled diagonal weight cannot dilute proximity-adjusted split odds")
g.diagonal.enabled=true
check(not G.only_split(), "an enabled diagonal weight permits normal alternatives")
check(hm.death_roll(true, {limb=1,head=1,torso=1,split=1,diagonal=100}) == "odds",
  "enabled diagonal weight remains a proximity-adjusted alternative")
math.random, g.bladeFollow = random, savedFollow
g.diagonal.enabled=false; g.death.diagonal=0
check(hm.death_roll(true, {limb=1,head=1,torso=1,split=0,diagonal=0})=="split", "split-only survives a level hit even if proximity excludes splits")
local splitCalls, blowCalls = 0, 0
G.split=function() splitCalls=splitCalls+1; return true end
G.blow=function() blowCalls=blowCalls+1; return true end
sw.laser_hit=function() return nil end
hm.lethal={t=os.clock(),roll="split"}
cut(pawn,E.mesh,{t=os.clock(),loc=chest,n=v(0,0,1),dir=v(1,0,0)},chest)
check(splitCalls==1 and blowCalls==0, "split-only death cannot be replaced by the two-arm override")
-- Exercise the real failed second split stage, including the fallback decision.
local function uv(fn, name)
  for i=1,100 do local n,value=debug.getupvalue(fn,i); if not n then break end; if n==name then return value,i end end
  error("missing upvalue "..name)
end
local stageTick=uv(G.pump_once,"stage_tick")
local step=uv(stageTick,"stage_step")
local tickSplit=uv(step,"split_tick")
local stage=uv(tickSplit,"split_stage")
local oldStart,startIndex=uv(stage,"start")
local oldCopy, oldUndo = G.stage_split_copy, G.undo_split
local fallback=0
debug.setupvalue(stage,startIndex,function() fallback=fallback+1; return true end)
G.stage_split_copy=function(q) q.degenerate=true; return false end
G.undo_split=function() end
stage({stage="cut3",middle=true,kind="split",why="death",mesh=E.mesh,pawn=pawn})
check(fallback==0,"failed split-only retry never substitutes a waist cut")
g.death={limb=1,head=0,torso=0,split=100}
stage({stage="cut3",middle=true,kind="split",why="death",mesh=E.mesh,pawn=pawn})
check(fallback==1,"failed split with mixed odds retains waist fallback")
debug.setupvalue(stage,startIndex,oldStart)
G.stage_split_copy, G.undo_split = oldCopy, oldUndo
g.death={limb=1,head=0,torso=0,split=100}
check(not G.only_split(), "mixed odds retain normal cut alternatives")
g.death, G.split, G.blow, sw.laser_hit = savedDeath, savedSplit, savedBlow, savedLaser
hm.lethal=nil
-- An aborted split after an existing cut restores the original and must release the copy separately.
local cutList=uv(G.undo_split,"cuts")
local cloneList=uv(G.undo_split,"clones")
local splitClone=F.obj("FailedSplitCopy","SkeletalMeshComponent")
splitClone.K2_DestroyComponent=function(self) self.__dead=true; F.event("failed split copy destroyed") end
local srcAddr, copyAddr=E.mesh:GetAddress(),splitClone:GetAddress()
cutList[#cutList+1]={mesh=E.mesh,addr=srcAddr,bone="split",saved=true,copy=copyAddr}
cutList[#cutList+1]={mesh=splitClone,addr=copyAddr,bone="split copy"}
cloneList[#cloneList+1]=splitClone
F.sbslice.R="ok back, dropped 0"
local eventsBefore=#F.events
G.undo_split()
local restored, released, destroyed
for i=eventsBefore+1,#F.events do
  local what=F.events[i].what
  if what==string.format("sbslice R%x,0,%x",srcAddr,copyAddr) then restored=i end
  if what==string.format("sbslice x%x,0,1",copyAddr) then released=i end
  if what=="failed split copy destroyed" then destroyed=i end
end
check(restored and released and destroyed and restored<released and released<destroyed,
  "failed split restores previous cut and releases copy weights before destruction")
-- A reported post-death projectile is consumed on a later tick, once, without enemy scanning.
local oldSmash, oldBusy, oldCuts, oldAim = G.smash, G.busy, G.cuts_on, G.aim
local delivered, blocked = 0, false
G.smash=function(_,_,hit,why) if why=="after" then delivered=delivered+1 end; return true end
G.busy=function() return blocked end
G.cuts_on=function() return 0,false end
G.aim=function() end
g.enabled=true; g.smash.enabled=true; g.bluntRagdoll=false; g.afterHits.enabled=true
local activeBefore, activeIndex=uv(sw.projectile_record,"active")
local ah=uv(sw.projectile_record,"ah")
debug.setupvalue(sw.projectile_record,activeIndex,true)
ah.n,ah.t0,ah.blunt,ah.projectiles,ah.projectileRecent=0,F.t-1,nil,{},{}
local hitsAfter=assert(T.state.hits_after)
ah.t0=F.t
sw.projectileVolley={}
sw.projectile_record({t=F.t,loc=head,src="projectile collision",projectile=true},"early")
hitsAfter(pawn,E.mesh)
check(delivered==0 and #ah.projectiles==1, "early post-death shot waits for the initial delay")
F.step(0.7); hitsAfter(pawn,E.mesh)
check(delivered==1, "early post-death shot is processed after the initial delay")
delivered=0; ah.n=0; ah.projectileAt=nil; ah.projectileRecent={}; ah.projectileVolley={}; ah.t0=F.t-1
local _, pawnSeenIndex=uv(sw.projectile_blueprint_event,"pawnSeen")
debug.setupvalue(sw.projectile_blueprint_event,pawnSeenIndex,F.t)
local bullet=F.obj("AfterDeathProjectile","SBProjectile")
sw.projectile_blueprint_event(F.param(bullet),F.param(head),F.param(1))
sw.projectile_blueprint_event(F.param(bullet),F.param(head),F.param(1))
hitsAfter(pawn,E.mesh)
check(delivered==1,"duplicate projectile callbacks produce one post-death smash")
blocked=true
local bullet2=F.obj("AfterDeathProjectile2","SBProjectile")
debug.setupvalue(sw.projectile_blueprint_event,pawnSeenIndex,F.t)
sw.projectile_blueprint_event(F.param(bullet2),F.param(head),F.param(1))
F.step(0.4); hitsAfter(pawn,E.mesh)
check(delivered==1,"busy gore pipeline defers the projectile smash")
blocked=false; F.step(0.3); hitsAfter(pawn,E.mesh)
check(delivered==2,"deferred projectile smash runs after the pipeline is free")
g.afterHits.enabled=false
debug.setupvalue(sw.projectile_blueprint_event,pawnSeenIndex,F.t)
sw.projectile_blueprint_event(F.param(F.obj("DisabledShot","SBProjectile")),F.param(head),F.param(1))
F.step(0.5); hitsAfter(pawn,E.mesh)
check(delivered==2,"Hits After Death off prevents projectile smashes")
g.afterHits.enabled=true; g.smash.enabled=false
sw.projectile_record({t=F.t,loc=head,src="projectile collision"},"off")
check(#ah.projectiles==0,"Blunt Smash off does not queue projectile smashes")
g.smash.enabled=true; ah.n=g.afterHits.max
sw.projectile_record({t=F.t,loc=head,src="projectile collision"},"limit")
check(#ah.projectiles==0,"the shared per-death hit limit prevents projectile queuing")
ah.n=0; ah.projectileRecent={}; blocked=true
for i=1,8 do sw.projectile_record({t=F.t,loc=head,src="projectile collision"},"queue"..i) end
check(#ah.projectiles==4,"the projectile queue is bounded during a busy gore pipeline")
F.step(1.6); blocked=false; hitsAfter(pawn,E.mesh)
check(#ah.projectiles==0 and delivered==2,"stale queued projectile impacts expire")
G.smash,G.busy,G.cuts_on,G.aim=oldSmash,oldBusy,oldCuts,oldAim
debug.setupvalue(sw.projectile_record,activeIndex,activeBefore)
for _, e in ipairs(F.errors) do print("FAIL hook: " .. e); fails = fails + 1 end
print(fails == 0 and "PASS" or "FAIL")
