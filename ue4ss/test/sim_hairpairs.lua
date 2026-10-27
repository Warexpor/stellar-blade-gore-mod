-- physfix.alive_pairs: the pairs her vanilla physics asset lets collide that aren't two main bodies (her ponytail's
-- against her head, back and arms) are read from sbslice.dll ("L") before the table is filled, and kept colliding
-- while she lives ("t" with them); two main bodies colliding in the vanilla asset (her pelvis and arms) are not
local F = require("fake")
local print = F.say
local fails = 0
local function check(c, what)
  print((c and "ok   " or "FAIL ") .. what)
  if not c then fails = fails + 1 end
end
local DIR = "ue4ss/Mods/StellarBladeGore/Scripts/"
local physfix = dofile(DIR .. "physfix.lua")
local sent = {}
local BONES = { "Bip001-Pelvis", "Bip001-Spine2", "Bip001-Head", "Bip001-L-UpperArm", "Ab-TL-HairB01", "Ab-TL-HairB02", "Ab-L-Breast" }
-- the vanilla table's colliding pairs: pelvis/arm (main, main), spine2/hair01, head/hair02, arm/hair02
local L = "ok colliding 4 0,3 1,4 2,5 3,5"
physfix.init({
  try = function(f) local ok, r = pcall(f); if ok then return r end end,
  valid = function(o) return o ~= nil end,
  gore = { command = function(s)
    sent[#sent + 1] = s
    if s:sub(1, 1) == "L" then return L end
    if s:sub(1, 1) == "t" then return "ok table +424 1 -> 17 colliding " .. select(2, s:gsub(",", ",")) end
    return "err"
  end },
})
local bodies = {}
for _, b in ipairs(BONES) do bodies[#bodies + 1] = { BoneName = { ToString = function() return b end } } end
local pa = {
  GetAddress = function() return 0x5000 end,
  SkeletalBodySetups = { ForEach = function(_, cb) for i, b in ipairs(bodies) do cb(i, { get = function() return b end }) end end },
}
local keep, said = physfix.alive_pairs(pa)
local names = {}
for _, p in ipairs(keep) do names[#names + 1] = p[1] .. "/" .. p[2] end
table.sort(names)
check(#keep == 3, "three pairs kept: " .. table.concat(names, " ") .. said)
check(table.concat(names, " ") == "Bip001-Head/Ab-TL-HairB02 Bip001-L-UpperArm/Ab-TL-HairB02 Bip001-Spine2/Ab-TL-HairB01",
  "her hair's pairs, not her pelvis and arm")
local r = physfix.alive_table(pa)
local t = sent[#sent]
check(t:sub(1, 1) == "t" and t:find("^t5000,7,") ~= nil, "the table written with them: " .. t)
for _, p in ipairs({ "1,4", "2,5", "3,5" }) do check(t:find("," .. p, 1, true) ~= nil, "pair " .. p .. " kept colliding") end
check(not t:find(",0,3", 1, true), "pelvis/arm not kept")
local nL = 0
for _, s in ipairs(sent) do if s:sub(1, 1) == "L" then nL = nL + 1 end end
check(nL == 1, "the vanilla pairs read once (" .. nL .. ")")
print(fails == 0 and "PASS" or "FAIL")
