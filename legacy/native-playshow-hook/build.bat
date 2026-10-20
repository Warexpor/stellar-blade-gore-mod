@echo off
set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat
call "%VCVARS%"
set OUT=%~dp0..\EveRagdollDeath\Scripts
if not exist "%OUT%" mkdir "%OUT%"
cl /nologo /O2 /LD /EHa /MD /std:c++20 "%~dp0playshow_hook.cpp" /Fe:"%OUT%\playshow.dll" /link /OUT:"%OUT%\playshow.dll"
if errorlevel 1 exit /b 1
echo built %OUT%\playshow.dll
