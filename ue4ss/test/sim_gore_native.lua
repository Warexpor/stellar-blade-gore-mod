local create = dofile('ue4ss/Mods/StellarBladeGore/Scripts/gore_native.lua')
local root = 'ue4ss/Mods/StellarBladeGore/'
local result, req, okfile = root .. 'sbslice.cut', root .. 'sbslice.req', root .. 'sbslice.ok'
local native, M, ctx = {state='ready', waited=0}, {copies={dirty={}}}, {}
local clears, calls, response, fail = {}, {}, 'ok', false
FName = function(n) return n end
local cdo = {}
function cdo:SBRewardGroupDropFormationPathLocation(_, x, y, z, cmd)
  if fail then error('injected native error') end
  calls[#calls+1] = cmd
  if cmd:sub(1,1) ~= 'H' and cmd:sub(1,1) ~= 'F' then
    local f = assert(io.open(result, 'w')); f:write(response); f:close()
  end
end
M.copies_clear = function(addr) clears[#clears+1] = addr end
local function try(fn) local ok, v = pcall(fn); if ok then return v end end
local function valid(o) return o ~= nil end
local cuts = {}
local logs = {}
local function read(path) local f=io.open(path,'r'); if not f then return nil end; local s=f:read('a'); f:close(); return s end
local command, tick = create(M,native,function() return {} end,function() return cdo end,
  function(x,y,z) return {X=x,Y=y,Z=z} end,function() end,function(s) logs[#logs+1]=s end,
  read,'cheat',function() return ctx end,function() return try,valid end,function() return cuts end)
local fails = 0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
check(command('c123,0') == 'ok' and M.copies.dirty[0x123], 'successful cut marks its copies dirty')
check(command('x123,0') == 'ok' and clears[1] == 0x123, 'successful reset clears copies')
response = 'err failed'
check(command('c456,0') == 'err failed' and not M.copies.dirty[0x456], 'failed cut does not mark copies dirty')
M.fire('Ftest')
check(calls[#calls]=='Ftest', 'fire-and-forget dispatches without a reply')
fail = true
M.fire('Ffail')
check(native.hold_cdo == nil, 'failed fire discards cached cheat object')
fail = false
local mesh = { GetAddress = function() return 0x123 end }
cuts = { { mesh=mesh, addr=0x123 } }
M.hold_seams()
check(calls[#calls]=='H123', 'seam hold sends current cut addresses')
cuts = {}
local before = #calls
M.hold_seams()
check(#calls == before, 'seam hold skips empty cut lists')
native.state, native.waited = 'init', 0
StaticFindObject = function() return { GetAddress = function() return 0x123 end } end
tick()
check(native.state == 'waiting' and read(req) == '123', 'handshake writes the native request')
local f = assert(io.open(okfile,'w')); f:write('cpu copy LOD0 on'); f:close()
response = 'ok'
tick()
check(native.state == 'ready' and ctx.cpu_forced == true, 'handshake accepts native readiness and CPU-copy status')
os.remove(result); os.remove(req); os.remove(okfile)
native.state, native.waited, native.late = 'init', 0, nil
tick()
for _ = 1, 151 do tick() end
check(native.state == 'failed' and native.late, 'timeout reports failure but keeps the pending request')
local late = assert(io.open(okfile, 'w')); late:write('cpu copy LOD0 on'); late:close()
native.lateCheck = 0
tick()
check(native.state == 'ready' and not native.late, 'late helper response recovers without restarting')
os.remove(result); os.remove(req); os.remove(okfile)
native.state, native.waited, native.late = 'init', 0, nil
tick()
for _ = 1, 151 do tick() end
local errfile = root .. 'sbslice.err'
local refused = assert(io.open(errfile, 'w')); refused:write('unsupported build'); refused:close()
native.lateCheck = 0
tick()
check(native.state == 'failed' and not native.late, 'late refusal stays failed without retrying a refused hook')
os.remove(result); os.remove(req); os.remove(okfile); os.remove(errfile)
print(fails==0 and 'PASS' or 'FAIL')
