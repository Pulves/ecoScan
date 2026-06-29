param(
    [string]$EnvironmentFile = (Join-Path $PSScriptRoot "..\.env")
)

$ErrorActionPreference = "Stop"
$resolvedEnvironmentFile = [IO.Path]::GetFullPath($EnvironmentFile)

function New-HexSecret {
    param([int]$ByteCount)

    $bytes = New-Object byte[] $ByteCount
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    } finally {
        $random.Dispose()
    }
    return (
        [BitConverter]::ToString($bytes) -replace "-", ""
    ).ToLowerInvariant()
}

$databasePassword = New-HexSecret 24
$secretKey = New-HexSecret 48

if (Test-Path -LiteralPath $resolvedEnvironmentFile) {
    $content = Get-Content `
        -LiteralPath $resolvedEnvironmentFile `
        -Raw `
        -Encoding utf8
} else {
    $content = ""
}

function Set-EnvironmentValue {
    param(
        [string]$Content,
        [string]$Name,
        [string]$Value
    )

    $line = "$Name=$Value"
    if ($Content -match "(?m)^$([regex]::Escape($Name))=") {
        return [regex]::Replace(
            $Content,
            "(?m)^$([regex]::Escape($Name))=.*$",
            $line
        )
    }
    return "$($Content.TrimEnd())`r`n$line`r`n"
}

$content = Set-EnvironmentValue $content "POSTGRES_PASSWORD" $databasePassword
$content = Set-EnvironmentValue $content "SECRET_KEY" $secretKey
$content = Set-EnvironmentValue `
    $content `
    "DATABASE_URL" `
    "postgresql+psycopg://postgres:$databasePassword@localhost:5432/ecoscan"

$runningDatabase = docker ps `
    --filter "name=^/postgres_db$" `
    --filter "status=running" `
    --format "{{.Names}}"
if ($runningDatabase -eq "postgres_db") {
    docker exec postgres_db psql `
        -U postgres `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -c "ALTER USER postgres PASSWORD '$databasePassword';"
}

$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $resolvedEnvironmentFile,
    $content.Trim(),
    $utf8WithoutBom
)

Write-Output "Segredos de desenvolvimento rotacionados em $resolvedEnvironmentFile"
Write-Output "Os valores nao foram exibidos e o arquivo permanece fora do Git."
