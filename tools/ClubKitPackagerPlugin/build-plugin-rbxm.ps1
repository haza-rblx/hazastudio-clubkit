# Bundle plugin (nested Script + modules + UpdatePluginGUI) -> Plugins .rbxm
param(
    [string]$OutPath = (Join-Path $env:LOCALAPPDATA "Roblox\Plugins\HazastudioClubKitPackager.rbxm")
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$rojo = Join-Path (Split-Path (Split-Path $here -Parent) -Parent) ".tools\rojo\rojo.exe"

if (-not (Test-Path $rojo)) {
    Write-Error "Rojo not found at $rojo"
}

$gui = Join-Path $here "UpdatePluginGUI.rbxmx"
if (-not (Test-Path $gui)) {
    Write-Error "Missing UpdatePluginGUI.rbxmx next to default.project.json (export from Studio)."
}

Remove-Item (Join-Path $env:LOCALAPPDATA "Roblox\Plugins\HazastudioClubKitPackager.rbxmx") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA "Roblox\Plugins\HazastudioClubKitPackager") -Recurse -Force -ErrorAction SilentlyContinue

Push-Location $here
try {
    & $rojo build default.project.json --output $OutPath
    if ($LASTEXITCODE -ne 0) {
        throw "rojo build failed with exit $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$size = (Get-Item $OutPath).Length
Write-Host "Installed: $OutPath ($size bytes)"
Write-Host "Restart Roblox Studio, then check Manage Plugins / Open Panel"
