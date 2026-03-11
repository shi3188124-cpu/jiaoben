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

function Convert-ToInputList {
param(
[Parameter(Mandatory = $false)]$InputValue
)

if ($null -eq $InputValue) {
return @("text")
}

if ($InputValue -is [string]) {
$trimmed = $InputValue.Trim()
if ($trimmed) {
return @($trimmed)
}

return @("text")
}

$values = @($InputValue | ForEach-Object {
if ($null -eq $_) { return }
$text = [string]$_
if (-not [string]::IsNullOrWhiteSpace($text)) {
$text.Trim()
}
})

if ($values.Count -gt 0) {
return @($values)
}

return @("text")
}

function Get-OpenClawCommand {
$cmd = Get-Command "openclaw.cmd" -ErrorAction SilentlyContinue
if ($cmd) {
return $cmd.Source
}

$script = Get-Command "openclaw" -ErrorAction SilentlyContinue
if ($script) {
return $script.Source
}

return $null
}

function Invoke-OpenClaw {
param(
[Parameter(Mandatory = $true)][string[]]$Arguments
)

$commandPath = Get-OpenClawCommand
if (-not $commandPath) {
Write-Warning "openclaw command not found in PATH; skipping restart/status"
return
}

& $commandPath @Arguments
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
input = Convert-ToInputList -InputValue $Item.input
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

function Select-ModelsInteractive {
param(
[Parameter(Mandatory = $true)]$Models
)

$selected = New-Object 'System.Collections.Generic.HashSet[int]'
$cursor = 0
$rawUI = $Host.UI.RawUI

while ($true) {
Clear-Host
Write-Host "Available models:" -ForegroundColor Cyan
Write-Host "Use Up/Down to move, Space to select, Enter to confirm." -ForegroundColor DarkGray
Write-Host ""

for ($i = 0; $i -lt $Models.Count; $i++) {
$model = $Models[$i]
$marker = if ($selected.Contains($i)) { "[x]" } else { "[ ]" }
$pointer = if ($i -eq $cursor) { ">" } else { " " }
$reasoning = if ($model.reasoning) { "reasoning" } else { "no-reasoning" }
Write-Host ("{0} {1} {2} ({3}, ctx {4}, max {5})" -f $pointer, $marker, $model.id, $reasoning, $model.contextWindow, $model.maxTokens)
}

Write-Host ""
Write-Host ("Selected: {0}" -f $selected.Count)
$key = $rawUI.ReadKey("NoEcho,IncludeKeyDown")

switch ($key.VirtualKeyCode) {
13 {
if ($selected.Count -eq 0) {
Write-Host ""
Write-Host "Select at least one model before continuing." -ForegroundColor Yellow
Start-Sleep -Seconds 1
continue
}
break
}
38 {
if ($cursor -gt 0) { $cursor-- } else { $cursor = $Models.Count - 1 }
continue
}
40 {
if ($cursor -lt ($Models.Count - 1)) { $cursor++ } else { $cursor = 0 }
continue
}
32 {
if ($selected.Contains($cursor)) {
$selected.Remove($cursor) | Out-Null
}
else {
$selected.Add($cursor) | Out-Null
}
continue
}
default {
continue
}
}
}

return @($selected | Sort-Object)
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

$selectedIndexes = Select-ModelsInteractive -Models $models
$selectedModels = @($selectedIndexes | ForEach-Object { $models[$_] })

Clear-Host
Write-Host "Selected models:" -ForegroundColor Cyan
for ($i = 0; $i -lt $selectedModels.Count; $i++) {
Write-Host ("[{0}] {1}" -f ($i + 1), $selectedModels[$i].id)
}

Write-Host ""
$defaultChoice = Read-Host "Choose ONE default model number from the selected list"
$parsedDefault = 0
if (-not [int]::TryParse($defaultChoice, [ref]$parsedDefault)) {
throw "Invalid default selection"
}

$defaultIndex = $parsedDefault - 1
if ($defaultIndex -lt 0 -or $defaultIndex -ge $selectedModels.Count) {
throw "Default selection out of range"
}

$DefaultModel = $selectedModels[$defaultIndex]
$FullModel = "$ProviderId/$($DefaultModel.id)"

$json = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Ensure-ObjectProperty -Object $json -Name "auth" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.auth -Name "profiles" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json -Name "models" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.models -Name "providers" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json -Name "agents" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents -Name "defaults" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents.defaults -Name "model" -Value ([pscustomobject]@{})

$profileName = "$ProviderId`:default"
$json.auth.profiles | Add-Member -Force -NotePropertyName $profileName -NotePropertyValue ([pscustomobject]@{
provider = $ProviderId
mode = "api_key"
})

$backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Path $ConfigPath -Destination $backupPath -Force

$provider = [pscustomobject]@{
baseUrl = $BaseUrl
apiKey = $ApiKey
api = "openai-completions"
models = @($selectedModels)
}

$json.models.providers | Add-Member -Force -NotePropertyName $ProviderId -NotePropertyValue $provider
$json.agents.defaults.model.primary = $FullModel

$json | ConvertTo-Json -Depth 100 | Set-Content -Path $ConfigPath -Encoding UTF8

$writtenJson = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$writtenModels = @($writtenJson.models.providers.$ProviderId.models)
if ($writtenModels.Count -eq 0) {
throw "Provider '$ProviderId' has no models after write"
}

foreach ($writtenModel in $writtenModels) {
if ($writtenModel.input -is [string]) {
throw "Provider '$ProviderId' model '$($writtenModel.id)' has invalid input type after write; expected array, got string"
}
if (@($writtenModel.input).Count -eq 0) {
throw "Provider '$ProviderId' model '$($writtenModel.id)' is missing input values after write"
}
}

Write-Host ""
Write-Host "OpenClaw config updated"
Write-Host "Base URL: $BaseUrl"
Write-Host "Selected models: $($selectedModels.id -join ', ')"
Write-Host "Default model: $FullModel"
Write-Host "Config file: $ConfigPath"
Write-Host "Backup file: $backupPath"
Write-Host ""

Invoke-OpenClaw -Arguments @("gateway", "restart")
Start-Sleep -Seconds 2
Invoke-OpenClaw -Arguments @("status")
