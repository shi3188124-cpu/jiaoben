待选
Copy as markdown
好，直接给你。
你把下面两份分别粘到 GitHub 对应文件里就行。
￼
1) Windows 版：setup-openclaw.ps1
$ErrorActionPreference = "Stop"

$ConfigPath = "$HOME\.openclaw\openclaw.json"
$BaseUrl = "http://122.51.82.68:8059/v1"
$ProviderId = "szy"

function Ensure-ObjectProperty {
param(
[Parameter(Mandatory = $true)]$Object,
[Parameter(Mandatory = $true)][string]$Name,
[Parameter(Mandatory = $true)]$Value
)

if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
$Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}
}

function Convert-ToProviderModel {
param(
[Parameter(Mandatory = $true)]$Item
)

$cost = [pscustomobject]@{
input = 0
output = 0
cacheRead = 0
cacheWrite = 0
}

if ($Item.cost) {
$cost = [pscustomobject]@{
input = if ($null -ne $Item.cost.input) { $Item.cost.input } else { 0 }
output = if ($null -ne $Item.cost.output) { $Item.cost.output } else { 0 }
cacheRead = if ($null -ne $Item.cost.cacheRead) { $Item.cost.cacheRead } else { 0 }
cacheWrite = if ($null -ne $Item.cost.cacheWrite) { $Item.cost.cacheWrite } else { 0 }
}
}

return [pscustomobject]@{
id = $Item.id
name = if ($Item.name) { $Item.name } else { $Item.id }
reasoning = if ($null -ne $Item.reasoning) { [bool]$Item.reasoning } else { $true }
input = if ($Item.input) { @($Item.input) } else { @("text") }
cost = $cost
contextWindow = if ($Item.contextWindow) { $Item.contextWindow } elseif ($Item.context_window) { $Item.context_window } else { 128000 }
maxTokens = if ($Item.maxTokens) { $Item.maxTokens } elseif ($Item.max_tokens) { $Item.max_tokens } else { 32768 }
}
}

function Get-ModelList {
param(
[Parameter(Mandatory = $true)][string]$BaseUrl,
[Parameter(Mandatory = $true)][string]$ApiKey
)

$headers = @{ Authorization = "Bearer $ApiKey" }
$uri = "$BaseUrl/models"

try {
$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
}
catch {
throw "Failed to fetch model list from ${uri}: $($_.Exception.Message)"
}

if (-not $response) {
throw "Model API returned an empty response"
}

$items = @()
if ($response.data) {
$items = @($response.data)
}
elseif ($response.models) {
$items = @($response.models)
}
elseif ($response -is [System.Array]) {
$items = @($response)
}
else {
throw "Unrecognized model response format"
}

$models = foreach ($item in $items) {
if ([string]::IsNullOrWhiteSpace($item.id)) { continue }
Convert-ToProviderModel -Item $item
}

$models = @($models | Sort-Object id -Unique)

if ($models.Count -eq 0) {
throw "No models were returned by the API"
}

return $models
}

$SecureApiKey = Read-Host "Enter API Key" -AsSecureString
$ApiKey = [System.Net.NetworkCredential]::new("", $SecureApiKey).Password

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
throw "API Key cannot be empty"
}

if (!(Test-Path $ConfigPath)) {
throw "OpenClaw config file not found: $ConfigPath"
}

Write-Host ""
Write-Host "Fetching models from: $BaseUrl"
$models = Get-ModelList -BaseUrl $BaseUrl -ApiKey $ApiKey

Write-Host ""
Write-Host "Available models:"
for ($i = 0; $i -lt $models.Count; $i++) {
$m = $models[$i]
$reasoning = if ($m.reasoning) { "reasoning" } else { "no-reasoning" }
Write-Host (("[{0}] {1} ({2}, ctx {3}, max {4})" -f ($i + 1), $m.id, $reasoning, $m.contextWindow, $m.maxTokens))
}

Write-Host ""
$choice = Read-Host "Select model number"
$parsedChoice = 0
if (-not [int]::TryParse($choice, [ref]$parsedChoice)) {
throw "Invalid selection: please enter a number"
}

$selectedIndex = $parsedChoice - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $models.Count) {
throw "Selection out of range"
}

$SelectedModel = $models[$selectedIndex]
$FullModel = "$ProviderId/$($SelectedModel.id)"

$json = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Ensure-ObjectProperty -Object $json -Name "models" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.models -Name "providers" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json -Name "agents" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents -Name "defaults" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents.defaults -Name "model" -Value ([pscustomobject]@{})

$backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Path $ConfigPath -Destination $backupPath -Force

$provider = [pscustomobject]@{
baseUrl = $BaseUrl
apiKey = $ApiKey
api = "openai-completions"
models = @($models)
}

$json.models.providers | Add-Member -Force -NotePropertyName $ProviderId -NotePropertyValue $provider
$json.agents.defaults.model.primary = $FullModel

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $ConfigPath -Encoding UTF8

Write-Host ""
Write-Host "OpenClaw config updated"
Write-Host "Base URL: $BaseUrl"
Write-Host "Selected model: $FullModel"
Write-Host "Config file: $ConfigPath"
Write-Host "Backup file: $backupPath"
Write-Host ""

openclaw gateway restart
Start-Sleep -Seconds 2
openclaw status
