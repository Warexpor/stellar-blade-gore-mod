# Runtime structure

This is a map of the current implementation. The mod combines UE4SS Lua, the native `sbslice` helper and game asset patches. The Lua runs against game objects whose lifetime is controlled by Unreal; fake-game tests do not reproduce all engine behavior.

## Startup and shared context

`main.lua` builds `goreCtx`, delegates settings file creation and layered loading to `settings_manager.lua`, then loads and initializes the feature modules. It owns the player/death lifecycle, hook wiring and the game loop. The shared context supplies services and callbacks to the modules; some callbacks read live main-loop state, so copying their current values at startup would change behavior. Reloaded player settings are kept separate from the shipped defaults.

`object_lifetime.lua` installs the retained-object guards on that context. A frame epoch controls native liveness checks; a separate poll epoch controls shared character walks. Objects kept across engine callbacks must use the existing guard rules: probing an already-freed UE object through Lua can crash the process. The native helper performs the underlying object-array checks.

`swing_selection.lua` selects the killing weapon sweep using current settings and object guards, sampling each successfully read fallback-pose joint once per sweep. `swing_tracking.lua` maintains nearby weapons and pose history; its per-world bone cache is cleared on world changes. The main loop owns the current selected swing and schedules tracking.

`projectile_hits.lua` owns projectile impact geometry, hit callbacks, watch registration and rock correction. The main loop supplies fresh pawn, mesh-hit and gore state, retains hook wrappers and owns post-death projectile queues and world cleanup.

`low_arm.lua` owns low-health limb restrictions, settling, regrowth, camp restoration and their shared recovery state. It reads the current gore service, settings and hit evidence at each operation; main retains hit tracking and world lifecycle.

`hit_classification.lua` classifies blunt and sharp hit evidence and dispatches blunt smashes. It reads current settings, the tracked swing and gore service through callbacks; hit collection and death decisions remain in the main loop.

`hits_after.lua` selects and gates follow-up swings and dispatches cuts or queued projectile smashes. It reads current settings, swing and gore services; main owns the shared per-death state and reset. `after_hit_geometry.lua` computes the spatial intersection of hand and weapon sweeps with body segments, reusing successful shared-joint reads only within a single calculation.

`death_face.lua` creates separate expression controllers for the player and sandbox bosses, each with its own morph cache and cleanup state. It reads current settings and gore services through callbacks.

`cloth_reset.lua` owns spawn and outfit cloth resets, temporary collision changes, guarded restoration and hair simulation. State remains on `screen` for world changes and the main lifecycle supplies current ragdoll, gore and recovery services.

`death_camera.lua` owns the held camera, its controls and release. Main-loop recovery calls its interface and world cleanup discards its old actor references; live settings and shared photo-mode screen state remain accessible.

`death_screen.lua` controls death/revive visibility, periodic probing, hooks, transitions and intro animation; shared screen state is reset during recovery and world cleanup.

`death_widgets.lua` owns death/revive widget discovery and new-object watches; main-loop world cleanup still resets its shared state and guards are checked before use.

`photo_guard.lua` coordinates the cut/ragdoll photo shield and active photo watch, including close handling and weapon-trail reset.

`photo_visibility.lua` owns photo visibility tracking and near-clip restoration, retaining shared cleanup state.

`photo_freeze.lua` owns photo pause detection, mesh/hair freeze and detached-head face updates. Shared state is retained for recovery and world cleanup.

`photo_controls.lua` handles photo input and death holds using live lifecycle state; key registration remains in the main loop.

`photo_collision.lua` captures and restores photo-mode collision on body, cloth and capsule components; its shared snapshot can be discarded during recovery or world cleanup.

`death_hud.lua` owns death HUD traversal, hiding and restoration; its state remains on the screen object so world cleanup can discard old widget references. It reads the current lifecycle and settings through callbacks.

`performance.lua` installs frame reports and the GC probe on shared screen state. It reads current death state, pawn and settings through callbacks. It deliberately avoids native probe requests during the first six seconds of a death. Its GC option records and restores the engine's original values.

## Gore and movement

`gore.lua` owns the shared lifecycle: cut orchestration and queues, actor/mesh work, and cleanup or restoration. Native dispatch, hit decisions and several effects are delegated to the modules below. `active.lua` handles ragdoll behavior and physics; `struggle.lua` and `convulse.lua` handle post-death movements. The shared context carries callbacks between these systems. A cut can progress through multiple render frames; recovery, reload or another cut can interrupt that work. State and cleanup must be considered together.

