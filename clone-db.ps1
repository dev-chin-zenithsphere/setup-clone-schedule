$ErrorActionPreference = "Stop"

# ============================================================
# PostgreSQL Tools
# ============================================================

$pgDump    = "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe"
$pgRestore = "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe"
$psql      = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

# ============================================================
# SOURCE DATABASE
# เครื่องปัจจุบัน
# ============================================================

$sourceHost     = "127.0.0.1"
$sourcePort     = "5432"
$sourceDb       = "aoi_db"
$sourceUser     = "postgres"

# ใส่ Password ของ PostgreSQL เครื่องต้นทาง
$sourcePassword = "postgres"

# ============================================================
# DESTINATION DATABASE
# Zenith Server ผ่าน Tailscale
# ============================================================

$destHost       = "100.116.118.114"
$destPort       = "5432"
$destDb         = "aoi_db_clone"
$destUser       = "postgres"

# ใส่ Password ของ PostgreSQL เครื่องปลายทาง
$destPassword   = "P@ssw0rd"

# ============================================================
# BACKUP
# ============================================================

$backupDir = "C:\backup\postgres"

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

$backupFile =
    Join-Path `
        $backupDir `
        "aoi_db_$timestamp.backup"

# ============================================================
# CREATE BACKUP DIRECTORY
# ============================================================

if (!(Test-Path $backupDir)) {

    New-Item `
        -ItemType Directory `
        -Path $backupDir `
        -Force |
        Out-Null
}

# ============================================================
# CHECK POSTGRESQL TOOLS
# ============================================================

$requiredTools = @(
    $pgDump,
    $pgRestore,
    $psql
)

foreach ($tool in $requiredTools) {

    if (!(Test-Path $tool)) {

        throw "PostgreSQL tool not found: $tool"
    }
}

# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " AOI DATABASE AUTO CLONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Source"
Write-Host "  Host     : $sourceHost"
Write-Host "  Port     : $sourcePort"
Write-Host "  Database : $sourceDb"
Write-Host "  User     : $sourceUser"
Write-Host ""
Write-Host "Destination"
Write-Host "  Host     : $destHost"
Write-Host "  Port     : $destPort"
Write-Host "  Database : $destDb"
Write-Host "  User     : $destUser"
Write-Host ""
Write-Host "Backup"
Write-Host "  $backupFile"
Write-Host ""

try {

    # ========================================================
    # STEP 1
    # TEST SOURCE DATABASE
    # ========================================================

    Write-Host "[1/7] Testing source database..."

    $env:PGPASSWORD = $sourcePassword

    & $psql `
        -h $sourceHost `
        -p $sourcePort `
        -U $sourceUser `
        -d $sourceDb `
        -v ON_ERROR_STOP=1 `
        -c "SELECT current_database(), current_user;"

    if ($LASTEXITCODE -ne 0) {

        throw "Cannot connect to SOURCE PostgreSQL."
    }

    Write-Host "      Source connection OK."
    Write-Host ""

    # ========================================================
    # STEP 2
    # DUMP SOURCE
    # ========================================================

    Write-Host "[2/7] Dumping source database..."

    & $pgDump `
        -h $sourceHost `
        -p $sourcePort `
        -U $sourceUser `
        -F c `
        -b `
        -v `
        -f $backupFile `
        $sourceDb

    if ($LASTEXITCODE -ne 0) {

        throw "pg_dump failed with exit code $LASTEXITCODE"
    }

    if (!(Test-Path $backupFile)) {

        throw "Backup file was not created."
    }

    $backupSize =
        (Get-Item $backupFile).Length

    if ($backupSize -le 0) {

        throw "Backup file is empty."
    }

    Write-Host ""
    Write-Host "      Dump completed."
    Write-Host "      Size: $([Math]::Round($backupSize / 1MB, 2)) MB"
    Write-Host ""

    # ========================================================
    # STEP 3
    # VERIFY BACKUP
    # ========================================================

    Write-Host "[3/7] Verifying backup file..."

    & $pgRestore `
        --list `
        $backupFile |
        Out-Null

    if ($LASTEXITCODE -ne 0) {

        throw "Backup verification failed."
    }

    Write-Host "      Backup file OK."
    Write-Host ""

    # ========================================================
    # SWITCH PASSWORD TO DESTINATION
    # ========================================================

    $env:PGPASSWORD = $destPassword

    # ========================================================
    # STEP 4
    # TEST DESTINATION
    # ========================================================

    Write-Host "[4/7] Testing destination server..."

    & $psql `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -c "SELECT current_database(), current_user, version();"

    if ($LASTEXITCODE -ne 0) {

        throw "Cannot connect to DESTINATION PostgreSQL."
    }

    Write-Host "      Destination connection OK."
    Write-Host ""

    # ========================================================
    # STEP 5
    # TERMINATE CONNECTIONS + DROP OLD CLONE
    # ========================================================

    Write-Host "[5/7] Recreating destination database..."

    & $psql `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -c "
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '$destDb'
              AND pid <> pg_backend_pid();
        "

    if ($LASTEXITCODE -ne 0) {

        throw "Unable to terminate destination connections."
    }

    & $psql `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -c "DROP DATABASE IF EXISTS `"$destDb`";"

    if ($LASTEXITCODE -ne 0) {

        throw "DROP DATABASE failed."
    }

    # ========================================================
    # CREATE NEW DATABASE
    # ========================================================

    & $psql `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -c "CREATE DATABASE `"$destDb`";"

    if ($LASTEXITCODE -ne 0) {

        throw "CREATE DATABASE failed."
    }

    Write-Host "      Destination database recreated."
    Write-Host ""

    # ========================================================
    # STEP 6
    # RESTORE
    # ========================================================

    Write-Host "[6/7] Restoring database to destination..."

    & $pgRestore `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d $destDb `
        --no-owner `
        --no-privileges `
        --exit-on-error `
        --verbose `
        $backupFile

    if ($LASTEXITCODE -ne 0) {

        throw "pg_restore failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "      Restore completed."
    Write-Host ""

    # ========================================================
    # STEP 7
    # VERIFY DESTINATION
    # ========================================================

    Write-Host "[7/7] Verifying destination database..."

    & $psql `
        -h $destHost `
        -p $destPort `
        -U $destUser `
        -d $destDb `
        -v ON_ERROR_STOP=1 `
        -c "
            SELECT
                current_database() AS database,
                COUNT(*) AS table_count
            FROM information_schema.tables
            WHERE table_schema = 'public';
        "

    if ($LASTEXITCODE -ne 0) {

        throw "Destination verification failed."
    }

    # ========================================================
    # SUCCESS
    # ========================================================

    Write-Host ""
    Write-Host "=============================================="
    Write-Host " DATABASE CLONE SUCCESS"
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "Source      : $sourceDb@$sourceHost"
    Write-Host "Destination : $destDb@$destHost"
    Write-Host "Backup      : $backupFile"
    Write-Host "Completed   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""

}
catch {

    Write-Host ""
    Write-Host "=============================================="
    Write-Host " DATABASE CLONE FAILED"
    Write-Host "=============================================="
    Write-Host ""

    Write-Error $_

    exit 1
}
finally {

    # Clear password from environment
    $env:PGPASSWORD = $null
}