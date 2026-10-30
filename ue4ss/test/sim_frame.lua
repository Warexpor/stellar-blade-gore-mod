-- The stumps' shared frame (gore.lua M.pair, M.tachy_frame): Tachy's core stands in it, so its x and y are where her
-- bone goes on each disc. A left and a right cut, mirror images of each other across her midline (x = 0, her left
-- +X, her back -Y), with the DLL's rim axes (ob.x) pointing anywhere: the right's frame has to be the left's mirror
-- image (bone at the mirrored place, handedness flipped), and each cut piece's frame its stump's (handedness flipped
-- again). Thighs (cut level) and arms (hanging, cut on a slant, and raised to the side, cut along her side)
local F = require("fake")
local M = dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function n(a) local l = math.sqrt(a.X ^ 2 + a.Y ^ 2 + a.Z ^ 2); return v(a.X / l, a.Y / l, a.Z / l) end
local function mir(a) return v(-a.X, a.Y, a.Z) end
local function near(a, b) return math.abs(a.X - b.X) + math.abs(a.Y - b.Y) + math.abs(a.Z - b.Z) < 1e-6 end
local BACK = v(0, -1, 0.05) -- her back, as back_on gives it (off the plane: M.pair squares it)
-- the frame an opening gets, as M.core and tachy_lid read it
local function frame(o) local z = n(o.z); return { M.tachy_frame(o, z) } end
local function case(what, boneL, zL, xL, xR)
  local bL, lL = { z = zL, x = xL }, { z = v(-zL.X, -zL.Y, -zL.Z), x = xL }
  local zR = mir(zL)
  local bR, lR = { z = zR, x = xR }, { z = v(-zR.X, -zR.Y, -zR.Z), x = xR }
  local boneR = boneL:gsub("%-L%-", "-R-")
  M.pair(bL, lL, BACK, M.side_of(boneL))
  M.pair(bR, lR, mir(BACK), M.side_of(boneR))
  local fbL, flL, fbR, flR = frame(bL), frame(lL), frame(bR), frame(lR)
  check(near(fbR[1], mir(fbL[1])) and near(fbR[2], mir(fbL[2])), what .. ": the right stump's frame is the left's mirror image")
  check(fbR[3] ~= fbL[3], what .. ": and its handedness flipped (mirrored " .. tostring(fbL[3]) .. " / " .. tostring(fbR[3]) .. ")")
  check(near(flR[1], mir(flL[1])) and near(flR[2], mir(flL[2])) and flR[3] ~= flL[3], what .. ": the cut pieces' frames likewise")
  check(near(flL[1], fbL[1]) and flL[3] ~= fbL[3] and flR[3] ~= fbR[3], what .. ": each piece mirrors its own stump")
  local bk = n(v(BACK.X, BACK.Y, BACK.Z))
  check(fbL[1].X * bk.X + fbL[1].Y * bk.Y + fbL[1].Z * bk.Z > 0.5, what .. ": x is her back, not the rim's axis")
end
case("thighs", "Bip001-L-Thigh", v(0.1, 0, -1), v(1, 0.3, 0), v(-0.2, 1, 0))
case("upper arms", "Bip001-L-UpperArm", n(v(0.3, 0.2, -1)), v(0, 1, 0.2), v(0.7, -0.7, 0.1))
case("forearms", "Bip001-L-Forearm", n(v(0.4, -0.5, -1)), v(-1, 0, 0.4), v(0.1, 0.1, 1))
case("raised arms", "Bip001-L-UpperArm", v(1, 0, 0.1), v(0, 0, 1), v(0, 1, 0))
-- her back is read off a spine bone the limb stays on: after a waist cut Spine1 rides her flying upper half, and a
-- thigh cut then took its back from that (its bone and tubes no longer the other thigh's mirror image, playtest)
for _, b in ipairs({ "Bip001-L-Thigh", "Bip001-R-Thigh", "Bip001-L-Calf", "Bip001-R-Calf" }) do
  check(M.back_bone(b) == "Bip001-Spine", b .. ": back off Bip001-Spine, under the waist cut")
end
check(M.back_bone("Bip001-L-UpperArm") == "Bip001-Spine1" and M.back_bone("Bip001-R-Forearm") == "Bip001-Spine1", "arms: back off Spine1, which they go with")
check(M.back_bone("Bip001-Head") == "Bip001-Head" and M.back_bone("Bip001-Spine1") == "Bip001-Spine1", "spine cuts: their own bone")
-- no back (back_on found nothing): the rim's axis still makes a frame
local o = { z = v(0, 0, 1), x = v(1, 0, 0) }
M.pair(o, nil, nil, 1)
check(o.tx and near(o.tx, v(1, 0, 0)), "no back: the rim's axis")
print(fails == 0 and "PASS" or "FAIL")
