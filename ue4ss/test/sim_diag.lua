-- The diagonal cut (gore.diag_plane, gore.diagonal): from over one shoulder down across her to over the other hip.
-- On the made-up Eve (eve.lua, standing, facing +X, her right -Y): the plane's angle off her
-- spine within diagonal's 33-40 degrees, the head and the other arm on its head side, that arm and both thighs past
-- it; a blade's slant (gore.blade_slant) read right; a death rolled diagonal (odds of it alone) starts the split with
-- the diagonal's plane
local F = require("fake")
local E = require("eve")
local pawn = E.make(F)
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.death = { limb = 0, head = 0, torso = 0, split = 0, diagonal = 100, moreLimbs = 0 }
-- (parked: off in tune.lua, on for this test)
s.gore.diagonal = { enabled = true }
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=4 limb=0 seam=30000 vanished=30000 unsunk=0 reweighted=3786 stuck=0 far=0.0 sinks=100,85 new=2 sinkmoved=0 held=2 active=928/0 cyc=192/85/0"
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local gore = dofile(DIR .. "gore.lua")
gore.init({ tune = { gore = { diagonal = {} } }, try = function(fn, ...) local o, r = pcall(fn, ...); if o then return r end end,
  valid = function(x) return x ~= nil end, v3 = function(v) return string.format("%.0f %.0f %.0f", v.X, v.Y, v.Z) end })
local mesh = E.mesh
local axis = vec(0, 0, 1)
for _, side in ipairs({ "R", "L" }) do
  local at, n, deg = gore.diag_plane(mesh, side, false)
  check(at ~= nil, side .. ": a plane")
  if at then
    print(string.format("  %s: %.0f deg off her spine, normal %.2f %.2f %.2f", side, deg, n.X, n.Y, n.Z))
    check(deg > 30 and deg < 45, side .. ": slanting 30-45 deg off her spine")
    local function h(b) return dot(sub(E.bone(b), at), n) end
    local o = side == "R" and "L" or "R"
    check(h("Bip001-Head") > 0 and h("Bip001-" .. o .. "-UpperArm") > 0, side .. ": the head and the other arm on the head's side")
    check(h("Bip001-" .. side .. "-UpperArm") < 0 and h("Bip001-L-Thigh") < 0 and h("Bip001-R-Thigh") < 0, side .. ": that arm and both thighs past it")
    -- its own plane read back as a blade: the same slant and shoulder
    local d2, slab, s2 = gore.blade_slant(axis, gore.her_right(mesh, axis), n)
    check(d2 and math.abs(d2 - deg) < 1 and not slab and s2 == side, string.format("%s: as a blade, %.0f deg from over her %s shoulder", side, d2 or -1, tostring(s2)))
  end
end
local d, slab = gore.blade_slant(axis, gore.her_right(mesh, axis), vec(0, 0, 1))
check(d and d > 85 and not slab, "a level blade: across her (90 deg)")
d, slab = gore.blade_slant(axis, gore.her_right(mesh, axis), vec(1, 0, 0))
check(slab, "a blade facing her front: a slab, not a diagonal")

-- a death with the odds all diagonal
local d0 = #F.log_lines() + 1
E.s.hp = 0
E.die(true)
F.run(3, pawn)
check(F.find("rolled diagonal", d0) ~= nil, "the death rolled the diagonal")
local sp = F.find("split %(death%) at .*diagonal from over her", d0)
check(sp ~= nil, "the split made along the diagonal: " .. tostring(sp and sp:match("diagonal from over her %a+ shoulder, %d+ deg")))
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
