-- Classify attack evidence and dispatch a blunt killing blow.
return function(sw, get_tune, get_swing, get_gore, len, log)
-- ---- blunt or sharp (tune.gore.smash, experimental) ----
-- A killing blow from a blunt weapon smashes the part it landed on to meat (gore.smash) instead of cutting it. What
-- hit her is told by names, each against smash.sharp first, then smash.blunt: the weapon meshes of the enemy that
-- swung, its swinging bone, then the enemy itself (its name and class). Failing those, a bare hand or foot with no
-- weapon mesh is blunt (smash.bareHands), and so is a blow from above with no weapon (a stomp). Anything else cuts.
-- Returns blunt (true / false) and why. Asked with gore.smash or gore.bluntRagdoll on, else every blow is a blade.
-- real: what hit her only, smash.always aside (bluntRagdoll's ask)
function sw.blunt_alias(text)
  local tune = get_tune()
  -- The game's actors are CH_M_NA_16_Blueprint_C_1, not "SkullHammer". Use the existing spawn definitions to
  -- resolve those opaque names; match the Blueprint boundary so CH_M_NA_16 never matches CH_M_NA_160.
  local low = tostring(text or ""):lower()
  for _, group in ipairs({ (tune.enemies or {}).kinds or {}, (tune.bosses or {}).kinds or {} }) do
    for _, k in pairs(group) do
      local bp = type(k.bp) == "string" and k.bp:match("([^/]+)$"):lower()
      if bp and (low == bp or low:sub(1, #bp + 1) == bp .. "_") then return k.alias end
    end
  end
  -- clawed enemies with no weapon meshes (tune.gore.smash.species): judged by the name it gives their class
  for frag, name in pairs(((tune.gore or {}).smash or {}).species or {}) do
    local f = tostring(frag):lower()
    if f ~= "" and (low == f or low:sub(1, #f + 1) == f .. "_") then return tostring(name) end
  end
end
function sw.blunt_of(h, real)
  local tune, swing = get_tune(), get_swing()
  local g = tune.gore or {}
  local s = g.smash or {}
  if (s.enabled ~= true and g.bluntRagdoll ~= true) or not h then return false, "off" end
  if s.enabled == true and s.always == true and not real then return true, "smash.always" end
  if h.blast then return true, "explosion death show" end
  if h.projectile then return true, "projectile hit result" end
  if h.rock then return true, "Gorilla rock projectile" end
  local function judge(what, text)
    local low = tostring(text or ""):lower()
    if low == "" then return nil end
    for _, list in ipairs({ { s.sharp or {}, false }, { s.blunt or {}, true } }) do
      for _, w in ipairs(list[1]) do
        if low:find(tostring(w):lower(), 1, true) then return list[2], string.format("%s %s: %s", what, text, w) end
      end
    end
  end
  -- (the swing's weapons only when it was the swing that killed her: a made-up blow names the nearest enemy)
  local mine = h.attacker == nil or h.attacker == swing.who
  local weapons = h.weaponNames or (mine and swing.weapons) or {}
  local bluntWeapon, bluntWhy
  for _, w in ipairs(weapons) do
    local b, why = judge("weapon", type(w) == "string" and w or w.name)
    -- MeshInfoList order isn't evidence of which weapon hit. A blade among several meshes wins over a generic
    -- blunt match, just as sharp wins inside a single name; never turn a sword into a hammer by slot order.
    if why and not b then return false, why end
    if why then bluntWeapon, bluntWhy = b, why end
  end
  if bluntWhy then return bluntWeapon, bluntWhy end
  local wb = h.wbone
  if wb then
    local b, why = judge("weapon bone", wb)
    if why then return b, why end
  end
  for _, t in ipairs({ h.attacker or swing.who or "", h.attackerClass or (mine and swing.cls) or "" }) do
    local b, why = judge("enemy", t)
    if why then return b, why end
    local alias = sw.blunt_alias(t)
    b, why = judge("enemy alias", alias)
    if why then return b, why .. " (" .. t .. ")" end
  end
  if #weapons == 0 and s.bareHands ~= false and wb then
    local low = wb:lower()
    -- hair whips (Marionette LeftHandHair) contain "hand": judged sharp above, never a bare fist
    if low:find("hair", 1, true) then return false, string.format("hair weapon (%s), not a bare hand", wb) end
    for _, w in ipairs({ "hand", "fist", "foot", "toe", "knee", "elbow" }) do
      if low:find(w, 1, true) then return true, string.format("bare %s (%s), no weapon mesh", w, wb) end
    end
  end
  local d = h.dir
  if #weapons == 0 and s.bareHands ~= false and (not h.made or h.stomp) and d and len(d) > 1e-3
    and d.Z / len(d) < -(g.splitDown or 0.6) then
    return true, "a blow from above with no weapon (a stomp)"
  end
  return false, string.format("nothing blunt about %s%s", tostring(h.attacker or swing.who),
    wb and (" (" .. wb .. ")") or "")
end
-- a blunt killing blow smashed (gore.smash); true when it did. why: "death"
function sw.smash_kill(pawn, mesh, h, why)
  local tune, gore = get_tune(), get_gore()
  local g = tune.gore or {}
  if not (gore and gore.smash) or g.enabled == false or (g.smash or {}).enabled ~= true then return false end
  local blunt, how = sw.blunt_of(h)
  log(string.format("death: the blow is %s (%s)", blunt and "blunt" or "a blade", how))
  if not blunt then return false end
  local ok, r, later = pcall(gore.smash, pawn, mesh, h, why)
  if not ok then log("smash failed: " .. tostring(r)); return false end
  return r, later
end


end
