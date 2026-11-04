-- Split-lid follow cadence: a settled split's lids must not pay full bone/transform reads every tick.
-- After 30 still ticks the follow checks every fourth tick; any motion resumes full-rate updates at once.
local T = require("smash_world").boot('s.gore.blood=false')
local F, E, G = T.F, T.E, T.G
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local fails = 0
local function check(c, s) F.say((c and "ok   " or "FAIL ") .. s); if not c then fails = fails + 1 end end
local function find(fn, wanted, seen)
  seen = seen or {}; if type(fn) ~= "function" or seen[fn] then return end; seen[fn] = true
  for i = 1, math.huge do
    local name, v = debug.getupvalue(fn, i); if not name then break end
    if name == wanted then return v, fn, i end
    if name ~= "_ENV" and type(v) == "function" then
      local a, b, c = find(v, wanted, seen); if b then return a, b, c end
    end
  end
end
local split_caps = assert(find(G.pump_once, "split_caps"))
local skin = assert(find(split_caps, "skin_lid"))
local lids_tick = assert(find(G.tick, "lids_tick"))
local skinned = assert(find(skin, "skinned"))
-- A lid riding two spine bones, like sim_split's rigid-motion case.
local turn, shift, bend, uploads = 0, vec(0, 0, 0), 0, 0
local function world(x, y, z)
  local c, s = math.cos(turn), math.sin(turn)
  return vec(shift.X + x * c - y * s, shift.Y + x * s + y * c, shift.Z + z)
end
local function rotation() return { X = 0, Y = 0, Z = math.sin(turn / 2), W = math.cos(turn / 2) } end
local body = F.obj("StillHalf", "SkeletalMeshComponent")
body.GetSocketTransform = function(_, b)
  local z = tostring(b) == "top" and 10 or 0
  return { Translation = world(z > 0 and bend or 0, 0, z), Rotation = rotation() }
end
local reads = 0
local actor = F.obj("StillLid", "StaticMeshActor")
local realT = function() return { Translation = shift, Rotation = rotation() } end
rawset(actor, "GetTransform", function() reads = reads + 1; return realT() end)
local pmc = F.obj("StillPMC", "ProceduralMeshComponent")
pmc.UpdateMeshSection_LinearColor = function(self, _, verts, normals) uploads = uploads + 1; self.verts, self.normals = verts, normals end
local pc = { wv = { vec(-1, 0, 2), vec(1, 0, 2), vec(1, 0, 8), vec(-1, 0, 8) }, wn = {} }
for k = 1, 4 do pc.wv[k + 4] = pc.wv[k]; pc.wn[k] = vec(0, 1, 0); pc.wn[k + 4] = vec(0, -1, 0) end
check(skin(body, actor, pmc, pc, { "bottom", "top" }), "lid binds to two spine bones")
lids_tick()
check(uploads == 1, "first follow binds the lid")
local still = 0
for _ = 1, 60 do lids_tick(); still = still + 1 end
check(uploads == 1, "sixty still ticks upload nothing more")
-- Call 1 ran, calls 2-31 build the 30 still ticks, then every fourth tick checks: 30 + 8 reads at most.
check(reads <= 44, string.format("still follow skips transform reads (%d reads over %d ticks)", reads, still + 1))
check(reads >= 34, string.format("still follow keeps checking (%d reads over %d ticks)", reads, still + 1))
check(#skinned >= 1, "the still lid is kept, not dropped")
local n = 0
for _, s in ipairs(skinned) do n = math.max(n, s.n or 0) end
check(n >= 61, "the follow window still counts skipped ticks")
local secondUploads = 0
local secondPmc = F.obj("NewPMC", "ProceduralMeshComponent")
secondPmc.UpdateMeshSection_LinearColor = function() secondUploads = secondUploads + 1 end
check(skin(body, actor, secondPmc, pc, { "bottom", "top" }), "a second lid binds while the first is idle")
lids_tick()
check(secondUploads == 1, "a newly bound lid updates on its first tick")
bend = 1
local before = uploads
for _ = 1, 4 do lids_tick() end
check(uploads > before, "a bend after the quiet spell uploads within four ticks")
for _, e in ipairs(F.errors) do F.say("hook error: " .. e) end
check(#F.errors == 0, "no engine simulation errors")
F.say(fails == 0 and "PASS" or "FAIL")
