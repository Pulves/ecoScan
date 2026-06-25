param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [string]$Database = "ecoscan",
    [string]$Container = "postgres_db",
    [switch]$ConfirmRestore
)

$ErrorActionPreference = "Stop"
if (-not $ConfirmRestore) {
    throw "Use -ConfirmRestore para confirmar a restauracao destrutiva."
}

$resolvedBackup = (Resolve-Path -LiteralPath $BackupFile).Path
$fileName = [System.IO.Path]::GetFileName($resolvedBackup)
$containerPath = "/tmp/$fileName"

docker cp $resolvedBackup "${Container}:$containerPath"
docker exec $Container pg_restore `
    --clean `
    --if-exists `
    --no-owner `
    --username=postgres `
    --dbname=$Database `
    $containerPath
docker exec $Container rm -f $containerPath

Write-Output "Backup restaurado em ${Database}: $resolvedBackup"
