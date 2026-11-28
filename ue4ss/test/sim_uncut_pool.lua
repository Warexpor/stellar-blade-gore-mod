-- Start with cuts off, exercise F3 through native startup and an intact death through recovery.
local F, E = require("fake"), require("eve")
local pawn = E.make(F)
local dir = "ue4ss/Mods/StellarBladeGore/Scripts/"
local fails = 0
local function check(ok, what)
  F.say((ok and "ok   " or "FAIL ") .. what)
  if not ok then fails = fails + 1 end
end

local settings = assert(io.open(dir .. "settings.lua", "w"))
settings:write("return { gore = { enabled = false, blood = false, pool = false }, deathMoves = false }")
settings:close()
local log = assert(io.open("ue4ss/UE4SS.log", "w"))
log:write("Failed to find FText::FText(FString&&)\n")
log:close()

local widget, failAttach, paused, inputHeld
local canTickPaused = false
pawn.PrimaryActorTick = { bTickEvenWhenPaused = false }
pawn.SetTickableWhenPaused = function(self, on)
  if canTickPaused then self.PrimaryActorTick.bTickEvenWhenPaused = on end
end
pawn.DisableInput = function() inputHeld = true end
pawn.EnableInput = function() inputHeld = false end
local decals = {}
F.objects["/Script/Engine.Default__GameplayStatics"] = F.obj("GameplayStatics", "GameplayStatics", {
  GetPlayerController = function() return pawn.Controller end,
  IsGamePaused = function() return paused == true end,
  SetGamePaused = function(_, _, on) paused = on; return true end,
  SpawnDecalAtLocation = function(_, _, _, _, at)
    local d = F.obj("FloorBlood", "DecalComponent", {
      at = at,
      SetWorldScale3D = function(self, scale) self.radius = scale.Y end,
      K2_DestroyComponent = function(self) self.__dead = true end,
    })
    decals[#decals + 1] = d
    return d
  end,
})
F.objects["/Script/Engine.Default__KismetMathLibrary"] = F.obj("Math", "KismetMathLibrary")
F.objects["/Script/Engine.Default__KismetSystemLibrary"] = F.obj("Trace", "KismetSystemLibrary", {
  LineTraceSingle = function(_, _, from, to, _, _, _, _, hit)
    if from.Z == to.Z or (from.Z > 0) == (to.Z > 0) then return false end
    hit.ImpactPoint = { X = from.X, Y = from.Y, Z = 0 }
    hit.ImpactNormal = { X = 0, Y = 0, Z = 1 }
    return true
  end,
})
for _, suffix in ipairs({ "03", "04" }) do
  local name = "MI_D_NoiseBloodDecal_" .. suffix
  local folder = "/Game/Art/FX/Enviroment/WaterFloodedCity/Cinematic/MV_DED01_Parkinglot_AfterBattle/MA/"
  F.objects[folder .. name .. "." .. name] = F.obj(name, "Material")
end

F.classes.GameInstance = { F.obj("Game", "GameInstance") }
for _, name in ipairs({ "UserWidget", "WidgetTree", "CanvasPanel", "Image", "TextBlock", "TextBlock:SetText" }) do
  F.class("/Script/UMG." .. name)
end
StaticConstructObject = function(cls, _, name)
  local o = F.obj(tostring(name), cls.__name, { Font = {} })
  if cls.__name == "UserWidget" then
    widget = o
    o.AddToViewport = function(self) self.inViewport = not failAttach end
    o.IsInViewport = function(self) return self.inViewport end
    o.RemoveFromParent = function(self) self.inViewport = false end
  elseif cls.__name == "CanvasPanel" then
    o.AddChildToCanvas = function(_, child)
      child.Slot = F.obj("Slot", "CanvasPanelSlot")
      return child.Slot
    end
  end
  return o
end
F.sbslice.T = "ok"
local ready = F.sbslice_ready
F.sbslice_ready = function() end
local read = dofile
local menu
dofile = function(path)
  local result = read(path)
  if path == dir .. "gui.lua" then menu = result end
  return result
end
dofile(dir .. "main.lua")
dofile = read
F.fire("/Script/Engine.PlayerController:ClientRestart", F.param(nil))
F.run(10.2, pawn)
check(F.press("F3", ""), "F3 is bound with Cuts and Blood off")
F.run(0.1, pawn)
check(menu.state.pending and not inputHeld and not paused, "F3 waits for native text before holding input")
failAttach = true
ready()
F.run(0.2, pawn)
check(menu.textBy == "dll" and not menu.state.pending, "SBSlice starts and supplies text with Cuts and Blood off")
check(not menu.state.open and not inputHeld and not paused and F.find("widget did not enter the viewport"),
  "a failed viewport attach leaves the game responsive and logs the reason")
failAttach = false
F.run(0.3, pawn)
F.press("F3", "")
F.run(0.1, pawn)
check(menu.state.open and widget.inViewport and inputHeld and not paused,
  "F3 opens without pausing when Eve cannot tick during pause")
local function select_row(key)
  for i, row in ipairs(menu.ROWS) do
    if row.key == key or row.button == key then menu.state.sel = i; return end
  end
  error("missing menu row: " .. key)
end
select_row("language")
local firstWidget = widget
F.press("RIGHT_ARROW", "")
F.run(0.1, pawn)
check(widget ~= firstWidget and widget.inViewport and not firstWidget.inViewport,
  "changing the menu language still replaces the visible widget")
F.run(0.3, pawn)
F.press("F3", "")
F.run(0.1, pawn)
check(not menu.state.open and not inputHeld, "F3 returns input after an unpaused open")

local function die()
  E.s.hp = 0
  E.die(true)
  F.run(4, pawn)
end
die()
check(#decals == 0, "an intact death stays dry by default")
E.respawn()
F.run(1, pawn)

canTickPaused = true
F.press("F3", "")
F.run(0.1, pawn)
check(menu.state.open and paused and pawn.PrimaryActorTick.bTickEvenWhenPaused, "F3 still supports normal world pause")
select_row("gore.uncutPool")
F.press("RIGHT_ARROW", "")
F.run(0.4, pawn)
F.press("F3", "")
F.run(0.1, pawn)
check(not paused and not inputHeld and not pawn.PrimaryActorTick.bTickEvenWhenPaused, "closing restores pause and input")

local from = #F.cmds + 1
die()
local cut = false
for i = from, #F.cmds do if F.cmds[i].s:match("^c%x") then cut = true end end
check(#decals == 1 and decals[1].radius > 4 and decals[1].at.Z == 0 and not cut,
  "opting in through F3 grows one ground pool with cuts and their blood effects off")
E.respawn()
F.run(1, pawn)
check(decals[1] and decals[1].__dead, "recovery clears the intact ragdoll's pool")
F.press("F3", "")
F.run(0.2, pawn)
select_row("balanced")
local isInputDown = pawn.Controller.IsInputKeyDown
rawset(pawn.Controller, "IsInputKeyDown", function(_, key) return tostring(key.KeyName) == "Enter" end)
F.run(0.2, pawn)
rawset(pawn.Controller, "IsInputKeyDown", isInputDown)
check(menu.get("gore.enabled") == true and menu.get("gore.noSplits") == false
    and menu.get("gore.bladeFollow") == 0.35 and menu.get("gore.smash.overrideTargets") == true,
  "Balanced Cut Preset enables splits and adjusts both blade and blunt outcomes")
F.press("F3", "")
F.run(0.2, pawn)
local saved = dofile(dir .. "menu.lua")
check(saved["gore.death.head"] == 20 and saved["gore.smash.targetWeights.head"] == 30 and saved["gore.uncutPool"] == true,
  "the preset saves the changed weights alongside prior menu preferences")
check(#F.errors == 0 and not F.find("tick error"), "no fake engine or mod tick errors")
F.say(fails == 0 and "PASS" or "FAIL")
