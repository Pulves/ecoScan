param(
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$pidFile = Join-Path $projectRoot "build\local-usb-proxy.pid"

if (Test-Path -LiteralPath $adb) {
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        & $adb reverse --remove tcp:8000 2>$null
    } else {
        & $adb -s $DeviceId reverse --remove tcp:8000 2>$null
    }
}

if (Test-Path -LiteralPath $pidFile) {
    $proxyProcessId = [int](Get-Content $pidFile -Raw)
    $process = Get-CimInstance Win32_Process `
        -Filter "ProcessId = $proxyProcessId" `
        -ErrorAction SilentlyContinue
    if (
        $null -ne $process -and
        $process.Name -eq "node.exe" -and
        $process.CommandLine -like "*local_usb_proxy.js*"
    ) {
        Stop-Process -Id $proxyProcessId
    }
    Remove-Item $pidFile -Force
}
