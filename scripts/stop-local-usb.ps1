param(
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$pidFile = Join-Path $projectRoot "build\local-usb-proxy.pid"

function Resolve-AdbPath {
    $command = Get-Command "adb" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $sdkRoots += Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    foreach ($sdkRoot in $sdkRoots) {
        if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
            continue
        }
        $candidate = Join-Path $sdkRoot "platform-tools\adb.exe"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

$adb = Resolve-AdbPath
if ($null -ne $adb) {
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
