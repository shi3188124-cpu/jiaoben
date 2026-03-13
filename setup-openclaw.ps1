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
elseif ($null -eq $Object.$Name) {
$Object.$Name = $Value
}
}

function Normalize-ModelItem {
param(
[Parameter(Mandatory = $true)]$Item
)

$cost = $Item.cost
if ($null -eq $cost) {
$cost = [pscustomobject]@{}
}

$contextWindow = $null
if ($Item.PSObject.Properties.Name -contains 'contextWindow') {
$contextWindow = $Item.contextWindow
}
elseif ($Item.PSObject.Properties.Name -contains 'context_window') {
$contextWindow = $Item.context_window
}

$maxTokens = $null
if ($Item.PSObject.Properties.Name -contains 'maxTokens') {
$maxTokens = $Item.maxTokens
}
elseif ($Item.PSObject.Properties.Name -contains 'max_tokens') {
$maxTokens = $Item.max_tokens
}

[pscustomobject]@{
id = [string]$Item.id
name = if ($Item.name) { [string]$Item.name } else { [string]$Item.id }
reasoning = if ($Item.PSObject.Properties.Name -contains 'reasoning') { [bool]$Item.reasoning } else { $true }
input = if ($Item.input) {
if ($Item.input -is [System.Collections.IEnumerable] -and -not ($Item.input -is [string])) {
@($Item.input | ForEach-Object { [string]$_ })
}
else {
@([string]$Item.input)
}
}
else {
@("text")
}
cost = [pscustomobject]@{
input = if ($cost.PSObject.Properties.Name -contains 'input') { $cost.input } else { 0 }
output = if ($cost.PSObject.Properties.Name -contains 'output') { $cost.output } else { 0 }
cacheRead = if ($cost.PSObject.Properties.Name -contains 'cacheRead') { $cost.cacheRead } else { 0 }
cacheWrite = if ($cost.PSObject.Properties.Name -contains 'cacheWrite') { $cost.cacheWrite } else { 0 }
}
contextWindow = if ($contextWindow) { $contextWindow } else { 128000 }
maxTokens = if ($maxTokens) { $maxTokens } else { 32768 }
}
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

function Get-PythonCommand {
$python = Get-Command "python" -ErrorAction SilentlyContinue
if ($python) {
return @($python.Source)
}

$py = Get-Command "py" -ErrorAction SilentlyContinue
if ($py) {
return @($py.Source, "-3")
}

return $null
}

function Invoke-OpenClaw {
param(
[Parameter(Mandatory = $true)][string[]]$Arguments
)

$commandPath = Get-OpenClawCommand
if (-not $commandPath) {
Write-Warning "openclaw command not found in PATH; skipping restart"
return
}

& $commandPath @Arguments
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

if ($null -eq $response) {
throw "Model API returned an empty response"
}

$items = $null
if ($response -is [System.Collections.IEnumerable] -and -not ($response -is [string])) {
$items = @($response)
}
elseif ($response.PSObject.Properties.Name -contains 'data') {
$items = @($response.data)
}
elseif ($response.PSObject.Properties.Name -contains 'models') {
$items = @($response.models)
}
else {
throw "Unrecognized model response format"
}

$normalized = @()
$seen = New-Object System.Collections.Generic.HashSet[string]

foreach ($item in $items) {
if (-not $item.id) { continue }
$model = Normalize-ModelItem -Item $item
if ($seen.Add($model.id)) {
$normalized += $model
}
}

if ($normalized.Count -eq 0) {
throw "No models were returned by the API"
}

return @($normalized | Sort-Object id)
}

function Select-ModelsInteractive {
param(
[Parameter(Mandatory = $true)]$Models
)

$cursor = 0
$selected = New-Object System.Collections.Generic.HashSet[int]
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
return @($selected | Sort-Object)
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
}

function Select-DefaultModelInteractive {
param(
[Parameter(Mandatory = $true)]$Models,
[Parameter(Mandatory = $false)][string]$CurrentDefault
)

$options = @(
[pscustomobject]@{ label = "Keep current default model"; value = $null }
) + @($Models | ForEach-Object {
[pscustomobject]@{ label = $_.id; value = $_.id }
})

$cursor = 0
$selected = 0
$rawUI = $Host.UI.RawUI

if ($CurrentDefault) {
$normalizedCurrent = $CurrentDefault
if ($normalizedCurrent.StartsWith("$ProviderId/")) {
$normalizedCurrent = $normalizedCurrent.Substring($ProviderId.Length + 1)
}

for ($i = 1; $i -lt $options.Count; $i++) {
if ($options[$i].value -eq $normalizedCurrent) {
$selected = $i
$cursor = $i
break
}
}
}

while ($true) {
Clear-Host
Write-Host "Choose default model:" -ForegroundColor Cyan
Write-Host "Use Up/Down to move, Space to select, Enter to confirm." -ForegroundColor DarkGray
if ($CurrentDefault) {
Write-Host ("Current default: {0}" -f $CurrentDefault) -ForegroundColor DarkGray
}
else {
Write-Host "Current default: (not set)" -ForegroundColor DarkGray
}
Write-Host ""

for ($i = 0; $i -lt $options.Count; $i++) {
$pointer = if ($i -eq $cursor) { ">" } else { " " }
$marker = if ($i -eq $selected) { "(*)" } else { "( )" }
Write-Host ("{0} {1} {2}" -f $pointer, $marker, $options[$i].label)
}

$key = $rawUI.ReadKey("NoEcho,IncludeKeyDown")

switch ($key.VirtualKeyCode) {
13 {
return $options[$selected].value
}
38 {
if ($cursor -gt 0) { $cursor-- } else { $cursor = $options.Count - 1 }
continue
}
40 {
if ($cursor -lt ($options.Count - 1)) { $cursor++ } else { $cursor = 0 }
continue
}
32 {
$selected = $cursor
continue
}
default {
continue
}
}
}
}

$pythonCommand = Get-PythonCommand
if (-not $pythonCommand) {
throw "python or py launcher not found. Please install Python 3 first."
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
$selectedModelIds = @($selectedModels | ForEach-Object { $_.id })

$json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
Ensure-ObjectProperty -Object $json -Name "agents" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents -Name "defaults" -Value ([pscustomobject]@{})
Ensure-ObjectProperty -Object $json.agents.defaults -Name "model" -Value ([pscustomobject]@{})

$currentDefault = $null
if ($json.agents.defaults.model.PSObject.Properties.Name -contains 'primary') {
$currentDefault = [string]$json.agents.defaults.model.primary
}

$selectedDefaultId = Select-DefaultModelInteractive -Models $selectedModels -CurrentDefault $currentDefault

$idsPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$pyPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + '.py')

try {
Set-Content -Path $idsPath -Value ($selectedModelIds -join [Environment]::NewLine) -Encoding UTF8

$pythonScript = @'
import json
import os
import urllib.request
from datetime import datetime

config_path = os.environ["OC_CONFIG_PATH"]
base_url = os.environ["OC_BASE_URL"].rstrip("/")
provider_id = os.environ["OC_PROVIDER_ID"]
api_key = os.environ["OC_API_KEY"]
selected_ids_path = os.environ["OC_SELECTED_IDS_FILE"]
default_id = os.environ.get("OC_DEFAULT_ID") or None

with open(selected_ids_path, "r", encoding="utf-8-sig") as f:
selected_ids = [line.lstrip("\ufeff").strip() for line in f if line.strip()]

default_id = default_id.lstrip("\ufeff").strip() if default_id else None

if not selected_ids:
raise SystemExit("No models selected")

def normalize_input(value):
if value is None:
return ["text"]
if isinstance(value, str):
value = value.strip()
return [value] if value else ["text"]
if isinstance(value, list):
normalized = [str(item).strip() for item in value if str(item).strip()]
return normalized or ["text"]
text = str(value).strip()
return [text] if text else ["text"]

req = urllib.request.Request(
f"{base_url}/models",
headers={"Authorization": f"Bearer {api_key}"},
)

try:
with urllib.request.urlopen(req, timeout=30) as resp:
payload = json.loads(resp.read().decode("utf-8"))
except Exception as e:
raise SystemExit(f"Failed to refetch model list: {e}")

if isinstance(payload, dict) and "data" in payload:
items = payload["data"]
elif isinstance(payload, dict) and "models" in payload:
items = payload["models"]
elif isinstance(payload, list):
items = payload
else:
raise SystemExit("Unrecognized model response format")

index = {}
for item in items:
model_id = item.get("id")
if not model_id:
continue
cost = item.get("cost") or {}
index[model_id] = {
"id": model_id,
"name": item.get("name") or model_id,
"reasoning": bool(item.get("reasoning", True)),
"input": normalize_input(item.get("input")),
"cost": {
"input": cost.get("input", 0),
"output": cost.get("output", 0),
"cacheRead": cost.get("cacheRead", 0),
"cacheWrite": cost.get("cacheWrite", 0),
},
"contextWindow": item.get("contextWindow") or item.get("context_window") or 128000,
"maxTokens": item.get("maxTokens") or item.get("max_tokens") or 32768,
}

selected_models = []
for model_id in selected_ids:
lookup_id = model_id
if lookup_id not in index and provider_id and not lookup_id.startswith(f"{provider_id}/"):
prefixed = f"{provider_id}/{lookup_id}"
if prefixed in index:
lookup_id = prefixed
if lookup_id not in index:
suffix_matches = [candidate for candidate in index.keys() if candidate == model_id or candidate.endswith("/" + model_id)]
if len(suffix_matches) == 1:
lookup_id = suffix_matches[0]
if lookup_id not in index:
raise SystemExit(f"Selected model not found in API response: {model_id}")
selected_models.append(index[lookup_id])

with open(config_path, "r", encoding="utf-8") as f:
data = json.load(f)

backup_path = f"{config_path}.bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
with open(backup_path, "w", encoding="utf-8") as f:
json.dump(data, f, ensure_ascii=False, indent=2)

data.setdefault("auth", {})
data["auth"].setdefault("profiles", {})
data.setdefault("models", {})
data["models"].setdefault("providers", {})
data.setdefault("agents", {})
data["agents"].setdefault("defaults", {})
data["agents"]["defaults"].setdefault("model", {})

data["auth"]["profiles"][f"{provider_id}:default"] = {
"provider": provider_id,
"mode": "api_key",
}

data["models"]["providers"][provider_id] = {
"baseUrl": base_url,
"apiKey": api_key,
"api": "openai-completions",
"models": selected_models,
}

if default_id:
data["agents"]["defaults"]["model"]["primary"] = f"{provider_id}/{default_id}"

with open(config_path, "w", encoding="utf-8") as f:
json.dump(data, f, ensure_ascii=False, indent=2)

with open(config_path, "r", encoding="utf-8") as f:
written = json.load(f)

written_models = ((((written.get("models") or {}).get("providers") or {}).get(provider_id) or {}).get("models")) or []
if not written_models:
raise SystemExit(f"Provider '{provider_id}' has no models after write")

for model in written_models:
model_input = model.get("input")
if not isinstance(model_input, list) or not model_input:
raise SystemExit(
f"Provider '{provider_id}' model '{model.get('id')}' has invalid input after write; expected non-empty array"
)

print()
print("OpenClaw config updated")
print(f"Base URL: {base_url}")
print(f"Selected models: {', '.join(m['id'] for m in selected_models)}")
if default_id:
print(f"Default model: {provider_id}/{default_id}")
else:
print("Default model: kept existing value")
print(f"Config file: {config_path}")
print(f"Backup file: {backup_path}")
'@

Set-Content -Path $pyPath -Value $pythonScript -Encoding UTF8

$env:OC_CONFIG_PATH = $ConfigPath
$env:OC_BASE_URL = $BaseUrl
$env:OC_PROVIDER_ID = $ProviderId
$env:OC_API_KEY = $ApiKey
$env:OC_SELECTED_IDS_FILE = $idsPath
$env:OC_DEFAULT_ID = if ($selectedDefaultId) { $selectedDefaultId } else { "" }

if ($pythonCommand -is [string]) {
& $pythonCommand $pyPath
}
else {
& $pythonCommand[0] @($pythonCommand[1..($pythonCommand.Count - 1)]) $pyPath
}

if ($LASTEXITCODE -ne 0) {
throw "Python writer failed"
}
}
finally {
if (Test-Path $idsPath) { Remove-Item $idsPath -Force }
if (Test-Path $pyPath) { Remove-Item $pyPath -Force }
Remove-Item Env:OC_CONFIG_PATH -ErrorAction SilentlyContinue
Remove-Item Env:OC_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:OC_PROVIDER_ID -ErrorAction SilentlyContinue
Remove-Item Env:OC_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:OC_SELECTED_IDS_FILE -ErrorAction SilentlyContinue
Remove-Item Env:OC_DEFAULT_ID -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Requesting gateway restart..."
Invoke-OpenClaw -Arguments @("gateway", "restart")
