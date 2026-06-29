param(
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$node = "C:\Program Files\nodejs\node.exe"
$proxyScript = Join-Path $PSScriptRoot "local_usb_proxy.js"
$buildDirectory = Join-Path $projectRoot "build"
$pidFile = Join-Path $buildDirectory "local-usb-proxy.pid"
$stdoutLog = Join-Path $buildDirectory "local-usb-proxy.log"
$stderrLog = Join-Path $buildDirectory "local-usb-proxy-error.log"

foreach ($requiredFile in @($adb, $node, $proxyScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Arquivo obrigatorio nao encontrado: $requiredFile"
    }
}

try {
    $health = Invoke-RestMethod `
        -Uri "http://127.0.0.1:18000/plants/health" `
        -TimeoutSec 15
} catch {
    throw "A API Docker nao responde em 127.0.0.1:18000. Execute 'docker compose up -d --build' na pasta api."
}
if (-not $health.model_loaded) {
    throw "A API iniciou, mas o modelo de reconhecimento nao foi carregado."
}

New-Item -ItemType Directory -Force $buildDirectory | Out-Null
$listener = Get-NetTCPConnection `
    -LocalAddress "127.0.0.1" `
    -LocalPort 8000 `
    -State Listen `
    -ErrorAction SilentlyContinue `
    | Select-Object -First 1

if ($null -ne $listener) {
    $process = Get-CimInstance Win32_Process `
        -Filter "ProcessId = $($listener.OwningProcess)"
    if (
        $process.Name -ne "node.exe" -or
        $process.CommandLine -notlike "*$proxyScript*"
    ) {
        throw "A porta local 8000 ja esta ocupada por outro processo."
    }
    $proxyProcessId = $listener.OwningProcess
} else {
    Remove-Item $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
    $proxy = Start-Process `
        -FilePath $node `
        -ArgumentList $proxyScript `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru
    $proxyProcessId = $proxy.Id
    Start-Sleep -Milliseconds 800
    if ($proxy.HasExited) {
        $detail = Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue
        throw "Nao foi possivel iniciar o relay USB local. $detail"
    }
}

[IO.File]::WriteAllText($pidFile, $proxyProcessId.ToString())

$devices = & $adb devices
if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel consultar os dispositivos ADB."
}
if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $deviceLines = @(
        $devices | Where-Object { $_ -match "^\S+\s+device$" }
    )
    if ($deviceLines.Count -ne 1) {
        throw "Conecte exatamente um dispositivo ou informe -DeviceId."
    }
    $DeviceId = ($deviceLines[0] -split "\s+")[0]
}

& $adb -s $DeviceId reverse tcp:8000 tcp:8000 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel ativar adb reverse para o dispositivo $DeviceId."
}

$reverseRules = & $adb -s $DeviceId reverse --list
[PSCustomObject]@{
    DeviceId = $DeviceId
    ApiContainer = "http://127.0.0.1:18000"
    AppEndpoint = "http://127.0.0.1:8000"
    ProxyProcessId = $proxyProcessId
    Reverse = ($reverseRules -join "; ")
}
