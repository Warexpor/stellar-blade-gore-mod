-- Stellar Blade Gore Mod settings. Edit and save, then restart the game or open the F3 menu in game to re-read it.
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
      limb = 42,               --   an arm or leg off
      head = 25,               --   beheaded
      torso = 15,              --   cut in half at the waist
      split = 18,              --   cut in half top to bottom (when the blow doesn't decide; a blade down her length splits too)
      -- diagonal = 15,        --   (parked for now) cut diagonally from over a shoulder to the other hip
      moreLimbs = 0.35,        --   chance a limb cut takes another limb too (and a third, at the same chance again)
    },
    bladeFollow = 0.75,        -- share of deaths with a tracked blade where the blade alone decides the cut; the rest
                               -- roll the odds above (1: always the blade, mostly waist cuts and splits)
    -- diagonal = {          (parked for now)
    --   enabled = true,          -- diagonal cuts, rolled or from a slanting blade (false: never)
    -- },
    oddsNear = {
      enabled = true,          -- the odds above follow where the blow landed: a part far from the hit isn't rolled
                               -- (a waist swing never beheads). Odds whose only kind is far from it still roll it
      floor = 0,               -- share of its odds a part far from the hit keeps (0-1; 1: the odds as they are)
    },
    torsoLegs = {
      enabled = true,          -- a cut across her waist sometimes leaves her legs playing her fall while the upper
                               -- body flies off (more often from a level swing; false: all of her ragdolls)
    },
    afterHits = {
      enabled = true,          -- enemies swinging at her body after she died cut it again
    },
    -- smash = {               (parked for now)
    --   enabled = false,         -- a blunt killing blow (a hammer, a fist, a stomp) smashes the arm, leg, head or
    --                            -- upper body it hit to meat chunks instead of cutting it
    --   always = false,          -- every death smashes, whatever hit her (to try it out)
    -- },
    laserCut = true,           -- a laser trap death cuts along the beam, everything it went through (false: the odds)
    bluntRagdoll = false,      -- a blunt killing blow (a hammer, a fist, a stomp) cuts nothing: a plain ragdoll death
                               -- (blades still cut)
    lowArm = {
      enabled = false,         -- a hit that leaves her HP under a quarter cuts an arm off; she fights on without
                               -- it (it dissolves back in at a camp rest, or comes back at her next life)
      side = "hit",            -- which arm: "hit" the one on the side the blow landed on, "left", "right" or
                               -- "either" (one at random each time)
      below = 0.25,            -- the share of her HP (0-1) a hit has to leave her under for it to come off
      noHealGun = true,        -- while the left one is off: no heal items, no gun (both need her left hand)
      notice = true,           -- and trying either shows the game's "Cannot use right now." with its sound
      noSword = true,          -- while the right one is off: no sword (gun and heals still work)
      healBack = false,        -- it also grows back once her HP is back at healAt (0.9), however she healed
      healAt = 0.9,
      effect = true,           -- what comes back at a camp rest dissolves back in (false: back at once, no effect)
    },
    throw = 250,               -- cm/s a cut-off piece flies off with (0: it just drops)
    headRagdoll = false,       -- a beheading during her animated fall always makes her a full ragdoll (false: the
    headRagdollChance = 0.6,   --   share of beheadings that do, 0-1; the rest play the fall on headless)
    legRagdoll = true,         -- a leg cut does too
    armRagdoll = false,        -- an arm cut does too (false: she falls on, the arm drops)
    armRagdollChance = 0.4,    --   with it off: the share of arm cuts that ragdoll her anyway (0-1)
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
    armSwing = {
      enabled = true,          --   with deathMoves: her arms lifting and dropping now and then (false: only the
    },                         --   struggle moves them)
    neck = {
      enabled = true,          --   her neck straining and twitching: her head trying to lift or turn, shaking, and
                               --   dropping back, sharp jerks after (false: her head lies still)
    },
  },
  deathMoves = true,           -- her body moving after a ragdoll death. Maimed (a limb off, or cut across the waist),
                               -- she struggles on the floor over her last seconds: a hand on the stump or going out
                               -- to it, trying to sit up or crawl; her arms swing in her last movements too
                               -- (false: she lies still, her face and breathing alone moving)
  struggle = {
    strength = 1.0,            --   how hard she moves in it, times the default
    length = 1.0,              --   how long it lasts, times the default (5-8 s)
    rise = {
      alone = 0.5,             --   share of ragdoll deaths with nothing cut off that still try to sit up (0: none)
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
    animated = true,           -- light deaths play her own fall animation and only the cut pieces fall by physics
                               -- (heavy hits, explosions, falls, waist cuts and splits are ragdolls anyway, and every
                               -- death with gore.enabled false); false:
                               -- every death a full ragdoll
    fallRagdoll = true,        -- a fall damage death is a ragdoll (false: her animated fall, when it is one)
    push = 1.0,                -- how hard the killing blow throws her body, times the default (0: no push of ours)
    stiffness = 1.0,           -- how stiff her ragdoll is: 0 limp as a sack, 1 as made, 2-3 she keeps her shape as
                               -- she falls and lies (a stiffer, more held-together body)
  },
  deathScreen = "delay",       -- when the death screen comes up: "game" at once, as the game does; "delay" 10 s into
                               -- the death; "key" only when you press Shift+F4. Shift+F4 also shows it early, and
                               -- hides it again once it is up (she stays down till you press it again)
  fewerGC = false,            -- fewer garbage collection hitches: no forced pass each time the game unloads part of
                              -- the map (its regular pass a minute still runs); off by default: the game's own behaviour
  hideHud = true,             -- the HUD (HP bar, skills, minimap) hidden through a death, back as she is up again
  holdPad = { "Gamepad_DPad_Down", "Gamepad_RightShoulder" }, -- Shift+F4 on the controller: both down in a death
                               -- shows the death screen or hides it again; key names as UE's Gamepad_* (false: none)
  holdPadFor = 1.0,           -- seconds both are held before it counts (a quick press of both in a fight came by accident)
  holdDown = true,             -- knocked down, she stays down till you dodge or jump (false: she gets up on her own)
  enemies = {
    enabled = true,            -- the same cuts on generic humanoid enemies you kill
    attackDown = true,         -- they keep attacking her while she is knocked down (false: they wait, as in the game)
    afterDeath = {
      enabled = false,         -- after her death the enemies around her keep attacking her body (being tested): those
      time = 10,               --   within 4.5 m play their own attacks at it for this many seconds, and their weapons
    },                         --   cut it through Hits After Death
    cutChance = 1.0,           -- chance a kill near her cuts something off (0-1)
    pushScale = 1.0,           -- times the game's own throw of a dying enemy (0: drops on the spot; 2: twice as far);
                               -- works with the cuts off too
    push = 0,                  -- cm/s every dying enemy is pushed along the blow on top (0: none)
  },
  bosses = {                   -- Sandbox Bosses (F3 → Sandbox): spawn Tachy, Raven or Scarlet in front of her and kill
    enabled = false,           -- them like any enemy (no cutscene), cut, struggling and with a dead face
    pick = "tachy",            -- tachy, raven, scarlet (DLC)
    hpScale = 0.25,            -- their HP and shield times this
    struggle = true,           -- their death struggle (with Death Struggle on)
  },
  playAs = {
    who = "eve",               -- Play As: eve, tachy, raven (her suit and hair, Eve's face), scarlet (DLC); each with her own blade
  },
  smoothAnim = false,          -- every character animated every frame: the engine skips frames on characters further
                               -- off or small on screen, which can look choppy, running most (costs some CPU)
  verboseLog = false,          -- a detailed log, for a bug report when asked for one (the log is made anew each start,
                               -- the last one kept as stellarbladegore.log.old)
  dev = false,                 -- test keys (F5-F11, Insert, Delete, Home, End, Page Up, Page Down), the enemy spawner, the glass
                               -- cannon mode (Page Down) and the schema dump on first start; see the README
}
