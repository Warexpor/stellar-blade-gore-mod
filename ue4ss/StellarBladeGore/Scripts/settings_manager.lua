-- Settings creation, layered overrides and reload notifications.
return function(goreCtx, log, set_tune, TUNE_PATH, SETTINGS_PATH, SETTINGS_DEFAULT, MENU_PATH)
-- settings.lua (the player's few switches) laid over tune.lua (every knob), key by key
local function overlay(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then overlay(dst[k], v) else dst[k] = v end
  end
end
local function first_settings()
  local f = io.open(SETTINGS_PATH, "r")
  if f then f:close(); return end
  local d = io.open(SETTINGS_DEFAULT, "r")
  if not d then return end
  local text = d:read("*a"); d:close()
  local o = io.open(SETTINGS_PATH, "w")
  if o then o:write(text); o:close(); log("settings.lua made from settings.default.lua")
  else log("settings.lua couldn't be written: settings.default.lua is used as it is") end
end

local function load_tune()
  first_settings()
  local ok, t = pcall(dofile, TUNE_PATH)
  if ok and type(t) == "table" then
    local sok, s = pcall(dofile, SETTINGS_PATH)
    if not sok and tostring(s):find("No such file", 1, true) then sok, s = pcall(dofile, SETTINGS_DEFAULT) end
    if sok and type(s) == "table" then overlay(t, s)
    elseif not tostring(s):find("No such file", 1, true) then log("settings.lua failed: " .. tostring(s)) end
    -- the in-game menu's changes (gui.lua) over both: { ["path.to.key"] = value }
    local mok, m = pcall(dofile, MENU_PATH)
    if mok and type(m) == "table" then
      for path, v in pairs(m) do
        local x, parts = t, {}
        for part in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
        for i = 1, #parts - 1 do
          if type(x[parts[i]]) ~= "table" then x[parts[i]] = {} end
          x = x[parts[i]]
        end
        if #parts > 0 then x[parts[#parts]] = v end
      end
    elseif not mok and not tostring(m):find("No such file", 1, true) then
      -- (a broken menu.lua dropped every menu change without a word)
      log("menu.lua failed, the menu's changes not applied: " .. tostring(m))
    end
    t.dev = t.dev == true
    set_tune(t)
    goreCtx.tune = t
    local keys = {}
    local function flat(prefix, x)
      for k, v in pairs(x) do
        if type(v) == "table" then flat(prefix .. k .. ".", v) else keys[#keys + 1] = prefix .. k .. "=" .. tostring(v) end
      end
    end
    flat("", t)
    table.sort(keys)
    log("tune: " .. table.concat(keys, " "))
    if goreCtx.enemies then goreCtx.enemies.reload() end
    if goreCtx.tables then goreCtx.tables.redo_dead() end
  else
    log("tune.lua failed: " .. tostring(t))
  end
end
local function base_tune()
  local ok, t = pcall(dofile, TUNE_PATH)
  if not ok or type(t) ~= "table" then return nil end
  local sok, st = pcall(dofile, SETTINGS_PATH)
  if not sok and tostring(st):find("No such file", 1, true) then sok, st = pcall(dofile, SETTINGS_DEFAULT) end
  if sok and type(st) == "table" then overlay(t, st) end
  return t
end
return load_tune, base_tune
end
