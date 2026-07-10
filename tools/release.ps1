# Hazastudio Club Kit - release helper (git tag + push from Cursor).
# Usage:
#   .\tools\release.ps1                    # dry-run / validate only
#   .\tools\release.ps1 -Execute             # commit (if dirty), tag, push main + tag
#   .\tools\release.ps1 -Tag v2.1.0 -Execute
#   .\tools\release.ps1 -Execute -GhRelease  # also gh release create (notes-only)

param(
    [string]$Tag = "",
    [switch]$Execute,
    [switch]$GhRelease,
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$git = Join-Path $root "git.ps1"
if (-not (Test-Path $git)) {
    Write-Error "git.ps1 not found at repo root."
}

function Read-VersionFile {
    $versionPath = Join-Path $root "VERSION"
    if (-not (Test-Path $versionPath)) {
        throw "VERSION file missing."
    }
    $v = (Get-Content $versionPath -Raw).Trim()
    if ($v -notmatch '^\d+\.\d+\.\d+$') {
        throw "VERSION must be semver (got: $v)"
    }
    return $v
}

function Read-KitProductVersion {
    $kitProduct = Join-Path $root "src\ReplicatedStorage\Hazastudio_ClubKit\KitProduct.luau"
    if (-not (Test-Path $kitProduct)) {
        throw "KitProduct.luau missing."
    }
    $content = Get-Content $kitProduct -Raw
    if ($content -match 'KitVersion\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    throw "KitVersion not found in KitProduct.luau"
}

function Read-ManifestVersion {
    $manifest = Join-Path $root "tools\ClubKitPackagerPlugin\ClubKitManifest.luau"
    if (-not (Test-Path $manifest)) {
        throw "ClubKitManifest.luau missing."
    }
    $content = Get-Content $manifest -Raw
    if ($content -match 'KIT_VERSION\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    throw "KIT_VERSION not found in ClubKitManifest.luau"
}

$version = Read-VersionFile
$kitVersion = Read-KitProductVersion
$manifestVersion = Read-ManifestVersion

Write-Host "=== Club Kit Release ===" -ForegroundColor Cyan
Write-Host "VERSION:           $version"
Write-Host "KitProduct:        $kitVersion"
Write-Host "ClubKitManifest:   $manifestVersion"

if ($kitVersion -ne $version -or $manifestVersion -ne $version) {
    Write-Error "Version mismatch. Sync VERSION, KitProduct.KitVersion, and ClubKitManifest.KIT_VERSION before release."
}

if (-not $Tag) {
    $Tag = "v$version"
}
if ($Tag -notmatch '^v\d+\.\d+\.\d+$') {
    Write-Error "Tag must look like vX.Y.Z (got: $Tag)"
}

$tagVersion = $Tag.TrimStart('v')
if ($tagVersion -ne $version) {
    Write-Error "Tag $Tag does not match VERSION $version"
}

Write-Host "Tag:               $Tag" -ForegroundColor Green
Write-Host "Plugin will detect: v$version after push" -ForegroundColor Green

$status = & $git status --porcelain
if ($status) {
    Write-Host "`nUncommitted changes:" -ForegroundColor Yellow
    $status | ForEach-Object { Write-Host "  $_" }
    if (-not $Execute) {
        Write-Host "`nDry-run only. Re-run with -Execute to commit, tag, and push." -ForegroundColor Yellow
        exit 0
    }
    if (-not $Message) {
        $Message = "release: $Tag"
    }
    Write-Host "Committing: $Message"
    & $git add -A
    & $git commit -m $Message
} elseif (-not $Execute) {
    Write-Host "`nWorking tree clean. Dry-run only - re-run with -Execute to tag and push." -ForegroundColor Yellow
    exit 0
}

if (-not $Execute) {
    exit 0
}

$existingTag = & $git tag -l $Tag
if ($existingTag) {
    Write-Error "Tag $Tag already exists locally. Delete or pick a new version."
}

Write-Host "Creating tag $Tag ..."
& $git tag $Tag

Write-Host "Pushing main ..."
& $git push origin main

Write-Host "Pushing tag $Tag ..."
& $git push origin $Tag

if ($GhRelease) {
    $notesFile = Join-Path $root "CHANGELOG.md"
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host "Creating GitHub release (notes-only) ..."
        gh release create $Tag --notes-file $notesFile
    } else {
        Write-Warning "gh CLI not found - skip GitHub release. Tag push is enough for plugin source sync."
    }
}

Write-Host "`nDone. Studio plugin can Check Update -> v$version" -ForegroundColor Green
