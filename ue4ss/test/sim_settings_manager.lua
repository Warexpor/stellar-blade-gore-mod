-- Settings file creation, layered overrides, reload notifications and menu-reset baseline.
local module = dofile("ue4ss/Mods/StellarBladeGore/Scripts/settings_manager.lua")
local paths = { tune="fixture-tune.lua", settings="fixture-settings.lua", default="fixture-default.lua", menu="fixture-menu.lua" }
local function put(path, content) local f=assert(io.open(path,"w")); f:write(content); f:close() end
local function read(path) local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s end
put(paths.tune, "return { dev=false, gore={ volume=1, blood=true, channels={3,4} } }\n")
local defaults="return { gore={ volume=2, blood=false } }\n"
put(paths.default, defaults)
put(paths.menu, 'return { ["gore.volume"]=3, ["gore.channels.2"]=9 }\n')
local reloads, redos, current = 0, 0, nil
local ctx = { enemies={reload=function() reloads=reloads+1 end}, tables={redo_dead=function() redos=redos+1 end} }
local logs={}
local load, base = module(ctx, function(s) logs[#logs+1]=s end, function(t) current=t end,
  paths.tune, paths.settings, paths.default, paths.menu)
local fails=0
local function check(ok,msg) print((ok and "ok   " or "FAIL ")..msg); if not ok then fails=fails+1 end end
load()
check(read(paths.settings)==defaults, "first load creates player settings from defaults")
check(current.gore.volume==3 and current.gore.blood==false and current.gore.channels[1]==3 and current.gore.channels[2]==9,
  "menu overrides player settings over base tuning, including numeric paths")
local initial=base()
check(initial.gore.volume==2 and initial.gore.channels[2]==4, "menu reset baseline excludes menu overrides")
local custom="return { gore={ volume=5, blood=true } }\n"
put(paths.settings, custom)
put(paths.menu, 'return { ["gore.channels.2"]=6 }\n')
load()
check(read(paths.settings)==custom and current.gore.volume==5 and current.gore.channels[2]==6,
  "reload preserves the player file and reads updated settings")
check(ctx.tune==current and reloads==2 and redos==2, "reload publishes settings and notifies dependent modules")
print(fails==0 and "PASS" or "FAIL")
