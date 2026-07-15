# Count top-level `local` declarations (Luau ~200 register budget per function/chunk).
# Usage (from repo root):
#   .\tools\count-locals.ps1
#   .\tools\count-locals.ps1 -FailAt 185
#   .\tools\count-locals.ps1 -Path src\...\Main.client.luau

param(
	[string[]]$Path,
	[int]$FailAt = 0,
	[int]$WarnAt = 170
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$defaultPaths = @(
	"src\StarterPlayerScripts\StarterPlayerScripts\Hazastudio_ClubKit\Main.client.luau",
	"src\ServerScriptService\Hazastudio_ClubKit\Server\Main.server.luau",
	"src\StarterPlayerScripts\StarterPlayerScripts\Hazastudio_ClubKit\Client\UI\MusicPlayerUIBinder.luau",
	"src\StarterPlayerScripts\StarterPlayerScripts\Hazastudio_ClubKit\Client\UI\MusicPlayerUIBinderPart2.luau",
	"src\StarterPlayerScripts\StarterPlayerScripts\Hazastudio_ClubKit\Client\Init\ClientModuleBag.luau",
	"src\ServerScriptService\Hazastudio_ClubKit\Server\Init\ServerModuleBag.luau"
)

$targets = if ($Path -and $Path.Count -gt 0) { $Path } else { $defaultPaths }
$failed = $false

foreach ($rel in $targets) {
	$full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $root $rel }
	if (-not (Test-Path -LiteralPath $full)) {
		Write-Host "MISSING  $rel"
		continue
	}
	$count = @(Select-String -LiteralPath $full -Pattern '^local\s+').Count
	$tag = "OK"
	if ($FailAt -gt 0 -and $count -ge $FailAt) {
		$tag = "FAIL"
		$failed = $true
	} elseif ($count -ge $WarnAt) {
		$tag = "WARN"
	}
	Write-Host ("{0,-4} {1,3}  {2}" -f $tag, $count, $rel)
}

Write-Host ""
Write-Host "Luau top-level local budget ~200. Prefer Init bags / helper modules before adding requires to Main."
if ($failed) {
	exit 1
}
