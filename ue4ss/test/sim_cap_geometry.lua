-- Rounded native opening normals can be slightly longer than one. A point close to the normal must not produce NaNs.
local F = require("fake")
local print = F.say
local function v(x,y,z) return { X=x, Y=y, Z=z } end
local function add(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
local function sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local function scale(a,k) return v(a.X*k,a.Y*k,a.Z*k) end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function norm(a) local d=math.sqrt(dot(a,a)); if d > 1e-9 then return scale(a,1/d) end end
local function cross(a,b) return v(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
local make = dofile("ue4ss/Mods/StellarBladeGore/Scripts/cap_geometry.lua")(v,add,scale,sub,dot,norm,cross)
local z=v(0.408,0.408,0.817)
local _, verts, tris = make({z=z,x=v(1,0,0),p={scale(z,1),scale(z,-1),scale(z,2),scale(z,-2)}},1)
local finite = #verts == 18 and #tris == 72
for _, p in ipairs(verts) do for _, n in ipairs({p.X,p.Y,p.Z}) do if n ~= n or math.abs(n) == math.huge then finite=false end end end
print((finite and "ok   " or "FAIL ") .. "rounded opening normal produces finite cap geometry")
print(finite and "PASS" or "FAIL")
