$pgDump    = "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe"
$pgRestore = "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe"
$psql      = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

# SOURCE
$sourceHost = "localhost"
$sourcePort = "5432"
$sourceDb   = "aoi_db"
$sourceUser = "postgres"

# DESTINATION
$destHost = "100.116.118.114"
$destPort = "5432"
$destDb   = "aoi_db_clone"
$destUser = "postgres"

# Password
$env:PGPASSWORD = "<DESTINATION_PASSWORD>"

# Temporary backup
$backupDir  = "C:\backup\postgres"
$backupFile = "$backupDir\aoi_db_clone.backup"

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force
}

Write-Host "=== START AOI DATABASE CLONE ==="

# 1. Dump source DB
& $pgDump `
    -h $sourceHost `
    -p $sourcePort `
    -U $sourceUser `
    -F c `
    -b `
    -f $backupFile `
    $sourceDb

if ($LASTEXITCODE -ne 0) {
    Write-Error "pg_dump failed"
    exit 1
}

# 2. Terminate connections on destination
& $psql `
    -h $destHost `
    -p $destPort `
    -U $destUser `
    -d postgres `
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$destDb' AND pid <> pg_backend_pid();"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Cannot connect to destination PostgreSQL"
    exit 1
}

# 3. Drop old clone
& $psql `
    -h $destHost `
    -p $destPort `
    -U $destUser `
    -d postgres `
    -c "DROP DATABASE IF EXISTS $destDb;"

if ($LASTEXITCODE -ne 0) {
    Write-Error "DROP DATABASE failed"
    exit 1
}

# 4. Create destination DB
& $psql `
    -h $destHost `
    -p $destPort `
    -U $destUser `
    -d postgres `
    -c "CREATE DATABASE $destDb;"

if ($LASTEXITCODE -ne 0) {
    Write-Error "CREATE DATABASE failed"
    exit 1
}

# 5. Restore
& $pgRestore `
    -h $destHost `
    -p $destPort `
    -U $destUser `
    -d $destDb `
    --no-owner `
    --no-privileges `
    $backupFile

if ($LASTEXITCODE -ne 0) {
    Write-Error "pg_restore failed"
    exit 1
}

Write-Host "=== DATABASE CLONE COMPLETED ==="
Write-Host "Source      : $sourceDb@$sourceHost"
Write-Host "Destination : $destDb@$destHost"

$env:PGPASSWORD = $null