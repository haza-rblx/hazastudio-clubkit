# Wrapper: pakai Git portable di .tools/git (tanpa install system-wide)
$gitExe = Join-Path $PSScriptRoot ".tools\git\cmd\git.exe"
if (-not (Test-Path $gitExe)) {
    Write-Error "Git belum terpasang. Jalankan setup dari AGENTS.md atau minta agent install ulang."
    exit 1
}
& $gitExe @args
