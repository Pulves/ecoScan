param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\backups")
)

$ErrorActionPreference = "Stop"
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "ecoscan-$timestamp.dump"
$containerPath = "/tmp/$fileName"
$localPath = Join-Path $resolvedOutput $fileName

docker exec postgres_db pg_dump `
    --format=custom `
    --no-owner `
    --username=postgres `
    --file=$containerPath `
    ecoscan

docker cp "postgres_db:$containerPath" $localPath
docker exec postgres_db rm -f $containerPath

Write-Output $localPath
