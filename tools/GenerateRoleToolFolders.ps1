# Generate empty Role Tool folders (Rojo / ServerStorage.Tools)
#
# Membaca toolFolder dari ClubKitConfig + membership tier defaults,
# lalu membuat folder kosong dengan init.meta.json (tanpa placeholder Tool).
#
# Usage (dari root repo):
#   powershell -File tools/GenerateRoleToolFolders.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "src\ReplicatedStorage\Hazastudio_ClubKitConfig\ClubKitConfig.luau"
$toolsRoot = Join-Path $root "src\ServerStorage\Tools"
$metaContent = @"
{
  `"className`": `"Folder`"
}
"@

if (-not (Test-Path $configPath)) {
    Write-Error "ClubKitConfig tidak ditemukan: $configPath"
}

$config = Get-Content $configPath -Raw
$folderNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Add-Folder([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $trimmed = $name.Trim()
    if ($trimmed -eq "" -or $trimmed -eq "GUEST") { return }
    [void]$folderNames.Add($trimmed.ToUpper())
}

# toolFolder = "..." pada RoleCategories
foreach ($m in [regex]::Matches($config, 'toolFolder\s*=\s*"([^"]+)"')) {
    Add-Folder $m.Groups[1].Value
}

# ToolFolder = "..." pada SpenderRoles
foreach ($m in [regex]::Matches($config, 'ToolFolder\s*=\s*"([^"]+)"')) {
    Add-Folder $m.Groups[1].Value
}

# chatTag Owner (SystemRoles.Owner tidak punya toolFolder)
if ($config -match 'Owner\s*=\s*\{[^}]*chatTag\s*=\s*"([^"]+)"') {
    Add-Folder $matches[1]
}

# Membership tier folders (sama seperti RolesDomain.buildMembershipToolFolders)
Add-Folder "VIP"
Add-Folder "VVIP"
Add-Folder "SUPREME"

# Archive bucket (bukan role — untuk folder obsolete)
[void]$folderNames.Add("_ARCHIVE")

$ordered = $folderNames | Sort-Object
Write-Host "=== GenerateRoleToolFolders ==="
Write-Host ("Target: {0}" -f $toolsRoot)
Write-Host ("Folders: {0}" -f $ordered.Count)

New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null

# Tools root meta
Set-Content -Path (Join-Path $toolsRoot "init.meta.json") -Value $metaContent -NoNewline
Add-Content -Path (Join-Path $toolsRoot "init.meta.json") -Value ""

$created = 0
$existing = 0

foreach ($name in $ordered) {
    $displayName = if ($name -eq "_ARCHIVE") { "_Archive" } else { $name }
    $dir = Join-Path $toolsRoot $displayName
    $wasNew = -not (Test-Path $dir)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path (Join-Path $dir "init.meta.json") -Value $metaContent -NoNewline
    Add-Content -Path (Join-Path $dir "init.meta.json") -Value ""
    if ($wasNew) {
        $created++
        Write-Host ("  [CREATE] {0}" -f $displayName)
    } else {
        $existing++
        Write-Host ("  [OK] {0}" -f $displayName)
    }
}

Write-Host ""
Write-Host ("Selesai. Created: {0} | Already existed: {1}" -f $created, $existing)
Write-Host "Sync Rojo → ServerStorage.Tools muncul di Studio (folder kosong, tanpa Tool)."
