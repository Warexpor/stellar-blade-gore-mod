# Installing fixes

Always install each completed fix into the local game after updating the changelog and technical docs, before reporting completion. Do not stop at building or packaging it, and do not ask again for permission to install.

For Lua/native fixes on Linux, run `bash ue4ss/install.sh`; for changed pak assets, also run `./build.sh --install`. On Windows use `.\windows.ps1` per below. Preserve player settings and verify the installed files match the fixed sources/build. If installation is blocked, report the specific blocker.

## Windows development

Use `.\windows.ps1` for Windows builds, tests, packaging, and installation; see the Windows development section of README.md for actions and dependencies. The current-user Windows PowerShell execution policy is `RemoteSigned`, so local scripts run without an execution-policy override. For Lua/native fixes use `.\windows.ps1 -Action install`; for changed pak assets also use `.\windows.ps1 -Action build-install`.

## Communication style

- When talking to the user directly: human language always, warm and plain. No robot lists unless asked.
- Still verify like an engineer: base claims on logs and code (`file:line`), run the sims, install to game, confirm MATCH, keep `settings.lua` as-is. Just tell it like a human.
