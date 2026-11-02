# Installing fixes

Always install each completed fix into the local game after updating the changelog and technical docs, before reporting completion. Do not stop at building or packaging it, and do not ask again for permission to install.

For Lua/native fixes, run `bash ue4ss/install.sh`; for changed pak assets, also run `./build.sh --install`. Preserve player settings and verify the installed files match the fixed sources/build. If installation is blocked, report the specific blocker.

## Windows development

Use `.\windows.ps1` for Windows builds, tests, packaging, and installation; see the Windows development section of README.md for actions and dependencies. The current-user Windows PowerShell execution policy is `RemoteSigned`, so local scripts run without an execution-policy override. For Lua/native fixes use `.\windows.ps1 -Action install`; for changed pak assets also use `.\windows.ps1 -Action build-install`.
