local install=dofile('ue4ss/Mods/StellarBladeGore/Scripts/outfit_animation.lua')
local M, scans, reads = {}, 0, 0
local function try(fn) local ok,v=pcall(fn); if ok then return v end end
local function valid(o)
  if o and o.freed then error('read freed object') end
  return o~=nil
end
install(M,function() return try,valid end)
local function fname(s) return {ToString=function() return s end} end
local function class(node)
  return {GetAddress=function() return 0x123 end, ForEachProperty=function(_,fn)
    scans=scans+1; fn({GetStruct=function() return {GetFName=function() return fname('AnimNode_KawaiiPhysics') end} end,
      GetFName=function() return fname(node) end})
  end, GetSuperStruct=function() return nil end}
end
local function mesh(node, alpha)
  local instance={[node]={Alpha=alpha}, GetAddress=function() return 0x456 end, GetClass=function() return class(node) end}
  local m={instance=instance,disabled=false,GetPostProcessInstance=function(self) return self.instance end}
  function m:SetDisablePostProcessBlueprint(on) reads=reads+1; self.disabled=on end
  return m
end
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
local old=mesh('old',0.25)
check(M.kawaii(old,false)==1 and old.instance.old.Alpha==0, 'ragdoll disables outfit physics')
M.kawaii(old,false)
check(M.kawaii(old,true)==1 and old.instance.old.Alpha==0.25, 'repeated disable still restores original alpha')
M.kawaii(old,false); M.rig(old,false)
check(old.disabled and #M.rigoff==1, 'split records the disabled rig')
old.freed=true
M.outfit_forget()
local ok=pcall(M.rig_back)
check(ok and #M.rigoff==0 and reads==1, 'world change drops old rig without probing freed mesh')
local fresh=mesh('new',0.6)
check(M.kawaii(fresh,false)==1 and fresh.instance.new.Alpha==0 and scans==2, 'reused class address is scanned for the new outfit')
check(M.kawaii(fresh,true)==1 and fresh.instance.new.Alpha==0.6, 'reused instance address restores new original alpha')
M.rig(fresh,false); M.rig_back()
check(not fresh.disabled and #M.rigoff==0, 'ordinary recovery re-enables the new rig')
-- Exercise the production world-reset entry point, not only the extracted helper.
local G=dofile('ue4ss/Mods/StellarBladeGore/Scripts/gore.lua')
G.init({tune={gore={}},try=try,valid=valid,log=function() end})
G.rigoff={old}; G.kawaiiWas={stale=0.2}; G.kawaiiNodes={stale={'old'}}
local forgot=pcall(G.forget,nil)
check(forgot and #G.rigoff==0 and next(G.kawaiiWas)==nil and next(G.kawaiiNodes)==nil,
  'production world cleanup discards old outfit references and caches')
check(pcall(G.rig_back), 'post-reload recovery does not touch the old mesh')
print(fails==0 and 'PASS' or 'FAIL')
