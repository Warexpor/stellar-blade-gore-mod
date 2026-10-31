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
for _, e in ipairs(F.errors) do print("FAIL hook: " .. e); fails = fails + 1 end
print(fails == 0 and "PASS" or "FAIL")
