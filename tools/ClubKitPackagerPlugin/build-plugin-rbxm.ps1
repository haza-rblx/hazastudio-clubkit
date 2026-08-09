# Bundle plugin (nested Script + modules + UpdatePluginGUI) -> Plugins .rbxm
param(
    [string]$OutPath = (Join-Path $env:LOCALAPPDATA "Roblox\Plugins\HazastudioClubKitPackager.rbxm"),
    [switch]$CopyToDeliver
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$root = Split-Path (Split-Path $here -Parent) -Parent
$rojo = Join-Path $root ".tools\rojo\rojo.exe"

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

if ($CopyToDeliver) {
    $version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
    $deliverDir = Join-Path $root "deliver"
    if (-not (Test-Path $deliverDir)) {
        New-Item -ItemType Directory -Path $deliverDir | Out-Null
    }
    $deliverName = "HazastudioClubKit_Plugin_v$version.rbxm"
    $deliverPath = Join-Path $deliverDir $deliverName
    Copy-Item -Path $OutPath -Destination $deliverPath -Force
    Write-Host "Delivery copy: $deliverPath" -ForegroundColor Green
}

Write-Host "Restart Roblox Studio, then check Manage Plugins / Open Panel"
