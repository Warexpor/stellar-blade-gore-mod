local install=dofile('ue4ss/Mods/StellarBladeGore/Scripts/hit_classification.lua')
local sw, calls = {}, 0
local tune={gore={enabled=true,smash={enabled=true,sharp={'sword'},blunt={'hammer'}}}}
local swing={who='enemy',weapons={{name='hammer'}}}
local gore={smash=function() calls=calls+1; return true,'queued' end}
local function len(v) return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
install(sw,function() return tune end,function() return swing end,function() return gore end,len,function() end)
local fails=0
local function check(ok,msg) print((ok and 'ok   ' or 'FAIL ')..msg); if not ok then fails=fails+1 end end
check(sw.blunt_of({attacker='enemy'})==true, 'initial tracked hammer is blunt')
swing={who='enemy',weapons={{name='sword'}}}
check(sw.blunt_of({attacker='enemy'})==false, 'replacement swing is read on the next classification')
tune={gore={enabled=true,smash={enabled=true,sharp={'hammer'},blunt={'sword'}}}}
check(sw.blunt_of({attacker='enemy'})==true, 'replacement settings are read on the next classification')
local first, pending=sw.smash_kill({}, {}, {attacker='enemy'}, 'death')
check(first and pending=='queued' and calls==1, 'smash dispatch uses current classifier and returns deferred state')
gore={smash=function() calls=calls+1; return false end}
check(sw.smash_kill({}, {}, {attacker='enemy'}, 'death')==false and calls==2, 'smash dispatch reads the replacement gore service')
tune={gore={enabled=false,smash={enabled=true,blunt={'sword'}}}}
check(not sw.smash_kill({}, {}, {attacker='enemy'}, 'death') and calls==2, 'replacement disabled settings block dispatch')
tune={gore={enabled=true,smash={enabled=true,sharp={'saw'},blunt={},species={['CH_M_NA_13']='sawshark'}}}}
swing={who='CH_M_NA_13_Blueprint_C_1',weapons={}}
check(sw.blunt_of({attacker='CH_M_NA_13_Blueprint_C_1',wbone='Bip001-R-Hand'})==false, 'a clawed species swipes cut, never smashed')
check(sw.blunt_of({attacker='CH_M_NA_16_Blueprint_C_1',wbone='Bip001-R-Hand'})==true, 'other bare hands still smash')
print(fails==0 and 'PASS' or 'FAIL')
