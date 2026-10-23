-- Stellar Blade Gore Mod settings. Edit and save, then restart the game or press F6 in game to re-read it.
-- (settings.default.lua is what ships: the mod copies it to settings.lua on its first start, and reads settings.lua.
-- Edit settings.lua; an update replaces only the default.)
-- Anything here overrides the same key in tune.lua (the full list of knobs, for tinkering).
return {
  gore = {
    enabled = true,            -- false: no cuts and no blood at all
    -- hitMarks = {              (parked for now)
    --   enabled = true,          -- a hit she lives through leaves a slash of blood on her skin (healing fades it)
    -- },
    death = {                  -- relative odds of what her death does when the blow doesn't decide it
      limb = 50,               --   an arm or leg off
      head = 30,               --   beheaded
      torso = 12,              --   cut in half at the waist
      split = 8,               --   cut in half top to bottom (only on a blow from above)
    },
    afterHits = {
      enabled = true,          -- enemies swinging at her body after she died cut it again
    },
    voice = {
      enabled = true,          -- her own death cry (false: the game's death voice only)
      -- sounds = { "vo_eve_die_01", "vo_eve_die_fall_01" },  -- which recordings (default: vo_eve_die_01-05); names
      --   under Sound/Dialogue/ActionVoice/Eve, or full paths of another mod's SoundWaves / SoundCues
    },
    deathFace = {
      enabled = true,          -- a dead face on her as she dies, eyes closing (false: the game's own, gone 1 s in)
    },
  },
  convulse = {
    enabled = true,            -- after her death her face winces, gasps and twitches for a while, fading out (beheaded
                               -- or split down her length: none of it)
    face = true,               --   her face moving (false: it stays as the death face left it)
    voice = {
      enabled = true,          --   quiet breaths and moans along (false: silent)
      volume = 1.0,            --   how loud, times the default (0.5: half)
    },
    neck = {
      enabled = true,          --   her neck straining and twitching: her head trying to lift or turn, shaking, and
                               --   dropping back, sharp jerks after (false: her head lies still)
    },
  },
  cameraStill = true,          -- after her death you turn the camera round her, mouse or right stick, and fly it with
                               -- WASD, Q/E (down/up), Shift (faster) or the left stick and triggers, till the death
                               -- screen (false: the game's own camera, which jerks after her body)
  cameraMouse = 3,             --   mouse speed
  cameraStick = 150,           --   right stick speed, degrees a second
  cameraTrack = 2.5,           --   how closely it slides after her body, on the level, till you fly it (0: it stays put)
  cameraMove = 400,            --   flying speed, cm a second
  -- deathSkip = true,         -- Esc on her death fast forwards to the death screen (parked for now)
  active = {
    stiffness = 1.0,           -- how stiff her ragdoll is: 0 limp as a sack, 1 as made, 2-3 she keeps her shape as
                               -- she falls and lies (a stiffer, more held-together body)
  },
  holdPad = { "Gamepad_DPad_Down", "Gamepad_RightShoulder" }, -- Shift+F4 on the controller: both down in a death holds
                               -- it (no death screen, she stays down), again lets it go; key names as UE's Gamepad_*
                               -- (false: none)
  holdDown = true,             -- knocked down, she stays down till you dodge or jump (false: she gets up on her own)
  enemies = {
    enabled = true,            -- the same cuts on generic humanoid enemies you kill
    attackDown = true,         -- they keep attacking her while she is knocked down (false: they wait, as in the game)
  },
  dev = false,                 -- test keys (F5, F7-F11 and their Shift/Ctrl variants), the enemy spawner, the glass
                               -- cannon mode (Shift+F8) and the schema dump on first start; see the README
}