The staged cut scheduler in `gore_scheduler.lua` advances pending cuts on render frames and services delayed audio, impact effects and bleeding work under separate budgets. `gore_ownership.lua` tags work to an owner through `enemy.run` and guards enemy-owned objects; player recovery partitions shared lists around its cleanup, while enemy removal filters that owner's work and objects. Those operations replace several list tables, so another module must not retain a snapshot of them. Blood trackers explicitly record ownership on creation because smash-chunk trackers are inserted at the front. World cleanup discards old references without reading freed actors.

The extracted gore helpers have narrower responsibilities:

- `blade_decision.lua` classifies blade planes against recorded or current poses and chooses and queues cuts. The gore lifecycle still owns queued work, interruption and aim state, which the decision module accesses live.
- `outfit_animation.lua` controls outfit physics nodes and split rigs. Normal recovery restores them; world cleanup drops old mesh references and address-based caches without probing the old world.
- `split_plane.lua` computes split planes, anatomical hit sides and blade slant; `split_break.lua` selects spine breaks while respecting limbs kept on each half. `split_cut.lua` handles preparation and the two staged native cuts; rollback, scheduling and opening remain in the gore lifecycle.
- `gore_copies.lua` discovers other mods’ pose-following mesh copies and synchronizes or releases their cut weights in native-sized batches; split copies and world cleanup share its bookkeeping. The flush keeps newly queued updates for the next frame and stops when recovery replaces its current copy set or cut list.
- `gore_hit_marks.lua` owns living-hit decal queries, placement, healing and cleanup. Its public state remains on the gore module for preload and world cleanup; the unfinished feature remains disabled by default.
- `gore_smash_select.lua` ranks smash targets and computes impact coverage and remaining flesh from the current cut list. `gore_smash.lua` handles dispatch, piece visibility and restoration, chunks and blood; delayed work and spawned actors remain in live gore-lifecycle queues.
- `gore_watch.lua` schedules background bone preparation, pool refills and paced preloads, reading live cut state before work.
- `gore_scheduler.lua` advances cut stages and delayed impact work through live queue access; the gore lifecycle owns and replaces the underlying queues.
- `gore_floor.lua` owns floor tracing and bounded geometry checks. `gore_pools.lua` owns tracked openings, decal creation, pool growth and cleanup, using live list accessors because recovery and enemy removal replace their tables.
- `gore_native.lua` owns the Lua-side native handshake, command dispatch and seam hold, preserving live cut and object guard access.
- `gore_regrow.lua` owns regrowth copies, dissolve materials, sink handoff and cleanup; it reads current cut/copy/LOD state as recovery may replace those lists.
- `body_blood.lua` owns the player skin-blood ramp and original values, retaining restoration values across world cleanup until the gore tick supplies a valid new pawn.
- `gore_assets.lua` owns guarded asset lookup and its disposable world cache; rooted package guards survive world changes and are validated before use. `gore_preload.lua` owns native rooting and the asynchronous request/poll protocol; the gore lifecycle schedules work.
- `bone_lists.lua` owns per-mesh bone trees and cached native cut lists; world cleanup clears its derived caches.
- `slice_response.lua` parses the native helper's numeric, vector and opening response fields.
- `cap_geometry.lua` generates ordinary procedural cap geometry; `tachy_geometry.lua` supplies Tachy opening frames, surface geometry, bone selection and UV mapping. Actor creation and materials stay in the gore lifecycle.
- `split_rides.lua` selects spine anchors available to a split half and its lid.
- `gore_audio.lua` owns cue choices and playback spacing; `gore_voice.lua` owns voice selection, playback, fades and voice preload paths. Both depend on current game context; the voice module reads the current cut list on demand.

`enemies.lua` and `bosses.lua` handle enemy-side features. `physfix.lua` manages outfit physics compatibility. Other modules include settings UI and keys, stains, tables, new-object watching and optional compatibility features. `sbslice.dll` handles native operations including mesh cuts, object lifetime and object watching; its protocol and engine-address assumptions are described in `TECHNICAL.md`.

## Change boundaries

Keep state transitions, their cleanup, and scheduling together when moving a subsystem; do not assume a cut or a death completes uninterrupted. Preserve frame vs poll timing, current settings and UE-object lifetime guards. Prefer a small explicit interface to sharing mutable state, and check whether a table is replaced during cleanup before capturing it in another module. Moving code alone is not a performance fix: measure engine calls and frame timing in game.

The main and gore files retain lifecycle coordination across hooks, staged cuts, rollback and recovery. Their size reflects coupled game transitions, so changes there should be assessed with the associated subsystem and cleanup path rather than moving a transition in isolation. Use `TESTING.md` to select simulations and record game-only verification limits.
