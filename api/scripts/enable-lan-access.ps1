param(
    [int]$Port = 8000,
    [string]$RemoteAddress = "192.168.0.0/24",
    [string]$ResultFile
)

$ErrorActionPreference = "Stop"
$ruleName = "EcoScan API LAN"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    throw "Execute este script em um PowerShell como Administrador."
}

$ruleParameters = @{
    DisplayName = $ruleName
    Direction = "Inbound"
    Action = "Allow"
    Protocol = "TCP"
    LocalPort = $Port
    RemoteAddress = $RemoteAddress
    EdgeTraversalPolicy = "Allow"
    Profile = "Any"
}

$existingRule = Get-NetFirewallRule `
    -PolicyStore PersistentStore `
    -DisplayName $ruleName `
    -ErrorAction SilentlyContinue
if ($null -ne $existingRule) {
    $existingRule | Remove-NetFirewallRule
}
New-NetFirewallRule @ruleParameters | Out-Null
$rule = Get-NetFirewallRule `
    -PolicyStore ActiveStore `
    -DisplayName $ruleName

$portFilter = $rule | Get-NetFirewallPortFilter
$addressFilter = $rule | Get-NetFirewallAddressFilter
$result = [PSCustomObject]@{
    Name = $rule.DisplayName
    Enabled = $rule.Enabled.ToString()
    Profile = $rule.Profile.ToString()
    Direction = $rule.Direction.ToString()
    Action = $rule.Action.ToString()
    Protocol = $portFilter.Protocol.ToString()
    LocalPort = ($portFilter.LocalPort -join ",")
    RemoteAddress = ($addressFilter.RemoteAddress -join ",")
    EdgeTraversalPolicy = $rule.EdgeTraversalPolicy.ToString()
    PolicyStoreSourceType = $rule.PolicyStoreSourceType.ToString()
}

if (-not [string]::IsNullOrWhiteSpace($ResultFile)) {
    $resolvedResultFile = [IO.Path]::GetFullPath($ResultFile)
    $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        $resolvedResultFile,
        ($result | ConvertTo-Json),
        $utf8WithoutBom
    )
}

$result
