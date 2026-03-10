$ErrorActionPreference = "Stop"

$ConfigPath = "$HOME\.openclaw\openclaw.json"
$BaseUrl = "http://122.51.82.68:8059/v1"
$ProviderId = "szy"
$ModelId = "gpt-5.4"
$FullModel = "$ProviderId/$ModelId"

$SecureApiKey = Read-Host "Enter API Key" -AsSecureString
$ApiKey = [System.Net.NetworkCredential]::new("", $SecureApiKey).Password

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API Key cannot be empty"
}

if (!(Test-Path $ConfigPath)) {
    throw "OpenClaw config file not found: $ConfigPath"
}

$json = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (-not $json.models) {
    $json | Add-Member -NotePropertyName models -NotePropertyValue ([pscustomobject]@{})
}
if (-not $json.models.providers) {
    $json.models | Add-Member -NotePropertyName providers -NotePropertyValue ([pscustomobject]@{})
}
if (-not $json.agents) {
    $json | Add-Member -NotePropertyName agents -NotePropertyValue ([pscustomobject]@{})
}
if (-not $json.agents.defaults) {
    $json.agents | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
}
if (-not $json.agents.defaults.model) {
    $json.agents.defaults | Add-Member -NotePropertyName model -NotePropertyValue ([pscustomobject]@{})
}

$provider = [pscustomobject]@{
    baseUrl = $BaseUrl
    apiKey  = $ApiKey
    api     = "openai-completions"
    models  = @(
        [pscustomobject]@{
            id            = $ModelId
            name          = "GPT-5.4"
            reasoning     = $true
            input         = @("text")
            cost          = [pscustomobject]@{
                input      = 0
                output     = 0
                cacheRead  = 0
                cacheWrite = 0
            }
            contextWindow = 128000
            maxTokens     = 32768
        }
    )
}

$json.models.providers | Add-Member -Force -NotePropertyName $ProviderId -NotePropertyValue $provider
$json.agents.defaults.model.primary = $FullModel

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $ConfigPath -Encoding UTF8

Write-Host ""
Write-Host "OpenClaw config updated"
Write-Host "Base URL: $BaseUrl"
Write-Host "Default model: $FullModel"
Write-Host "Config file: $ConfigPath"
Write-Host ""

openclaw gateway restart
Start-Sleep -Seconds 2
openclaw status
