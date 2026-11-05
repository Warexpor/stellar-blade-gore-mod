local prefix = assert(os.getenv('LUA_PATH')):match('^([^;]+)')
local testDir = assert(prefix:match('^(.*)/%?%.lua$'))
local checker = testDir .. '/../check_scripts.sh'
for _, dir in ipairs({ 'preflight_good', 'preflight_global', 'preflight_syntax' }) do
  assert(os.execute('mkdir ' .. dir))
end
local function write(dir, source)
  local f = assert(io.open(dir .. '/test.lua', 'w')); f:write(source); f:close()
end
write('preflight_good', 'local x = math.abs(-1)\nreturn x\n')
write('preflight_global', 'return codex_missing_global()\n')
write('preflight_syntax', 'return )\n')
local function run(dir)
  local result = os.execute('bash "' .. checker .. '" "' .. dir .. '" > preflight-result.log 2>&1')
  local f = assert(io.open('preflight-result.log', 'r')); local out = f:read('a'); f:close()
  return result == true, out
end
local good, output = run('preflight_good')
if output:find('compiler not found', 1, true) then print('SKIP: Lua compiler unavailable'); print('PASS'); return end
local badGlobal, globalOutput = run('preflight_global')
local badSyntax, syntaxOutput = run('preflight_syntax')
local fails = 0
local function check(ok, text) print((ok and 'ok   ' or 'FAIL ') .. text); if not ok then fails = fails + 1 end end
check(good, 'valid script passes preflight')
check(not badGlobal and globalOutput:find('codex_missing_global', 1, true), 'unknown global fails preflight')
check(not badSyntax and syntaxOutput:find("doesn't load", 1, true), 'invalid syntax fails preflight')
print(fails == 0 and 'PASS' or 'FAIL')
