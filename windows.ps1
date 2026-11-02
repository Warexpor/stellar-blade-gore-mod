param(
    [ValidateSet('build', 'check-build', 'build-install', 'native', 'test-lua', 'test-native', 'package', 'check-package', 'install')]
    [string]$Action = 'build',
    [string]$GamePath = $env:SB_GAME,
    [string[]]$Scenario = @()
)

$ErrorActionPreference = 'Stop'
$bash = 'C:\msys64\usr\bin\bash.exe'
if (!(Test-Path -LiteralPath $bash)) { throw 'MSYS2 was not found at C:\msys64.' }
if (!$GamePath) {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $libraries = @($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $libraries += (Get-Content -LiteralPath $vdf | Select-String '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value.Replace('\\', '\') })
        }
        foreach ($library in $libraries) {
            $candidate = Join-Path $library 'steamapps\common\StellarBlade'
            if (Test-Path -LiteralPath (Join-Path $candidate 'SB\Binaries\Win64\SB-Win64-Shipping.exe')) { $GamePath = $candidate; break }
        }
    }
}
if ($GamePath) { $env:SB_GAME = (Resolve-Path -LiteralPath $GamePath).Path }
$env:MSYSTEM = 'CLANG64'
& $bash (Join-Path $PSScriptRoot 'windows\dev.sh') $Action @Scenario
exit $LASTEXITCODE
