# Download Discord's detectable applications list for OBS GameFlow.
# Only downloads a local cache; the Lua script does not contact the network.
$ErrorActionPreference = "Stop"
$url = "https://discord.com/api/v9/applications/detectable"
$dest = Join-Path $PSScriptRoot "discord_games.json"
$temp = Join-Path $PSScriptRoot "discord_games.json.download"

try {
    Write-Host "Downloading Discord detectable applications..."
    Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 30
    $raw = [System.IO.File]::ReadAllText($temp, [System.Text.Encoding]::UTF8)
    if (-not $raw.TrimStart().StartsWith("[")) {
        throw "Unexpected response: expected a JSON array."
    }
    $parsed = ConvertFrom-Json -InputObject $raw
    if ($null -eq $parsed) { throw "Empty response." }
    Move-Item -LiteralPath $temp -Destination $dest -Force
    Write-Host "Saved $dest"
    Write-Host "In OBS, choose Reload databases to apply the update."
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}
