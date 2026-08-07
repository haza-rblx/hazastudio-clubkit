# Dev hot-reload server for the Club Kit Studio plugin.
# Serves plugin/*.luau sources on http://127.0.0.1:8798 so the installed
# plugin's "Reload Panel" button can rebuild the UI in-session (no Studio restart).
#
# Usage:
#   .\tools\ClubKitPackagerPlugin\dev-serve.ps1            # foreground, Ctrl+C to stop
#   .\tools\ClubKitPackagerPlugin\dev-serve.ps1 -Port 8798
#
# Routes:
#   GET /health               -> "ok"
#   GET /modules.txt          -> newline-separated module names (no extension)
#   GET /source/<Name>.luau   -> raw Luau source
#
# Uses a raw TcpListener (NOT HttpListener) so no admin / netsh urlacl is needed.

param(
    [int]$Port = 8798,
    [string]$Root = (Join-Path $PSScriptRoot "plugin")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Root)) {
    Write-Error "Plugin source folder not found: $Root"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-ModuleNames {
    Get-ChildItem -Path $Root -Filter *.luau -File |
        Where-Object { $_.Name -ne "HazastudioClubKit.plugin.luau" } |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object
}

function Send-Response {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$Status,
        [string]$StatusText,
        [string]$Body
    )
    $bodyBytes = $utf8.GetBytes($Body)
    $head = "HTTP/1.1 $Status $StatusText`r`n" +
        "Content-Type: text/plain; charset=utf-8`r`n" +
        "Content-Length: $($bodyBytes.Length)`r`n" +
        "Cache-Control: no-store`r`n" +
        "Connection: close`r`n`r`n"
    $headBytes = $utf8.GetBytes($head)
    $Stream.Write($headBytes, 0, $headBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

function Handle-Request {
    param([System.Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $stream.ReadTimeout = 5000

    # Read headers until CRLFCRLF
    $buffer = New-Object byte[] 65536
    $request = ""
    while ($request -notmatch "`r`n`r`n") {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { return }
        $request += $utf8.GetString($buffer, 0, $read)
        if ($request.Length -gt 262144) { return }
    }

    $requestLine = ($request -split "`r`n")[0]
    if ($requestLine -notmatch "^GET\s+(\S+)\s+HTTP") { return }
    $path = [System.Uri]::UnescapeDataString($Matches[1])
    $path = $path.Split("?")[0]

    $stamp = Get-Date -Format "HH:mm:ss"

    if ($path -eq "/" -or $path -eq "/health") {
        Send-Response -Stream $stream -Status 200 -StatusText "OK" -Body "ok"
        Write-Host "[$stamp] GET $path -> 200"
        return
    }

    if ($path -eq "/modules.txt") {
        $names = Get-ModuleNames
        Send-Response -Stream $stream -Status 200 -StatusText "OK" -Body (($names -join "`n") + "`n")
        Write-Host "[$stamp] GET $path -> 200 ($($names.Count) modules)"
        return
    }

    if ($path -match "^/source/([\w_]+)(\.luau)?$") {
        $name = $Matches[1]
        $file = Join-Path $Root ($name + ".luau")
        if (Test-Path $file) {
            $body = [System.IO.File]::ReadAllText($file)
            Send-Response -Stream $stream -Status 200 -StatusText "OK" -Body $body
            Write-Host "[$stamp] GET $path -> 200 ($((Get-Item $file).Length) bytes)"
        } else {
            Send-Response -Stream $stream -Status 404 -StatusText "Not Found" -Body "not found: $name"
            Write-Host "[$stamp] GET $path -> 404"
        }
        return
    }

    Send-Response -Stream $stream -Status 404 -StatusText "Not Found" -Body "unknown route: $path"
    Write-Host "[$stamp] GET $path -> 404"
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse("127.0.0.1"), $Port)
try {
    $listener.Start()
} catch {
    Write-Error "Could not bind http://127.0.0.1:$Port - is another dev-serve already running? $($_.Exception.Message)"
}

Write-Host ""
Write-Host "  Club Kit dev server" -ForegroundColor Cyan
Write-Host "  Serving  : $Root"
Write-Host "  Listening: http://127.0.0.1:$Port"
Write-Host ""
Write-Host "  In Studio: Hazastudio Club Kit toolbar -> Reload Panel"
Write-Host "  Stop with Ctrl+C"
Write-Host ""

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            Handle-Request -Client $client
        } catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] request error: $($_.Exception.Message)"
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
