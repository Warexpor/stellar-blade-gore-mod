-- Guarded asset lookup and its world-reset cache.
return function(M, native, get_ctx, get_guards, log)
local cache = {}
local function load_obj(path)
  local ctx = get_ctx()
  local try, valid = get_guards()
  -- nothing roots the Niagara systems once their components are cleaned up, so GC frees them; a cached
  -- wrapper then points at a dead object (crash on the next death's blood spawn). Checking the cached wrapper wasn't
  -- enough: a freed object's address gets reused, IsValid then passes on whatever lives there now, and a sound cue
  -- read that way crashed PlaySoundAtLocation (attenuation pointer 0x1, eighteenth playtest's F11). Found by path
  -- every time instead
  -- Engine class/default objects persist for the process lifetime. Reuse their wrappers;
  -- asset wrappers still require a fresh lookup because they can be garbage collected.
  if path:sub(1, 8) == "/Script/" and valid(cache[path]) then return cache[path] end
  local held = M.guardedAssets[path]
  if held and ctx.held then
    local t0 = path:sub(1, 12) == "/Game/Sound/" and os.clock() or nil
    local alive = ctx.held(held)
    if t0 and (os.clock() - t0) * 1000 >= 10 then
      log(string.format("sound asset guard %s took %.0f ms", path:match("([^/.]+)$") or path, (os.clock() - t0) * 1000))
    end
    if alive then return held.obj end
  end
  if held then M.guardedAssets[path] = nil; native.rooted[path] = nil end
  local o = try(function() return StaticFindObject(path) end)
  -- not from the pak around a respawn (ctx.may_load): a load then waited on the level's own loading, whose new
  -- objects wait on the Lua lock the tick holds (an endless loading screen, Nexus report); found next time instead
  if not valid(o) and not ctx.may_load() then return nil end
  if not valid(o) and LoadAsset then o = try(function() return LoadAsset(path) end) end
  if not valid(o) then o = try(function() return StaticFindObject(path) end) end
  cache[path] = valid(o) and o or false
  if not valid(o) then log("could not load " .. path) end
  -- an asset (not a native class or default object) stays loaded from now on: see native.root
  if valid(o) and path:sub(1, 8) ~= "/Script/" and native.root then native.root(path, o) end
  if valid(o) and native.rooted and native.rooted[path] == true and ctx.keep and ctx.held then
    local k = ctx.keep(o)
    if k and ctx.held(k) then M.guardedAssets[path] = k end
  end
  return valid(o) and o or nil
end

return { load = load_obj, forget = function() cache = {} end }
end
