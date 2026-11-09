# Installing fixes

Always install each completed fix into the local game after updating the changelog and technical docs, before reporting completion. Do not stop at building or packaging it, and do not ask again for permission to install.

For Lua/native fixes on Linux, run `bash ue4ss/install.sh`; for changed pak assets, also run `./build.sh --install`. On Windows use `.\windows.ps1` per below. Preserve player settings and verify the installed files match the fixed sources/build. If installation is blocked, report the specific blocker.

## Windows development

Use `.\windows.ps1` for Windows builds, tests, packaging, and installation; see the Windows development section of README.md for actions and dependencies. The current-user Windows PowerShell execution policy is `RemoteSigned`, so local scripts run without an execution-policy override. For Lua/native fixes use `.\windows.ps1 -Action install`; for changed pak assets also use `.\windows.ps1 -Action build-install`.

## Tooling

- Install whatever tools, SDKs, runtimes or dependencies the job needs without asking for permission. Interested result only: just get it done and report blockers if installation fails.

## Communication style

- When talking to the user directly: human language always, plain and to the point. No robot lists unless asked. Professional, not gushing: no hype, no cheerleading, no performative excitement. Keep responses short: only the crucial info, no padding.
- Still verify like an engineer: base claims on logs and code (`file:line`), run the sims, install to game, confirm MATCH, keep `settings.lua` as-is.

## Testing scope

- Never run the full test suite on a minor change: run only the focused sims for what changed. The full suite runs only when the change touches shared harnesses or module boundaries, or the user asks for it.
