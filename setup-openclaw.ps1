$ConfigPath = "$HOME\.openclaw\openclaw.json"
$BaseUrl = "http://122.51.82.68:8059/v1"
$ProviderId = "szy"
$ModelId = "gpt-5.4"
$FullModel = "$ProviderId/$ModelId"

$SecureApiKey = Read-Host "请输入 API Key" -AsSecureString
$ApiKey = [System.Net.NetworkCredential]::new("", $SecureApiKey).Password

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API Key 不能为空"
}

if (!(Test-Path $ConfigPath)) {
    throw "找不到 OpenClaw 配置文件: $ConfigPath"
}

$json = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 100

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
Write-Host "✅ OpenClaw 配置已更新"
Write-Host "🤖 默认模型: $FullModel"
Write-Host "📄 配置文件: $ConfigPath"
Write-Host ""

openclaw gateway restart
Start-Sleep -Seconds 2
openclaw status
