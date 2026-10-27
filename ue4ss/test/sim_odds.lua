-- The death odds rolled with the blade left aside (Blade Decides) or none seen follow where the blow landed
-- (gore.near_odds, tune.gore.oddsNear): a clear waist cut rolled a beheading a quarter of the time (playtest). On the
-- made-up Eve (eve.lua, standing, facing +X), the factors each kind's odds are rolled with: a level swing at her waist
-- never beheads or splits, one at her neck beheads, a blade down her length splits, a blow from above never cuts the
-- waist, a hit at her hand takes a limb; odds of one kind alone still roll it wherever the hit (main.lua's pick_kind)
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
local gore = dofile(DIR .. "gore.lua")
local tune = { gore = { oddsNear = { enabled = true } } }
gore.init({ tune = tune, try = function(f, ...) local o, r = pcall(f, ...); if o then return r end end,
  valid = function(x) return x ~= nil end, v3 = function(v) return string.format("%.0f %.0f %.0f", v.X, v.Y, v.Z) end })

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function at(z, x) local b = E.bone("Bip001-Pelvis"); return vec(b.X + (x or 12), b.Y, z + b.Z - 95) end
local function show(name, w)
  print(string.format("  %s: limb %.2f head %.2f torso %.2f split %.2f (%s)", name, w.limb, w.head, w.torso, w.split, w.why))
end
local mesh = E.mesh

-- a level swing (its plane facing up) at her waist, in front of her
local w = gore.near_odds(mesh, { loc = at(110), n = vec(0, 0, 1), dir = vec(0, 1, 0) }, nil)
show("level swing at her waist", w)
check(w.head == 0 and w.split == 0 and w.torso == 1, "a level swing at her waist: never her head nor a split, the waist in full")
-- the same at her neck
w = gore.near_odds(mesh, { loc = at(150), n = vec(0, 0, 1), dir = vec(0, 1, 0) }, nil)
show("level swing at her neck", w)
check(w.head == 1 and w.split == 0 and w.torso <= 0.6, "a level swing at her neck: her head in full, the waist less")
-- a blade down her length (its plane facing her side) at her chest
w = gore.near_odds(mesh, { loc = at(130), n = vec(0, 1, 0), dir = vec(1, 0, -0.3), fwd = vec(1, 0, 0) }, nil)
show("blade down her length", w)
check(w.split == 1 and w.torso <= 0.25 and w.head < 1, "a blade down her length: a split in full, the waist a quarter")
-- a blow from above at her chest
w = gore.near_odds(mesh, { loc = at(130), dir = vec(0.2, 0, -1), fwd = vec(1, 0, 0) }, nil)
show("blow from above", w)
check(w.torso == 0 and w.split > 0, "a blow from above: no waist cut, a split")
-- no blade seen, the hit at her right hand
w = gore.near_odds(mesh, nil, E.bone("Bip001-R-Hand"))
show("no blade, hit at her hand", w)
check(w.limb == 1 and w.head == 0, "no blade, a hit at her hand: a limb, never her head")
check(gore.near_odds(mesh, nil, nil) == nil, "nothing to go by: the odds as they are")
-- floor: a far part keeps that share
tune.gore.oddsNear.floor = 0.1
w = gore.near_odds(mesh, { loc = at(110), n = vec(0, 0, 1), dir = vec(0, 1, 0) }, nil)
check(math.abs(w.head - 0.1) < 1e-6, "floor 0.1: her head keeps a tenth of its odds from a waist swing")
tune.gore.oddsNear.enabled = false
check(gore.near_odds(mesh, { loc = at(110), n = vec(0, 0, 1) }, nil) == nil, "off: the odds as they are")
print(fails == 0 and "PASS" or "FAIL")
