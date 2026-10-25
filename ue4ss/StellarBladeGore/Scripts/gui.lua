-- The in-game settings menu (tune.menuKey F3, or tune.menuPad on the controller): plain UMG widgets made here at
-- runtime in the look of the game's own settings screen (its fonts, colours and layout; nothing in the pak). The
-- world goes on while it is open (it was slowed to a stop: asked not to be); her moving and looking are held. Q/E (LB/RB) switch the tab, Up/Down (or the D-pad) picks a row, Left/Right
-- changes it, R / Y (Triangle) puts the tab back to settings.lua, Enter / A presses a button, Backspace / B or the key again closes it. A change applies at once; on
-- closing, the changed values are saved to menu.lua (path = value), which wins over settings.lua, and the settings
-- are read again (the enemies' and the death table's are made over from them). "Reset to settings.lua" deletes it.
-- The Keys tab (keys.lua): Enter on a row, then the new key, which another action had is swapped onto its old one.
local M = {}
local ctx, log, try, valid

M.PATH = "ue4ss/Mods/StellarBladeGore/Scripts/menu.lua"
M.FONT = "/Game/Art/Font/Rajdhani-BoldM_Font.Rajdhani-BoldM_Font"
-- the settings screen's own: labels in Mideum, values and tabs in Bold (M.FONT when one isn't found)
M.FONT_MID = "/Game/Art/Font/Mideum.Mideum"
M.FONT_BOLD = "/Game/Art/Font/Bold.Bold"
-- the game's own key icons (80 x 80, the key in the middle of each)
M.ICONS = "/Game/Art/UI/Texture/Interaction/"
M.HINTS = {
  kb = { { { "PC/KeyIcon_KeyBoard_Q", "PC/KeyIcon_KeyBoard_E" }, "Tab", "Q E" },
    { { "PC/KeyIcon_KeyBoard_Left", "PC/KeyIcon_KeyBoard_Right" }, "Adjust", "< >" },
    { { "PC/KeyIcon_KeyBoard_R" }, "Reset Tab", "R" },
    { { "PC/KeyIcon_KeyBoard_F3" }, "Exit", "F3" } },
  xbox = { { { "XBOX/KeyIcon_XboxOne_Gamepad_LeftShoulder", "XBOX/KeyIcon_XboxOne_Gamepad_RightShoulder" }, "Tab", "LB RB" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_DPad_X" }, "Adjust", "D-PAD" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_FaceButton_Top" }, "Reset Tab", "Y" },
    { { "XBOX/KeyIcon_XboxOne_Gamepad_FaceButton_Right" }, "Exit", "B" } },
  playstation = { { { "DualSense/KeyIcon_DualSense_Gamepad_LeftShoulder", "DualSense/KeyIcon_DualSense_Gamepad_RightShoulder" }, "Tab", "L1 R1" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_DPad_X" }, "Adjust", "D-PAD" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Top" }, "Reset Tab", "TRI" },
    { { "DualSense/KeyIcon_DualSense_Gamepad_FaceButton_Right" }, "Exit", "O" } },
}
-- rows: a tab (section), a setting (bool, num with min/max/step, list of values with their names), or a button
M.ROWS = {
  { section = "Gore" },
  { key = "gore.enabled", label = "Cuts and Blood", kind = "bool", help = "Master switch for all cuts, stumps and blood, on Eve and on enemies. Off: deaths are plain ragdolls." },
  { key = "gore.death.limb", label = "Limb Cut Chance", kind = "num", min = 0, max = 100, step = 5, help = "Rolled when no blade was tracked, or Blade Decides left it aside. Weight against the other chances: the arm or leg nearest the hit comes off." },
  { key = "gore.death.head", label = "Beheading Chance", kind = "num", min = 0, max = 100, step = 5, help = "Rolled when no blade was tracked, or Blade Decides left it aside. Weight against the other chances: the head comes off." },
  { key = "gore.death.torso", label = "Waist Cut Chance", kind = "num", min = 0, max = 100, step = 5, help = "Rolled when no blade was tracked, or Blade Decides left it aside. Weight against the other chances: the body is cut in two at the waist, leaning a little at random." },
  { key = "gore.death.split", label = "Vertical Split Chance", kind = "num", min = 0, max = 100, step = 5, help = "Weight against the other chances: the body splits in two from head to hips. Unlike the others it is rolled on every death, even with a tracked blade." },
  { key = "gore.death.moreLimbs", label = "Extra Limb Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance a limb cut takes the next nearest limb too (0-1), and a third at the same chance again. At 0.35: 35% two or more limbs, 12% three. Rolled limb cuts only; a tracked blade cuts every limb it crosses." },
  { key = "gore.bladeFollow", label = "Blade Decides", kind = "num", min = 0, max = 1, step = 0.05, help = "Share of deaths with a tracked blade where the blade alone decides what is cut (0-1). The rest roll the chances above. At 1 most deaths are waist cuts or splits, since a blade mostly crosses her body." },
  { key = "gore.torsoLegs.enabled", label = "Waist Cut Leg Animation", kind = "bool", help = "A waist cut during an animated death fall: the legs and hips keep playing the fall while the upper body flies off as a ragdoll. Off: the whole body goes ragdoll." },
  { key = "gore.torsoLegs.rolled", label = "   Leg Animation Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance of the leg animation when no blade was tracked (0-1). A level swing uses 0.75 and a slanted one 0.35 (tune.lua)." },
  { key = "gore.afterHits.enabled", label = "Hits After Death", kind = "bool", help = "Enemy weapons swinging through Eve's dead body cut it again (a limb, the head or the body), up to 6 times a death. About a quarter leave only a wound." },
  { key = "gore.throw", label = "Cut Piece Force", kind = "num", min = 0, max = 800, step = 25, unit = " cm/s", help = "Speed a piece flies off with when it wasn't cut by the killing blow, e.g. a hit after death (0: it just drops). The killing blow's pieces fly with the blow (deathThrow in tune.lua)." },
  { key = "holdDown", label = "Stay Down After Knockdown", kind = "bool", help = "When knocked down, Eve stays on the ground until you dodge or jump. Off: she gets up by herself after a second, as in the game." },
  -- { section = "Stumps" },
  -- { key = "gore.tachyRelief", label = "Stump Detail", kind = "num", min = 0, max = 3, step = 0.25, help = "Depth of the flesh detail on stumps (0: smooth). New cuts." },
  -- { key = "gore.stubBone", label = "Spine Bone Thickness", kind = "num", min = 0.1, max = 0.6, step = 0.02, help = "Share of the cut's width (next cut)." },
  { section = "Death" },
  { key = "deathScreen", label = "Death Screen", kind = "list", values = { "game", "delay", "key" },
    names = { game = "Instant", delay = "Delayed", key = "Shift+F4" },
    help = "When the death screen appears. Instant: as the game shows it. Delayed: after Death Screen Delay. Shift+F4: only when you press Shift+F4 (or hold D-pad down + R1 for a second), which also brings it up early or hides it again." },
  { key = "hideHud", label = "Hide HUD on Death", kind = "bool", help = "Hides the HUD (HP bar, skills, minimap, notices) through a death, so the body lies on a clean screen. The death screen still comes up as Death Screen says. Off: the HUD stays up, as in the game." },
  { key = "reviveAt", label = "Death Screen Delay", kind = "num", min = 1, max = 60, step = 1, unit = " s", help = "Seconds into a death before the death screen (and the revive item screen) shows. Only used with Death Screen set to Delayed." },
  { key = "gore.voice.enabled", label = "Death Scream", kind = "bool", help = "Eve cries out, from her own voice recordings, the moment she dies. Off: only the game's own death voice." },
  { key = "gore.deathFace.enabled", label = "Death Expression", kind = "bool", help = "Holds a lifeless expression on her face for the whole death, her eyes closing. Off: the game's own face, which goes blank about a second in with her eyes open." },
  { key = "convulse.enabled", label = "Post-Death Movement", kind = "bool", help = "For a few seconds after she falls: winces, gasps, eye flutters and a last breath. Her body itself stays still unless convulse.body is turned on in tune.lua." },
  { key = "convulse.face", label = "   Facial Movement", kind = "bool", help = "The winces, gasps and eyelid flutters on her face. Off: her face stays still (the neck and the breathing can still play)." },
  { key = "convulse.voice.enabled", label = "   Breathing Sounds", kind = "bool", help = "Quiet breaths with her gasps and an occasional moan. Never once she is beheaded, and never over her death scream." },
  { key = "convulse.voice.volume", label = "   Breathing Volume", kind = "num", min = 0, max = 3, step = 0.1, help = "Volume of those breaths and moans (1: default, 0: silent)." },
  { key = "convulse.neck.enabled", label = "   Neck Movement", kind = "bool", help = "Her head strains to lift or turn, shakes with the effort, drops back, then jerks a few times. Not once she is beheaded." },
  { key = "active.animated", label = "Animated Death Falls", kind = "bool", help = "Standing and light-hit deaths play Eve's own fall animation and hold its end pose; cut pieces still fall by physics. Heavy hits, explosions, mid-air deaths and splits are ragdolls. Off: every death is a full ragdoll." },
  { key = "gore.headRagdoll", label = "   Ragdoll When Beheaded", kind = "bool", help = "A beheading during an animated fall always switches her to a full ragdoll. Off: the chance below decides." },
  { key = "gore.headRagdollChance", label = "   Beheading Ragdoll Chance", kind = "num", min = 0, max = 1, step = 0.1, help = "With Ragdoll When Beheaded off: the chance a beheading during an animated fall ragdolls her. The rest play the fall on headless." },
  { key = "gore.legRagdoll", label = "   Ragdoll When Leg Cut", kind = "bool", help = "A leg cut during an animated fall switches her to a full ragdoll. Off: she plays the fall to the end without the leg." },
  { key = "gore.armRagdoll", label = "   Ragdoll When Arm Cut", kind = "bool", help = "An arm cut during an animated fall switches her to a full ragdoll. Off: she plays the fall on and the arm drops away." },
  { key = "gore.armRagdollChance", label = "   Arm Cut Ragdoll Chance", kind = "num", min = 0, max = 1, step = 0.1, help = "With Ragdoll When Arm Cut off: the chance an arm cut during an animated fall ragdolls her anyway (each arm rolled, so both off is likelier). 0: she always plays the fall on." },
  { key = "active.push", label = "Death Push", kind = "num", min = 0, max = 4, step = 0.25, unit = "x", help = "How hard the killing blow throws Eve's body, on top of the game's own throw (1: default, 0: the game's alone, 2: twice the default)." },
  { key = "active.stiffness", label = "Ragdoll Stiffness", kind = "num", min = 0, max = 3, step = 0.25, help = "Muscle tone in her ragdoll as she falls. 0: limp from the start, 1: default (firm, going limp as she lands), 2-3: she holds her shape longer." },
  { section = "Enemies" },
  { key = "enemies.enabled", label = "Enemy Gore", kind = "bool", help = "Cuts and blood on humanoid enemies killed within 25 m of Eve." },
  { key = "enemies.cutChance", label = "   Cut Chance", kind = "num", min = 0, max = 1, step = 0.05, help = "Chance a kill cuts something off (0-1): along your swing when you swung, else a limb, the head or a waist cut at random." },
  { key = "enemies.pushScale", label = "Death Throw", kind = "num", min = 0, max = 4, step = 0.25, unit = "x", help = "Scales the game's own throw of a dying enemy (1: as the game, 0: it drops on the spot, 2: twice as far). Works with Enemy Gore off too." },
  { key = "enemies.push", label = "Extra Death Push", kind = "num", min = 0, max = 1000, step = 50, unit = " cm/s", help = "Speed added to every enemy death along the blow, slightly upward, on top of Death Throw (0: none). Works with Enemy Gore off too." },
  { key = "enemies.attackDown", label = "Attacks While Down", kind = "bool", help = "Enemies keep attacking Eve while she is knocked down. Off: they wait for her to get up, as in the game." },
  { section = "Camera" },
  { key = "cameraStill", label = "Free Camera", kind = "bool", help = "At a death the camera stops riding her pawn and holds where it is until she gets up. Turn it with the mouse or right stick; fly it with WASD, Q/E or the left stick and triggers (Shift: faster)." },
  { key = "cameraMouse", label = "   Mouse Sensitivity", kind = "num", min = 0.5, max = 10, step = 0.5, help = "How fast the mouse turns the death camera." },
  { key = "cameraStick", label = "   Stick Sensitivity", kind = "num", min = 30, max = 400, step = 10, help = "How fast the right stick turns the death camera, in degrees a second at full tilt." },
  { key = "cameraTrack", label = "   Follow Strength", kind = "num", min = 0, max = 10, step = 0.5, help = "How quickly the death camera slides sideways after her body, never up or down (0: it stays put). It stops following once you fly it." },
  { key = "cameraMove", label = "   Fly Speed", kind = "num", min = 100, max = 2000, step = 50, unit = " cm/s", help = "How fast the death camera flies (Shift: three times that). It stays within 15 m of where it started." },
  { section = "Mod" },
  { key = "menuPadIcons", label = "Controller Icons", kind = "list", values = { "xbox", "playstation" },
    names = { xbox = "Xbox", playstation = "PlayStation" }, help = "Which controller's buttons this menu shows when you use a controller." },
  { key = "smoothAnim", label = "Smooth Character Animation", kind = "bool", help = "Animates every character every frame. The engine updates distant or small characters less often, which can look choppy, most of all when they run. Costs some CPU with many on screen." },
  { key = "verboseLog", label = "Detailed Log", kind = "bool", help = "Writes every per-frame detail to stellarbladegore.log, for bug reports. The log grows much faster; leave it off otherwise." },
  { key = "dev", label = "Developer Keys", kind = "bool", help = "Test keys (F5 test death, F7 ragdoll, F9-F11 cuts), the enemy spawner and glass cannon mode. See the README." },
  { button = "reset", label = "Reset to settings.lua", help = "Throws away every change made in this menu (deletes menu.lua) and goes back to settings.lua's values." },
  { button = "close", label = "Close", help = "Closes the menu. Changes are already applied, and are saved to menu.lua, which wins over settings.lua." },
}
M.VISIBLE = 12 -- rows on screen at once (a longer tab scrolls)
M.KEYS = {
  up = { "Up", "Gamepad_DPad_Up", "Gamepad_LeftStick_Up" },
  down = { "Down", "Gamepad_DPad_Down", "Gamepad_LeftStick_Down" },
  left = { "Left", "Gamepad_DPad_Left", "Gamepad_LeftStick_Left" },
  right = { "Right", "Gamepad_DPad_Right", "Gamepad_LeftStick_Right" },
  ok = { "Enter", "Gamepad_FaceButton_Bottom" },
  back = { "BackSpace", "Gamepad_FaceButton_Right" },
  reset = { "R", "Gamepad_FaceButton_Top" },
  tabl = { "Q", "Gamepad_LeftShoulder" },
  tabr = { "E", "Gamepad_RightShoulder" },
}
M.state = { open = false, sel = 2, top = 1, ui = nil, held = {}, changed = {}, toggled = 0 }

