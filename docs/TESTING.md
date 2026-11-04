# Testing the mod

The Lua simulations are fast regression checks against a fake game, not proof of behavior or performance in Stellar Blade. The fake engine supplies objects, time, hooks and native responses; it cannot reproduce the engine's threading, garbage collection, render stalls, real assets, or every animation and outfit. Use a game playtest and its log for those questions.

On Windows, run `.\windows.ps1 -Action test-lua` from PowerShell, or pass `-Scenario split,frame` to select scenarios. Each scenario runs in its own scratch game directory; the runner requires a successful Lua exit, a `PASS` line, and no `FAIL` assertion line. The default list is in `ue4ss/test/run.sh`; `diag` is opt-in because the diagonal feature is parked. The native harness is `.\windows.ps1 -Action test-native`. Default native runs can skip mesh and physics-parity cases when build caches are absent; inspect the output. Explicitly selected cache-dependent groups fail when their required cache is missing.

## What representative checks establish

- `newobj_fallback` checks watcher fallback choices in isolation. It cannot exercise UE4SS callback threading.
- `charcache` checks lifetime-batch sizes, cache reuse, and fake character read cadence; `reload` checks cleanup against a simulated freed screen. Native `test_alive` separately checks the native object-array logic. Neither can prove the real engine never frees an object between calls.
- `cutlist` compares selected cut lists with fake engine traversal and checks use of warmed trees; real skeletons still need game verification.
- `split`, `stages`, and `smash_lifecycle` drive the scripts through cut stages and recovery in a fake world. `frame` checks geometric mirror properties, `tachy_geometry` checks bone selection and UV behavior on shipped core data, and `cap_fallback` checks actor placement after a simulated mesh failure. They cannot verify the rendered appearance or real physics.
- `ragdoll_probe` checks that ordinary startup skips three diagnostic snapshots and that probes still enable them. `perf_probe` checks the GC-probe death pause and restoration of original GC options. `hook_perf` counts fake lookups; `swing_perf` compares sweep results to a reference and prints a benchmark. These do not measure in-game frame times.
- `settings_manager` checks first-run creation, layered overrides, reload notifications and preservation of a simulated player settings file.
- `death_face` checks fake morph selection, application, cleanup and reloaded settings; it cannot verify visual expression or a real head swap.
- `voiceas` checks alternate-character voice selection with a death that allows post-death voice; `split` separately checks post-death movement suppression, but does not directly assert audio output.
- `after_geometry` checks a hand crossing, a distant miss and an interpolated blade crossing against a known synthetic limb; actual weapon bounds and motion need a game test.
- `after` checks simulated follow-up attacks and cleanup. `after_nomontage` checks walking and overhead misses and a fast swing without a montage cutting the remaining arm. Its initial death is constrained to an arm and its swing crosses the opposite arm; this checks that scenario, not every possible weapon plane or death.

## Reading results

Some scenarios inspect log messages, and some use `debug.getupvalue` to reach local state. A log assertion can fail after harmless wording changes; an upvalue test can fail after a harmless refactor. Such a failure is a reason to investigate the behavior, not to blindly restore the wording or internal shape. Conversely, passing a log or call-count assertion does not establish that a player sees the intended result. Prefer direct observable state, realistic geometry and independent expected results where the fake environment can express them.

The above is a review of representative scenarios, not an audit of every test. Before removing or merging a scenario, identify the behavior it alone protects and whether another check covers the same failure mode. Preserve the in-game log and settings across installations, and record what still needs a real-world retest in the changelog and technical notes.
