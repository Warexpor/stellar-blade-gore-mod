-- Stellar Blade Gore Mod settings. Edit and save, then restart the game or press F6 in game to re-read it.
-- (settings.default.lua is what ships: the mod copies it to settings.lua on its first start, and reads settings.lua.
-- Edit settings.lua; an update replaces only the default.)
-- Anything here overrides the same key in tune.lua (the full list of knobs, for tinkering).
return {
  gore = {
    enabled = true,            -- false: no cuts and no blood at all
    hitMarks = {
      enabled = true,          -- a hit she lives through leaves a slash of blood on her skin (healing fades it)
    },
    death = {                  -- relative odds of what her death does when the blow doesn't decide it
      limb = 30,               --   an arm or leg off
      head = 22,               --   beheaded
      torso = 38,              --   cut in half at the waist
      split = 10,              --   cut in half top to bottom (only on a blow from above)
    },
    afterHits = {
      enabled = true,          -- enemies swinging at her body after she died cut it again
    },
    voice = {
      enabled = true,          -- her own death cry (false: the game's death voice only)
    },
  },
  enemies = {
    enabled = true,            -- the same cuts on generic humanoid enemies you kill
  },
  dev = false,                 -- test keys (F5, F7-F11 and their Shift/Ctrl variants), the enemy spawner, the glass
                               -- cannon mode (Shift+F8) and the schema dump on first start; see the README
}
