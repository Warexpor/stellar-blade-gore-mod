-- Validate the extracted Tachy core metadata using the shipped mesh, without testing generated pictures.
local M=dofile("ue4ss/Mods/StellarBladeGore/Scripts/gore.lua")
local t=dofile("ue4ss/Mods/StellarBladeGore/Scripts/tachy_core.lua")
local tune={gore={boneSilver=true}}
M.init({tune=tune})
local fails=0
local function check(ok,msg) print((ok and "ok   " or "FAIL ")..msg); if not ok then fails=fails+1 end end
local bone=M.tachy_bone(t)
local included,excluded
for i=0,#t.verts//11-1 do if bone.verts[i] then included=included or i else excluded=excluded or i end end
check(#bone.tris>0 and #bone.tris<#t.tris and included~=nil and excluded~=nil,
  "bone selection retains a subset of the real core geometry")
check(M.tachy_bone(t)==bone, "bone metadata is reused for repeated calls")
local remap=M.bone_uv(t,included,0.8,0.5)
local other=M.bone_uv(t,excluded,0.8,0.5)
check((remap.X~=0.8 or remap.Y~=0.5) and other.X==0.8 and other.Y==0.5,
  "silver UV remapping applies only to selected bone vertices")
tune.gore.boneSilver=false
local disabled=M.bone_uv(t,included,0.8,0.5)
check(disabled.X==0.8 and disabled.Y==0.5, "boneSilver off preserves original UVs")
print(fails==0 and "PASS" or "FAIL")
