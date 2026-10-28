-- P in a death (Photo Mode in a Death): it holds the death as Shift+F4 does, so the death screen and getting up don't
-- come on over photo mode. Kept after photo mode closed, the death screen never came back and she couldn't respawn
-- (Nexus report, 0.4.6). The hold P took goes as photo mode closes (or at once when it doesn't open); one made with
-- Shift+F4 stays till Shift+F4 again
local F = require("fake")
local E = require("eve")
local R = require("rag")
local pawn = E.make(F)
local print = F.say
F.sbslice.c = "ok verts=62882 mode=0 limb=7912 seam=138 vanished=0 unsunk=0 reweighted=3786 stuck=0 watched=114 far=23.5 sinks=100,85 new=2 sinkmoved=2 held=2 active=928/0 cyc=192/85/0 pieces=5"
-- photo mode as sbslice.dll reads it: f2 enters it, f3 its state (84 not 0 while it is on), the rest answered ok
local photo, opens = false, true
F.sbslice.f = function(s)
  if s:sub(1, 2) == "f2" then
    if not opens then return "err photo mode busy" end
    photo = true
    return "ok photo entered 1"
  end
  if s:sub(1, 2) == "f3" then return "ok photo state: mgr 38=1 84=" .. (photo and "1" or "0") .. " 48=0" end
  return "ok photo shield 1"
end
R.install(F, E)
F.world = R.step
local ok, err = pcall(dofile, "ue4ss/Mods/StellarBladeGore/Scripts/main.lua")
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
  for i, x in ipairs(F.log_lines()) do if i >= from and (not pat or x:find(pat)) then print("  | " .. x:sub(1, 230)) end end
end
local function hidden() local w = E.deadScreen and E.deadScreen.__w; return w and (w.vis == 1 or w.vis == 2) end
local function next_life() E.respawn(); F.run(20, pawn) end

-- 1: P 2 s into a death, photo mode closed 4 s later: the death screen up once the death's clock (stopped while it was
-- held) reaches 10 s
local at = mark()
E.die(true)
F.run(2, pawn)
check(F.press("P", ""), "P bound")
F.run(1, pawn)
check(F.find("in the held death, opening photo mode: ok photo entered 1", at) ~= nil, "1: P opened photo mode")
F.run(3, pawn)
check(hidden(), "1: the death screen hidden while photo mode is on")
photo = false
F.run(1.5, pawn)
check(F.find("photo mode closed: the death P held let go", at) ~= nil, "1: photo mode closed: the hold P took let go")
F.run(9, pawn)
check(not hidden(), "1: the death screen up again (" .. tostring(E.deadScreen and E.deadScreen.__w.vis) .. ")")
if fails > 0 then dump(at) end
next_life()

-- 2: Shift+F4 held the death first (its first press brings the death screen up early, the second holds), then P: the
-- hold is the player's, kept after photo mode closes till Shift+F4 again
at = mark()
E.die(true)
F.run(2, pawn)
check(F.press("F4", "SHIFT"), "Shift+F4 bound")
F.run(0.5, pawn)
F.press("F4", "SHIFT")
F.run(0.5, pawn)
check(F.find("Shift%+F4: death held", at) ~= nil, "2: Shift+F4 twice: the death held")
F.press("P", "")
F.run(3, pawn)
photo = false
F.run(9, pawn)
check(not F.find("the death P held let go", at), "2: Shift+F4's hold not let go as photo mode closed")
check(hidden(), "2: the death screen still hidden 14 s in")
F.press("F4", "SHIFT")
F.run(1, pawn)
check(not hidden(), "2: Shift+F4 again: the death screen up")
next_life()

-- 3: P with photo mode not opening: the hold it took let go at once
at = mark()
opens = false
E.die(true)
F.run(2, pawn)
F.press("P", "")
F.run(0.5, pawn)
check(F.find("photo mode didn't open: the death P held let go", at) ~= nil, "3: photo mode didn't open: the hold let go")
F.run(9, pawn)
check(not hidden(), "3: the death screen up at 11 s")
opens = true
next_life()

-- 4: her hair made to ignore her bodies (an arm cut off her alive: her mesh a PhysicsBody) and photo mode's switch
-- back setting it blocking them as it closes: put back as before photo mode (playtest: her hair shoved her bodies
-- apart, her whole body shifting and stretching after it closed)
local SMC = "/Script/Engine.SkeletalMeshComponent"
local smcPath, meshIsa = rawget(F.objects[SMC], "__path"), rawget(E.mesh, "__isa")
rawset(F.objects[SMC], "__path", SMC)
rawset(E.mesh, "__isa", { [SMC] = true })
local hair = F.obj("SBHair", "SkeletalMeshComponent", {
  __isa = { [SMC] = true }, en = 3, resp = {},
  GetCollisionEnabled = function(self) return self.en end,
  SetCollisionEnabled = function(self, v) self.en = v end,
  GetCollisionResponseToChannel = function(self, ch) return self.resp[ch] or 2 end,
  SetCollisionResponseToChannel = function(self, ch, v) self.resp[ch] = v end,
})
hair.resp[5] = 0
local function kids(list) return { ForEach = function(_, fn) for i, c in ipairs(list) do fn(i, { get = function() return c end }) end end } end
rawset(pawn, "RootComponent", F.obj("Root4", "CapsuleComponent", { AttachChildren = kids({ E.mesh, hair }) }))
at = mark()
E.die(true)
F.run(2, pawn)
F.press("P", "")
F.run(1, pawn)
-- (photo mode's own switch: query only while on, set blocking everything as it closes)
hair.en = 1
F.run(2, pawn)
hair.en, hair.resp[5] = 3, 2
photo = false
F.run(1.5, pawn)
check(F.find("her other meshes' collision as before it: put back on SBHair ch5 2>0", at) ~= nil, "4: her hair's response to her bodies put back")
check(hair.resp[5] == 0 and hair.en == 3, "4: her hair ignores PhysicsBody again (" .. tostring(hair.resp[5]) .. ")")
if fails > 0 then dump(at, "photo") end
rawset(pawn, "RootComponent", nil)
rawset(F.objects[SMC], "__path", smcPath)
rawset(E.mesh, "__isa", meshIsa)
next_life()

for _, e in ipairs(F.errors) do print("hook error: " .. e) end
local te = F.find("tick error")
if te then print("tick error in the log: " .. te) end
check(not te and #F.errors == 0, "no errors")
print(fails == 0 and "PASS" or "FAIL")
