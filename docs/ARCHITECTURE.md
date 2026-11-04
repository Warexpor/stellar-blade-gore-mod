# Runtime structure

This is a map of the current implementation, not a claim that its boundaries are finished. The mod combines UE4SS Lua, the native `sbslice` helper and game asset patches. The Lua runs against game objects whose lifetime is controlled by Unreal; fake-game tests do not reproduce all engine behavior.

## Startup and shared context

`main.lua` builds `goreCtx`, delegates settings file creation and layered loading to `settings_manager.lua`, then loads and initializes the feature modules. It owns the player/death lifecycle, hook wiring and the game loop. The shared context supplies services and callbacks to the modules; some callbacks read live main-loop state, so copying their current values at startup would change behavior. Reloaded player settings are kept separate from the shipped defaults.

`object_lifetime.lua` installs the retained-object guards on that context. A frame epoch controls native liveness checks; a separate poll epoch controls shared character walks. Objects kept across engine callbacks must use the existing guard rules: probing an already-freed UE object through Lua can crash the process. The native helper performs the underlying object-array checks.

`after_hit_geometry.lua` computes the spatial intersection of after-death hand and weapon sweeps with body segments; `main.lua` still owns attack gating and cut dispatch.

`death_face.lua` creates separate expression controllers for the player and sandbox bosses, each with its own morph cache and cleanup state. It reads current settings and gore services through callbacks.

`performance.lua` installs frame reports and the GC probe on shared screen state. It reads current death state, pawn and settings through callbacks. It deliberately avoids native probe requests during the first six seconds of a death. Its GC option records and restores the engine's original values.

## Gore and movement

`gore.lua` still owns the largest shared lifecycle: cut selection and queues, native commands, actor/mesh work, effects, and cleanup or restoration. `active.lua` handles ragdoll behavior and physics; `struggle.lua` and `convulse.lua` handle post-death movements. The shared context carries callbacks between these systems. A cut can progress through multiple render frames; recovery, reload or another cut can interrupt that work. State and cleanup must be considered together.

The extracted gore helpers have narrower responsibilities:

- `bone_lists.lua` owns per-mesh bone trees and cached native cut lists; world cleanup clears its derived caches.
- `slice_response.lua` parses the native helper's numeric, vector and opening response fields.
- `cap_geometry.lua` generates ordinary procedural cap geometry; `tachy_geometry.lua` supplies Tachy opening frames, surface geometry, bone selection and UV mapping. Actor creation and materials stay in the gore lifecycle.
- `split_rides.lua` selects spine anchors available to a split half and its lid.
- `gore_audio.lua` owns cue choices and playback spacing; `gore_voice.lua` owns voice selection, playback, fades and voice preload paths. Both depend on current game context; the voice module reads the current cut list on demand.

`enemies.lua` and `bosses.lua` handle enemy-side features. `physfix.lua` manages outfit physics compatibility. Other modules include settings UI and keys, stains, tables, new-object watching and optional compatibility features. `sbslice.dll` handles native operations including mesh cuts, object lifetime and object watching; its protocol and engine-address assumptions are described in `TECHNICAL.md`.

## Change boundaries

Keep state transitions, their cleanup, and scheduling together when moving a subsystem; do not assume a cut or a death completes uninterrupted. Preserve frame vs poll timing, current settings and UE-object lifetime guards. Prefer a small explicit interface to sharing mutable state, and check whether a table is replaced during cleanup before capturing it in another module. Moving code alone is not a performance fix: measure engine calls and frame timing in game.

The remaining main and gore files still contain multiple responsibilities. In particular, screen/photo/camera behavior, attack and hit selection, staged cuts, pools and effects need further mapping before they can be safely separated. Use `TESTING.md` to select focused simulations and record game-only verification limits.
