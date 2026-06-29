param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$androidDirectory = $PSScriptRoot
$keystorePath = Join-Path $androidDirectory "app\upload-keystore.jks"
$propertiesPath = Join-Path $androidDirectory "key.properties"

if (-not $Force -and (
        (Test-Path -LiteralPath $keystorePath) -or
        (Test-Path -LiteralPath $propertiesPath)
    )) {
    throw "A chave release ja existe. Use -Force somente para substitui-la."
}

$keytool = Get-Command keytool.exe -ErrorAction SilentlyContinue
if ($null -eq $keytool) {
    $androidStudioKeytool = Join-Path $env:JAVA_HOME "bin\keytool.exe"
    if (-not (Test-Path -LiteralPath $androidStudioKeytool)) {
        throw "keytool.exe nao encontrado. Configure JAVA_HOME."
    }
    $keytoolPath = $androidStudioKeytool
} else {
    $keytoolPath = $keytool.Source
}

$passwordBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$password = ([BitConverter]::ToString($passwordBytes) -replace "-", "").ToLowerInvariant()

& $keytoolPath `
    -genkeypair `
    -v `
    -keystore $keystorePath `
    -storepass $password `
    -keypass $password `
    -alias upload `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -dname "CN=EcoScan, OU=Mobile, O=EcoScan, L=Fortaleza, ST=Ceara, C=BR"

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel gerar a chave de assinatura."
}

$propertiesContent = @"
storePassword=$password
keyPassword=$password
keyAlias=upload
storeFile=app/upload-keystore.jks
"@
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $propertiesPath,
    $propertiesContent.Trim(),
    $utf8WithoutBom
)

Write-Output "Chave release criada em $keystorePath"
Write-Output "Credenciais armazenadas em $propertiesPath"
Write-Output "Mantenha ambos fora do Git e em backup seguro."
