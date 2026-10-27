-- A level reload with her head cut off her alive (F9, tune.gore.bone the head): the cut is on her body and on her face
-- mesh, each a mesh asset of its own that the new Eve wears again. Both assets' collapsed helper bones must be put back
-- as the old Eve is dropped (gore.forget: sbslice "r<asset>" for every asset the new Eve wears that a cut of hers was
-- on), or the new Eve's face shows parts of it gone. (Only the body's were: the face's cut kept no asset)
local F = require("fake")
local E = require("eve")
local print = F.say
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local f = assert(io.open(DIR .. "settings.lua", "w"))
f:write([[
local s = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings.default.lua")
s.dev = true
s.gore.bone = "Bip001-Head"
return s
]])
f:close()
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
F.sbslice.f = "ok photo shield 1"
local BODY = F.obj("SK_CH_P_EVE_01", "SkeletalMesh")
local FACE = F.obj("SK_CH_P_EVE_01_Face", "SkeletalMesh")
-- her face: a mesh slot 1 of hers on her body's skeleton (its head bones), its own asset
local function dress(pawn)
  rawset(E.mesh, "SkeletalMesh", BODY)
  local face = F.obj("Face", "SkeletalMeshComponent", {
    SkeletalMesh = FACE,
    GetBoneIndex = function(_, b) return E.INDEX[b:ToString()] or -1 end,
    GetSocketLocation = function(_, b) return E.bone(b and b:ToString() or "") end,
    GetNumBones = function() return #E.BONE_OF + 1 end,
    GetBoneName = function(_, i) return F.fname(E.BONE_OF[i] or "None") end,
    IsVisible = function() return true end,
  })
  rawset(pawn, "MeshInfoList", { ForEach = function(_, cb)
    cb(1, { get = function() return { MeshSlot = 0, MeshComponent = E.mesh } end })
    cb(2, { get = function() return { MeshSlot = 1, MeshComponent = face } end })
  end })
  rawset(pawn, "K2_GetComponentsByClass", function() return { E.mesh, face } end)
  return face
end
local pawn = E.make(F)
dress(pawn)
local ok, err = pcall(dofile, DIR .. "main.lua")
if not ok then print("FAIL: main.lua didn't load: " .. tostring(err)); return end
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(16, pawn)

local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local function mark() return #F.log_lines() + 1 end
local function dump(from, pat)
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 240)) end end
end

local at = mark()
check(F.press("F9", ""), "F9 bound")
F.run(3, pawn)
check(F.find("cut Bip001%-Head", at) ~= nil, "F9: her head cut off alive")
if fails > 0 then dump(at) end

-- the level reloads: a new Eve in the same body and face
local c0 = #F.cmds
local old = pawn
pawn = E.make(F)
dress(pawn)
old.__dead = true
local r0 = mark()
F.run(3, pawn)
check(F.find("new Eve .* the level reloaded", r0) ~= nil, "the new Eve adopted")
local sent = {}
for i = c0 + 1, #F.cmds do sent[F.cmds[i].s] = true end
local wb, wf = string.format("r%x", BODY.__addr), string.format("r%x", FACE.__addr)
check(sent[wb] or sent.r, "her body's helper bones put back (" .. wb .. ")")
check(sent[wf] or sent.r, "her face's helper bones put back (" .. wf .. ")")
if fails > 0 then dump(r0, "reloaded") end
for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
