# Hazastudio Club Kit - delivery prep checklist (run from repo root).
# Packaging itself is done in Studio (Packager tab). This script validates repo + prints steps.

param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$versionPath = Join-Path $root "VERSION"
if (-not (Test-Path $versionPath)) {
    Write-Error "VERSION file missing."
}
$kitVersion = if ($Version) { $Version.Trim() } else { (Get-Content $versionPath -Raw).Trim() }

Write-Host ""
Write-Host "=== Club Kit delivery prep ===" -ForegroundColor Cyan
Write-Host "Kit version: $kitVersion"
Write-Host ""

Write-Host "Deliverables (Workspace models):" -ForegroundColor Yellow
Write-Host "  1. HazastudioClubKit_Package      (full place, NO SyncBhms)"
Write-Host "  2. HazastudioClubKit_SyncBhmsAddon   (BHMS dance pack, optional)"
Write-Host ""

Write-Host "Before Studio pack:" -ForegroundColor Yellow
Write-Host "  [ ] DUPLICATE dev place (File Save As) - do not pack live dev place"
Write-Host "  [ ] In duplicate: remove DanceGui, SyncBhmsGate, SyncBhmsAcmBridge, SyncBhmsRemotes"
Write-Host "  [ ] LegacySyncBhms = false in ClubKitConfig"
Write-Host "  [ ] Main duplicate: GroupId = 0, blank template config"
Write-Host "  [ ] Update Engine to v$kitVersion"
Write-Host "  [ ] Rebuild plugin: .\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1"
Write-Host ""

Write-Host "In Studio (Seller mode -> Packager):" -ForegroundColor Yellow
Write-Host "  [ ] Main template pack -> Create package -> Workspace/HazastudioClubKit_Package"
Write-Host "  [ ] SyncBhms add-on -> Create SyncBhms add-on -> Workspace/HazastudioClubKit_SyncBhmsAddon"
Write-Host ""

Write-Host "  Plugin RBXM: .\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1 -CopyToDeliver"
Write-Host "               -> deliver/HazastudioClubKitPackager_v$kitVersion.rbxm"
Write-Host ""
Write-Host "Docs: docs/delivery/TEMPLATE_PLACE.md + docs/delivery/PLUGIN.md"
Write-Host ""

$outDir = Join-Path $root "deliver"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
    Write-Host "Created deliver/ folder for RBXM output copies." -ForegroundColor Green
} else {
    Write-Host "deliver/ folder exists - optional notes only; packs live in Workspace."
}
