-- A real sword approaching the hair briefly must not leave its dropped copy tiny and frozen.
package.path = "./ue4ss/Mods/StellarBladeGore/Scripts/?.lua;" .. package.path
FName = function(x) return x end
local A = require('active')
A.init({ tune = { active = {} }, log = function() end, try = function(f) local ok, v = pcall(f); if ok then return v end end,
  valid = function(o) return o ~= nil and not o.dead end })
local function up(fn, name)
  for i = 1, 100 do local n, v = debug.getupvalue(fn, i); if not n then break end; if n == name then return v end end
  error('missing ' .. name)
end
local watch = up(A.tick, 'standins_watch')
local standins, dropped = up(watch, 'standins'), up(up(watch, 'standin_fly_start'), 'dropped')
local v = function(x,y,z) return {X=x,Y=y,Z=z} end
local dist = 80
local mesh = { GetSocketLocation = function() return v(0,0,0) end }
local real = { K2_GetComponentLocation = function() return v(dist,0,0) end, SetHiddenInGame = function(self, x) self.hidden=x end }
local copy = { GetAddress = function() return 10 end, K2_GetComponentToWorld = function() return {Scale3D=v(2,3,4)} end,
  SetWorldScale3D = function(self,x) self.scale=x end, K2_DestroyComponent = function(self) self.dead=true end }
local box = { K2_GetComponentLocation = function() return v(10,20,30) end,
  K2_SetWorldLocation = function(self,x) self.at=x end, SetSimulatePhysics = function(self,x) self.sim=x end,
  SetCollisionEnabled = function(self,x) self.collision=x end, K2_DestroyComponent = function(self) self.dead=true end }
local s = {copy=copy, real=real, mesh=mesh, hidden=true}
standins[1], dropped[1] = s, {comp=copy, box=box}
local fails=0
local function check(x,msg) print((x and 'ok   ' or 'FAIL ')..msg); if not x then fails=fails+1 end end
watch(0.1); dist=50; watch(1)
check(not s.fly and not copy.scale, 'passing within 60 cm does not start a false return')
dist=20; watch(0.3); watch(0.2)
check(s.fly and copy.scale.X < 2 and box.sim == false, 'stable hair return starts and shrinks the copy')
dist=65; watch(0.1)
check(not s.fly and copy.scale.X==2 and copy.scale.Y==3 and copy.scale.Z==4 and box.sim and box.collision==3 and box.at.X==10,
  'interrupted return restores original scale, position and physics')
dist=20; watch(0.3); watch(0.6)
check(copy.dead and box.dead and real.hidden==false and #dropped==0, 'completed return shows the real sword and removes the copy')
-- Snap-to-target can replace scale while restoring a dropped or gripped sword.
local back = up(A.stop, 'weapons_back')
local gripBack = up(A.stop, 'grip_back')
local gripped = up(gripBack, 'gripped')
local parent = {}
local weapon = { scale=v(2,3,4), loc=v(1,2,3) }
function weapon:K2_AttachToComponent() self.scale=v(1,1,1) end
function weapon:K2_SetRelativeLocationAndRotation(loc, rot) self.loc=loc; self.rot=rot end
function weapon:SetRelativeScale3D(scale) self.scale=scale end
local saved={comp=weapon, parent=parent, loc=v(1,2,3), rot={Pitch=0,Yaw=0,Roll=0}, scale=v(2,3,4)}
for _=1,4 do
  dropped[1]=saved
  back()
  check(weapon.scale.X==2 and weapon.scale.Y==3 and weapon.scale.Z==4 and weapon.loc.Z==3, 'recovery restores the full sword transform')
end
gripped[1]=saved
gripBack()
check(weapon.scale.X==2 and weapon.scale.Y==3 and weapon.scale.Z==4, 'grip recovery restores sword scale')
print(fails==0 and 'PASS' or 'FAIL')
