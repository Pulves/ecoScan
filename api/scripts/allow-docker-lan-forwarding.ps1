param(
    [switch]$Confirm,
    [string]$ResultFile
)

$ErrorActionPreference = "Stop"
$ruleDisplayName = "com.docker.backend.exe"
$programSuffix = "\DockerDesktop\resources\com.docker.backend.exe"

if (-not $Confirm) {
    throw "Informe -Confirm para desabilitar somente as regras publicas de bloqueio do Docker."
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    throw "Execute este script em um PowerShell como Administrador."
}

$candidates = @(
    Get-NetFirewallRule `
        -PolicyStore PersistentStore `
        -DisplayName $ruleDisplayName `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            $application = $_ | Get-NetFirewallApplicationFilter
            [PSCustomObject]@{
                Rule = $_
                Program = $application.Program
            }
        }
)

$targets = @(
    $candidates | Where-Object {
        $_.Rule.Enabled.ToString() -eq "True" -and
        $_.Rule.Direction.ToString() -eq "Inbound" -and
        $_.Rule.Action.ToString() -eq "Block" -and
        $_.Rule.Profile.ToString() -eq "Public" -and
        -not [string]::IsNullOrWhiteSpace($_.Program) -and
        $_.Program.EndsWith(
            $programSuffix,
            [StringComparison]::OrdinalIgnoreCase
        )
    }
)

if ($targets.Count -ne 2) {
    throw "Esperadas exatamente 2 regras publicas de bloqueio do Docker; encontradas $($targets.Count). Nenhuma regra foi alterada."
}

$targets.Rule | Disable-NetFirewallRule

$verifiedRules = @(
    $targets | ForEach-Object {
        Get-NetFirewallRule `
            -PolicyStore PersistentStore `
            -Name $_.Rule.Name
    }
)
if (@($verifiedRules | Where-Object { $_.Enabled.ToString() -ne "False" }).Count -ne 0) {
    throw "Nao foi possivel confirmar que as duas regras foram desabilitadas."
}

$result = [PSCustomObject]@{
    DisabledRules = $verifiedRules.Count
    Names = @($verifiedRules.Name)
    Programs = @($targets.Program)
    Profiles = @($verifiedRules | ForEach-Object { $_.Profile.ToString() })
    DefaultInboundPolicyChanged = $false
}

if (-not [string]::IsNullOrWhiteSpace($ResultFile)) {
    $resolvedResultFile = [IO.Path]::GetFullPath($ResultFile)
    $resultDirectory = [IO.Path]::GetDirectoryName($resolvedResultFile)
    if (-not [IO.Directory]::Exists($resultDirectory)) {
        [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    }
    $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        $resolvedResultFile,
        ($result | ConvertTo-Json -Depth 3),
        $utf8WithoutBom
    )
}

$result