function M.init(c)
  ctx, log, try, valid = c, c.log, c.try, c.valid
  -- the Keys tab (keys.lua's actions), before Mod
  if ctx.keys and not M.keysAdded then
    M.keysAdded = true
    local at = #M.ROWS + 1
    for i, r in ipairs(M.ROWS) do if r.section == "Mod" then at = i; break end end
    local rows = { { section = "Keys" } }
    for _, a in ipairs(ctx.keys.ACTIONS) do
      rows[#rows + 1] = { key = "keys." .. a.id, id = a.id, label = a.label, kind = "key",
        help = a.help .. " Enter, then press the new key (Ctrl, Shift and Alt can go with it); Backspace cancels. A key another action had is swapped with this one's." }
    end
    for k, r in ipairs(rows) do table.insert(M.ROWS, at + k - 1, r) end
    M.TABS = nil
  end
end

-- a setting by its dotted path in the live tune table, and set
local function get_in(t, path)
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[tonumber(part) or part]
  end
  return t
end
local function get(path)
  local t = ctx.tune
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[tonumber(part) or part]
  end
  return t
end
local function set(path, v)
  local t, last = ctx.tune, nil
  local parts = {}
  for part in path:gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
  for i = 1, #parts - 1 do
    if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
    t = t[parts[i]]
  end
  last = parts[#parts]
  t[last] = v
end
M.get = get

-- menu.lua: { ["path"] = value, ... } read over the settings (main.lua's load_tune), written here
function M.overlay(t)
  local ok, m = pcall(dofile, M.PATH)
  if not ok or type(m) ~= "table" then return 0 end
  local n = 0
  for path, v in pairs(m) do
    if type(path) == "string" and type(v) ~= "table" then
      local parts, x = {}, t
      for part in path:gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
      for i = 1, #parts - 1 do
        if type(x[parts[i]]) ~= "table" then x[parts[i]] = {} end
        x = x[parts[i]]
      end
      x[parts[#parts]] = v
      n = n + 1
    end
  end
  return n
end
local function save()
  local saved = {}
  local ok, m = pcall(dofile, M.PATH)
  if ok and type(m) == "table" then for k, v in pairs(m) do saved[k] = v end end
  for k in pairs(M.state.changed) do saved[k] = get(k) end
  -- (a value back at settings.lua's, a tab reset, is dropped from menu.lua)
  local base = ctx.base_tune and ctx.base_tune()
  if base then for k in pairs(M.state.changed) do if get_in(base, k) == saved[k] then saved[k] = nil end end end
  local keys = {}
  for k in pairs(saved) do keys[#keys + 1] = k end
  if #keys == 0 then return true end
  table.sort(keys)
  local f = io.open(M.PATH, "w")
  if not f then log("menu: can't write " .. M.PATH); return false end
  f:write("-- Settings changed in the in-game menu (F3). They win over settings.lua; delete this file (or the menu's\n")
  f:write("-- \"Reset to settings.lua\") to go back to it.\nreturn {\n")
  for _, k in ipairs(keys) do
    local v = saved[k]
    f:write(string.format("  [%q] = %s,\n", k, type(v) == "string" and string.format("%q", v) or tostring(v)))
  end
  f:write("}\n")
  f:close()
  return true
end

local function value_text(row)
  if row.kind == "key" then
    if M.state.capture and M.state.capture.id == row.id then return "Press a key..." end
    return ctx.keys.show(ctx.keys.binding(row.id))
  end
  local v = get(row.key)
  if row.kind == "bool" then return v and "On" or "Off" end
  if row.kind == "list" then return (row.names and row.names[v]) or tostring(v) end
  if type(v) ~= "number" then return tostring(v) end
  local s = row.step < 1 and string.format("%.2f", v):gsub("0$", "") or string.format("%d", math.floor(v + 0.5))
  return s .. (row.unit or "")
end

local function selectable(i) local r = M.ROWS[i]; return r and not r.section end
-- the tabs: { name, first, last } (row indices), one per section
local function tabs()
  if M.TABS then return M.TABS end
  local t = {}
  for i, r in ipairs(M.ROWS) do
    if r.section then t[#t + 1] = { name = r.section, first = i + 1, last = i }
    elseif t[#t] then t[#t].last = i end
  end
  M.TABS = t
  return t
end
local function tab_of(i)
  local T = tabs()
  for k, t in ipairs(T) do if i >= t.first and i <= t.last then return k, t end end
  return 1, T[1]
end

-- ---- the widgets ----
local function build()
  -- each stage logged first (the log is flushed a line at a time): a crash in the game's code here leaves no Lua
  -- error, only the last stage reached
  local function stage(what) log("menu: making it: " .. what) end
  stage("game instance")
  local function cls(p)
    local c = StaticFindObject(p)
    if not valid(c) then error("no class " .. p) end
    return c
  end
  local gi = FindFirstOf("GameInstance")
  if not valid(gi) then error("no game instance") end
  -- layout units: 1920 x 1080 fitted into the viewport (by its height on a wider screen: scaled by the width alone,
  -- a 21:9 screen was 810 units tall and the last rows and the help line fell off its bottom)
  local K = 1.0
  try(function()
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local size, scale = lib:GetViewportSize(gi), lib:GetViewportScale(gi)
    if size.X > 0 and size.Y > 0 and scale > 0 then K = math.min(size.X / 1920, size.Y / 1080) / scale end
  end)
  if K < 0.5 or K > 4 then K = 1.0 end
  -- fonts and icons only as found in memory, never loaded: LoadAsset from her tick is the likely crash of
  -- 0.4.0's F3 for players whose game hadn't loaded them yet (reported: every time). Not found: a
  -- TextBlock's own font, a key cap for an icon
  local function load_font(path)
    local f = StaticFindObject(path)
    return valid(f) and f or nil
  end
  stage("fonts")
  local fallback = load_font(M.FONT)
  local mid, bold = load_font(M.FONT_MID) or fallback, load_font(M.FONT_BOLD) or fallback
  log(string.format("menu: fonts found: %s %s %s", fallback and "yes" or "no", load_font(M.FONT_MID) and "yes" or "no",
    load_font(M.FONT_BOLD) and "yes" or "no"))
  -- the viewport's height in layout units (the backdrop covers it)
  local VH, VW = 1080, 1920
  try(function()
    local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local size, scale = lib:GetViewportSize(gi), lib:GetViewportScale(gi)
    if size.Y > 0 and scale > 0 then VH = size.Y / scale / K end
    if size.X > 0 and scale > 0 then VW = size.X / scale / K end
  end)
  stage("widgets")
  local stamp = string.format("%d%04d", os.time(), math.random(0, 9999))
  local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), gi, FName("SBGore_Menu_" .. stamp))
  local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SBGore_MenuTree"))
  w.WidgetTree = tree
  local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SBGore_MenuCanvas"))
  tree.RootWidget = canvas
  local n = 0
  -- ax, ay: the slot's alignment (0.5: x / y is its middle)
  local function place(slot, x, y, ww, hh, ax, ay)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAlignment({ X = ax or 0, Y = ay or 0 })
    slot:SetPosition({ X = x * K, Y = y * K })
    if ww then slot:SetAutoSize(false); slot:SetSize({ X = ww * K, Y = hh * K }) else slot:SetAutoSize(true) end
  end
  local function box(x, y, ww, hh, r, g, b, a)
    n = n + 1
    local im = StaticConstructObject(cls("/Script/UMG.Image"), tree, FName("SBGore_Img" .. n))
    local slot = canvas:AddChildToCanvas(im)
    place(slot, x, y, ww, hh)
    im:SetColorAndOpacity({ R = r, G = g, B = b, A = a })
    return im, slot
  end
  -- o: { font, wrap (the width it breaks at, layout units), boxw + just (in a box that wide: 1 centred, 2 right),
  -- spacing, mid (y is the line's middle: centred on a box's), centre (x is its middle) }
  local function text(x, y, size, s, o)
    o = o or {}
    n = n + 1
    local tb = StaticConstructObject(cls("/Script/UMG.TextBlock"), tree, FName("SBGore_Txt" .. n))
    -- (the glyphs sit a little above their line's middle: 1/12 of the size down)
    if o.mid then y = y + size / 12 end
    place(canvas:AddChildToCanvas(tb), x, y, o.boxw, o.boxw and size * 1.8, o.centre and 0.5, o.mid and 0.5)
    try(function()
      local f = tb.Font
      local fo = o.font or mid
      if fo then f.FontObject = fo end
      f.Size = math.floor(size * K + 0.5)
      if o.spacing then f.LetterSpacing = o.spacing end
    end)
    if o.wrap then try(function() tb.WrapTextAt = o.wrap * K; tb.AutoWrapText = false end) end
    if o.just then
      if not try(function() tb:SetJustification(o.just); return true end) then try(function() tb.Justification = o.just end) end
    end
    tb:SetText(FText(s or ""))
    return tb
  end
  local function tint(tb, r, g, b, a)
    try(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = r, G = g, B = b, A = a or 1 }, ColorUseRule = 0 }) end)
  end
  -- a focus box: white, a blue glow round it (as the game's Slot_Focus); its parts, shown and hidden together
  local function focus(x, y, ww, hh)
    local parts = {}
    for _, gl in ipairs({ { 8, 0.10 }, { 5, 0.22 }, { 2, 0.5 } }) do
      parts[#parts + 1] = box(x - gl[1], y - gl[1], ww + 2 * gl[1], hh + 2 * gl[1], 0.02, 0.22, 0.75, gl[2])
    end
    parts[#parts + 1] = box(x, y, ww, hh, 1, 1, 1, 1)
    return parts
  end

  -- the backdrop: near black, lighter blue-grey to the right, darker to the bottom, the faint crosses of the
  -- game's screen down the left
  box(0, 0, VW, VH, 0.004, 0.006, 0.009, 0.985)
  for i = 0, 39 do
    box(880 + i * (VW - 880) / 40, 0, (VW - 880) / 40 + 1, VH, 0.03, 0.045, 0.065, ((i + 1) / 40) ^ 1.6 * 0.6)
  end
  for i = 0, 9 do
    box(0, VH - 170 + i * 17, VW, 18, 0, 0, 0, (i + 1) / 10 * 0.55)
  end
  for _, c in ipairs({ { 96, 150 }, { 264, 186 }, { 96, 300 }, { 264, 312 }, { 96, 432 }, { 264, 440 }, { 96, 575 },
      { 264, 568 }, { 96, 720 }, { 264, 704 }, { 96, 852 }, { 264, 828 }, { 434, 210 }, { 434, 806 }, { 588, 800 } }) do
    box(c[1] - 30, c[2], 60, 1, 1, 1, 1, 0.06)
    box(c[1], c[2] - 30, 1, 60, 1, 1, 1, 0.06)
  end
  local ui = { w = w, rows = {}, tabs = {}, K = K, tint = tint }
  -- the title (the game's orange), the mod's name and version small under it
  tint(text(101, 92, 23, "Gore Settings"), 0.716, 0.246, 0.034)
  tint(text(101, 196, 9, "STELLAR BLADE GORE MOD  " .. tostring(ctx.version or ""), { font = bold, spacing = 200 }), 0.25, 0.27, 0.3)
  -- tabs and rows on one grid: the same top, height and spacing, so a tab lines up with the row beside it
  local r0, rh, bh = 222, 58, 48
  ui.r0, ui.rh = r0, rh
  -- the tabs down the left
  for k, t in ipairs(tabs()) do
    local ty = r0 + (k - 1) * rh
    ui.tabs[k] = { focus = focus(101, ty, 208, bh), txt = text(116, ty + bh / 2, 17, t.name, { font = bold, mid = true }) }
  end
  -- the rows: label left, value centred (at 945), arrows the same distance either side of it on the focused row
  local vc = 945
  for i = 1, M.VISIBLE do
    local ry = r0 + (i - 1) * rh
    local cy = ry + bh / 2
    ui.rows[i] = { focus = focus(385, ry, 790, bh),
      lab = text(400, cy, 17, "", { wrap = 340, mid = true }),
      val = text(vc, cy, 18, "", { font = bold, centre = true, mid = true }),
      la = text(vc - 170, cy, 18, "<", { font = bold, centre = true, mid = true }),
      ra = text(vc + 170, cy, 18, ">", { font = bold, centre = true, mid = true }) }
  end
  -- a thin scroll bar right of the rows, for a tab longer than the screen
  ui.track = { x = 1196, y = r0, h = M.VISIBLE * rh - 10 }
  ui.trackBg = box(ui.track.x, ui.track.y, 2, ui.track.h, 1, 1, 1, 0.08)
  ui.thumb, ui.thumbSlot = box(ui.track.x, ui.track.y, 2, rh, 0.02, 0.32, 0.9, 1)
  -- what the focused row does
  ui.help = text(400, r0 + M.VISIBLE * rh + 14, 15, "", { wrap = 780 })
  tint(ui.help, 0.32, 0.33, 0.35)
  -- the keys, bottom right: the game's key icons and their names, the keyboard's or the controller's (the last one
  -- used; the controller's as menuPadIcons says). An icon that doesn't load is a white key cap with its text
  local function icon(path, x, y, sz)
    local tex = StaticFindObject(M.ICONS .. path .. "." .. path:match("[^/]+$"))
    if not valid(tex) then return nil end
    local im = box(x, y, sz, sz, 1, 1, 1, 1)
    if not try(function() im:SetBrushFromTexture(tex, false); return true end) then
      try(function() im:SetRenderOpacity(0) end)
      return nil
    end
    return im
  end
  local function hints(list)
    local IS, STEP, GAP = 44, 36, 34 -- icon size; the next icon of one hint (the icons' own margins overlap); between hints
    local width = 0
    for i, h in ipairs(list) do width = width + IS + (#h[1] - 1) * STEP + 4 + #h[2] * 10 + (i < #list and GAP or 0) end
    local x, cy, out = VW - 90 - width, VH - 73, {}
    for _, h in ipairs(list) do
      local ims = {}
      for j, p in ipairs(h[1]) do ims[#ims + 1] = icon(p, x + (j - 1) * STEP, cy - IS / 2, IS) end
      if #ims == #h[1] then
        for _, im in ipairs(ims) do out[#out + 1] = im end
      else
        for _, im in ipairs(ims) do try(function() im:SetRenderOpacity(0) end) end
        -- the key cap fallback, over the hint's icon space
        local kw = IS + (#h[1] - 1) * STEP - 8
        out[#out + 1] = box(x + 4, cy - 13, kw, 26, 0.95, 0.95, 0.95, 1)
        local kt = text(x + 4 + kw / 2, cy, 11, h[3], { font = bold, centre = true, mid = true })
        tint(kt, 0.03, 0.035, 0.05)
        out[#out + 1] = kt
      end
      x = x + IS + (#h[1] - 1) * STEP + 4
      out[#out + 1] = text(x, cy, 17, h[2], { font = bold, mid = true })
      x = x + #h[2] * 10 + GAP
    end
    return out
  end
  stage("key icons")
  ui.keys = {}
  -- the keyboard's Exit is the menu's key as bound (a key cap with its name when the game has no icon for it)
  local mk = ctx.keys and ctx.keys.binding("menu") or "F3"
  ui.menuKey = mk
  for set, list in pairs(M.HINTS) do
    if set == "kb" and ctx.keys then
      local l = {}
      for i, h in ipairs(list) do l[i] = h end
      local mods, key = ctx.keys.parse(mk)
      local k = key and ctx.keys.BY_ENUM[key]
      local plain = k and next(mods) == nil
      l[#l] = { { "PC/KeyIcon_KeyBoard_" .. (plain and k.fkey or "None") }, "Exit", ctx.keys.show(mk) }
      list = l
    end
    ui.keys[set] = hints(list)
  end
  stage("on screen")
  try(function() w:SetVisibility(3) end) -- not hit-testable: the game keeps the mouse
  w:AddToViewport(960)
  return ui
end

local function show(im, on) try(function() im:SetRenderOpacity(on and 1 or 0) end) end
local function show_all(list, on) for _, x in ipairs(list) do show(x, on) end end
local function render()
  local s, ui = M.state, M.state.ui
  if not ui then return end
  local tint = ui.tint
  local tk, t = tab_of(s.sel)
  -- the selection kept on screen, within its tab
  if s.top < t.first or s.top > t.last then s.top = t.first end
  if s.sel < s.top then s.top = s.sel end
  if s.sel > s.top + M.VISIBLE - 1 then s.top = s.sel - M.VISIBLE + 1 end
  for k, tab in ipairs(ui.tabs) do
    local on = k == tk
    show_all(tab.focus, on)
    if on then tint(tab.txt, 0.022, 0.025, 0.05) else tint(tab.txt, 0.62, 0.63, 0.65) end
  end
  for i = 1, M.VISIBLE do
    local r = ui.rows[i]
    local idx = s.top + i - 1
    local row = idx <= t.last and M.ROWS[idx] or nil
    local on = row ~= nil and idx == s.sel
    show_all(r.focus, on)
    local lab, val = row and row.label or "", row and row.key and value_text(row) or ""
    try(function() r.lab:SetText(FText(lab)); r.val:SetText(FText(val)) end)
    -- (no arrows on a key: Enter takes a new one)
    local arrows = on and val ~= "" and row.kind ~= "key"
    show(r.la, arrows); show(r.ra, arrows)
    if on then
      tint(r.lab, 0.022, 0.025, 0.05); tint(r.val, 0.022, 0.025, 0.05)
      tint(r.la, 0.02, 0.32, 0.9); tint(r.ra, 0.02, 0.32, 0.9)
    else
      -- a sub-setting (its label indented) a shade dimmer
      local c = lab:sub(1, 1) == " " and 0.38 or 0.6
      tint(r.lab, c, c, c * 1.03); tint(r.val, 0.85, 0.85, 0.86)
    end
  end
  local cur = M.ROWS[s.sel]
  try(function() ui.help:SetText(FText(cur and cur.help or "")) end)
  local padSet = ctx.tune.menuPadIcons == "xbox" and "xbox" or "playstation"
  for set, list in pairs(ui.keys) do show_all(list, set == (s.pad and padSet or "kb")) end
  -- the scroll bar, only on a tab longer than the screen
  local count = t.last - t.first + 1
  local long = count > M.VISIBLE
  show(ui.trackBg, long); show(ui.thumb, long)
  if long then
    local tr, K = ui.track, ui.K
    local th = tr.h * M.VISIBLE / count
    local ty = tr.y + (tr.h - th) * (s.top - t.first) / (count - M.VISIBLE)
    try(function()
      ui.thumbSlot:SetPosition({ X = tr.x * K, Y = ty * K })
      ui.thumbSlot:SetSize({ X = 2 * K, Y = th * K })
    end)
  end
end

-- ---- open, close, her input held ----
local function controller(pawn)
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  return gs, valid(gs) and try(function() return gs:GetPlayerController(pawn, 0) end)
end
local function pause(pawn, on)
  local s = M.state
  local gs, pc = controller(pawn)
  if not valid(gs) then return end
  if on and not s.paused then
    s.paused = { pawn = pawn, pc = pc }
    if valid(pc) then
      try(function() pc:SetIgnoreMoveInput(true) end)
      try(function() pc:SetIgnoreLookInput(true) end)
      try(function() pawn:DisableInput(pc) end)
    end
  elseif not on and s.paused then
    local p = s.paused
    s.paused = nil
    if valid(p.pc) then
      try(function() p.pc:ResetIgnoreMoveInput() end)
      try(function() p.pc:ResetIgnoreLookInput() end)
      if valid(pawn) then try(function() pawn:EnableInput(p.pc) end) end
    end
  end
end
function M.open(pawn)
  local s = M.state
  if s.open then return end
  local ok = s.ui and valid(s.ui.w) and try(function() return s.ui.w:IsInViewport() end)
  -- (made again for a menu key rebound since: its Exit hint)
  if ok and ctx.keys and s.ui.menuKey ~= ctx.keys.binding("menu") then
    try(function() s.ui.w:RemoveFromParent() end)
    ok = false
  end
  if not ok then
    local built, ui = pcall(build)
    if not built then log("menu: couldn't be made: " .. tostring(ui)); return end
    s.ui = ui
  else
    try(function() s.ui.w:SetVisibility(3) end)
  end
  s.open, s.held, s.changed, s.swallow = true, {}, {}, true
  if not selectable(s.sel) then s.sel = 2 end
  pause(pawn, true)
  log("menu: making it: first draw")
  render()
  log("menu: opened")
end
local function capture_end()
  M.state.capture = nil
  if ctx.keys then ctx.keys.capture = nil end
  -- (the key just taken, still down, isn't a press in the menu)
  M.state.swallow = true
end
function M.close(pawn)
  local s = M.state
  if not s.open then return end
  if s.capture then capture_end() end
  s.open = false
  if s.ui and valid(s.ui.w) then try(function() s.ui.w:SetVisibility(1) end) end
  pause(pawn, false)
  local names = {}
  for k in pairs(s.changed) do names[#names + 1] = k .. "=" .. tostring(get(k)) end
  table.sort(names)
  if #names > 0 then
    save()
    log("menu: closed, saved to menu.lua: " .. table.concat(names, " "))
    if ctx.reload_tune then ctx.reload_tune() end
  else
    log("menu: closed, nothing changed")
  end
end
-- pad: opened from the controller (its key hints shown till a key is pressed)
function M.toggle(pawn, pad)
  local now = os.clock()
  if now - M.state.toggled < 0.3 then return end
  M.state.toggled = now
  if not M.state.open then M.state.pad = pad == true end
  if M.state.open then M.close(pawn) else M.open(pawn) end
end

local function step(dir)
  local s = M.state
  local row = M.ROWS[s.sel]
  if not row or not row.key or row.kind == "key" then return end
  local v = get(row.key)
  if row.kind == "bool" then v = not (v == true)
  elseif row.kind == "list" then
    local k = 1
    for i, x in ipairs(row.values) do if x == v then k = i end end
    v = row.values[(k - 1 + dir) % #row.values + 1]
  else
    v = math.max(row.min, math.min(row.max, (tonumber(v) or row.min) + dir * row.step))
    v = math.floor(v / row.step + 0.5) * row.step
    if row.step >= 1 then v = math.floor(v + 0.5) end
  end
  set(row.key, v)
  s.changed[row.key] = true
  -- (a row whose change shows at once on what is already out: its function on gore)
  if row.apply and ctx.gore and ctx.gore[row.apply] then
    local ok, err = pcall(ctx.gore[row.apply])
    if not ok then log("menu: " .. row.apply .. " failed: " .. tostring(err)) end
  end
  render()
end
local function press(pawn)
  local s = M.state
  local row = M.ROWS[s.sel]
  if not row then return end
  if row.button == "close" then M.close(pawn)
  elseif row.button == "reset" then
    os.remove(M.PATH)
    s.changed = {}
    if ctx.reload_tune then ctx.reload_tune() end
    log("menu: back to settings.lua (menu.lua deleted)")
    render()
  elseif row.kind == "bool" or row.kind == "list" then step(1)
  elseif row.kind == "key" and ctx.keys then
    -- the next key pressed (keys.lua hands it here instead of to its action)
    s.capture = { id = row.id, key = row.key, t = os.clock() }
    ctx.keys.capture = function(combo)
      local c = s.capture
      capture_end()
      if not c then return end
      local old = ctx.keys.binding(c.id)
      local others = ctx.keys.on_combo(combo, c.id)
      set(c.key, combo)
      s.changed[c.key] = true
      local swapped = {}
      for _, a in ipairs(others) do
        set("keys." .. a.id, old)
        s.changed["keys." .. a.id] = true
        swapped[#swapped + 1] = a.label
      end
      log(string.format("menu: %s on %s%s", c.id, combo, #swapped > 0 and (" (" .. table.concat(swapped, ", ") .. " moved to " .. old .. ")") or ""))
      render()
    end
    render()
  end
end
-- the tab's rows back to settings.lua's values (R / Y / Triangle), applied at once; menu.lua drops them on closing
local function reset_tab()
  local s = M.state
  local base = ctx.base_tune and ctx.base_tune()
  if not base then log("menu: tab reset: settings couldn't be read"); return end
  local _, t = tab_of(s.sel)
  local n, applies = 0, {}
  for i = t.first, t.last do
    local row = M.ROWS[i]
    if row.key then
      local v = get_in(base, row.key)
      -- (a key unset in settings.lua goes back to its default: unset here too)
      if (v ~= nil or row.kind == "key") and v ~= get(row.key) then
        set(row.key, v); s.changed[row.key] = true; n = n + 1
        if row.apply then applies[row.apply] = true end
      end
    end
  end
  for fn in pairs(applies) do
    if ctx.gore and ctx.gore[fn] then
      local ok, err = pcall(ctx.gore[fn])
      if not ok then log("menu: " .. fn .. " failed: " .. tostring(err)) end
    end
  end
  log(string.format("menu: %s tab reset to settings.lua (%d changed)", t.name, n))
  render()
end
-- up/down within the tab (round from its last row to its first), the tabs round too
local function move(dir)
  local s = M.state
  local _, t = tab_of(s.sel)
  local i = s.sel
  repeat
    i = i + dir
    if i > t.last then i = t.first elseif i < t.first then i = t.last end
  until selectable(i)
  s.sel = i
  render()
end
local function switch(dir)
  local s = M.state
  local T = tabs()
  local k = (tab_of(s.sel) - 1 + dir) % #T + 1
  s.sel, s.top = T[k].first, T[k].first
  render()
end

-- every tick of hers: the open combo on the controller, and the menu's keys while it is open (a key held repeats)
function M.tick(pawn)
  local s = M.state
  local _, pc = controller(pawn)
  if not valid(pc) then return end
  local function down(name) return try(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end) == true end
  local pad = ctx.tune.menuPad
  if type(pad) == "table" and #pad > 0 then
    local all = true
    for _, k in ipairs(pad) do if not down(k) then all = false; break end end
    if all and not s.padWas then M.toggle(pawn, true) end
    s.padWas = all
  end
  if not s.open then return end
  local now = os.clock()
  -- waiting for a key to bind: only Backspace / B (cancel) is read, and it gives up after 10 s
  if s.capture then
    local back = false
    for _, k in ipairs(M.KEYS.back) do if down(k) then back = true end end
    if back or now - s.capture.t > 10 then
      log("menu: key not changed (" .. (back and "cancelled" or "no key in 10 s") .. ")")
      capture_end()
      render()
    end
    return
  end
  for what, names in pairs(M.KEYS) do
    local on = false
    local pad
    for _, k in ipairs(names) do if down(k) then on = true; pad = k:sub(1, 7) == "Gamepad"; break end end
    local h = s.held[what]
    -- the key hints follow the last key used
    if on and not h and pad ~= s.pad then s.pad = pad; render() end
    if not on then s.held[what] = nil
    elseif s.swallow and not h then s.held[what] = { at = now, next = math.huge } -- down as it opened: not a press
    elseif not h or now >= h.next then
      s.held[what] = { at = h and h.at or now, next = now + (h and 0.08 or 0.4) }
      if what == "up" then move(-1) elseif what == "down" then move(1)
      elseif what == "tabl" and not h then switch(-1) elseif what == "tabr" and not h then switch(1)
      elseif what == "left" then step(-1) elseif what == "right" then step(1)
      elseif what == "ok" and not h then press(pawn)
      elseif what == "reset" and not h then reset_tab()
      elseif what == "back" and not h then M.close(pawn); return end
    end
  end
  s.swallow = false
end

return M
