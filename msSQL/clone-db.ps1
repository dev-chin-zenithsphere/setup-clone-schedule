[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# ============================================================
# PATHS
# ============================================================

$envFile = Join-Path $PSScriptRoot ".env"

# ============================================================
# LOAD .ENV
# ============================================================

if (-not (Test-Path $envFile)) {
    throw ".env file not found: $envFile"
}

Write-Host "Loading configuration from:"
Write-Host "  $envFile"
Write-Host ""

Get-Content $envFile | ForEach-Object {

    $line = $_.Trim()

    # Ignore empty lines
    if ([string]::IsNullOrWhiteSpace($line)) {
        return
    }

    # Ignore comments
    if ($line.StartsWith("#")) {
        return
    }

    # ENV must be KEY=VALUE
    $parts = $line -split "=", 2

    if ($parts.Count -ne 2) {
        throw "Invalid .env line: $line"
    }

    $name  = $parts[0].Trim()
    $value = $parts[1].Trim()

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Invalid .env variable: $line"
    }

    # Remove surrounding quotes if present
    if (
        ($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    Set-Item `
        -Path "Env:$name" `
        -Value $value
}

# ============================================================
# READ ENV VARIABLES
# ============================================================

$SourceServer = $env:MSSQL_SOURCE_SERVER
$SourceDatabase = $env:MSSQL_SOURCE_DATABASE

$SourceUseWindowsAuthentication =
    $env:MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION -match "^(true|1|yes)$"

$SourceUser = $env:MSSQL_SOURCE_USER
$SourcePassword = $env:MSSQL_SOURCE_PASSWORD

$DestinationServer = $env:MSSQL_DESTINATION_SERVER
$DestinationDatabase = $env:MSSQL_DESTINATION_DATABASE
$DestinationUser = $env:MSSQL_DESTINATION_USER
$DestinationPassword = $env:MSSQL_DESTINATION_PASSWORD

$BacpacDirectory = $env:MSSQL_BACPAC_DIRECTORY
$SqlCmdPath = $env:MSSQL_SQLCMD_PATH
$SqlPackagePath = $env:MSSQL_SQLPACKAGE_PATH

# ============================================================
# DEFAULT VALUES
# ============================================================

if ([string]::IsNullOrWhiteSpace($BacpacDirectory)) {
    $BacpacDirectory = "C:\backup\mssql"
}

if ([string]::IsNullOrWhiteSpace($SqlCmdPath)) {
    $SqlCmdPath = "sqlcmd.exe"
}

if ([string]::IsNullOrWhiteSpace($SqlPackagePath)) {
    $SqlPackagePath = Join-Path `
        $env:USERPROFILE `
        ".dotnet\tools\sqlpackage.exe"
}

# ============================================================
# VALIDATE ENV
# ============================================================

$requiredVariables = @{
    "MSSQL_SOURCE_SERVER"        = $SourceServer
    "MSSQL_SOURCE_DATABASE"      = $SourceDatabase
    "MSSQL_DESTINATION_SERVER"   = $DestinationServer
    "MSSQL_DESTINATION_DATABASE" = $DestinationDatabase
    "MSSQL_DESTINATION_USER"     = $DestinationUser
    "MSSQL_DESTINATION_PASSWORD" = $DestinationPassword
}

if (-not $SourceUseWindowsAuthentication) {
    if ([string]::IsNullOrWhiteSpace($SourceUser) -or [string]::IsNullOrWhiteSpace($SourcePassword) -or $SourcePassword -match '^<.*>$') {
        throw "Set MSSQL_SOURCE_USER and MSSQL_SOURCE_PASSWORD when source Windows Authentication is disabled."
    }
}

foreach ($item in $requiredVariables.GetEnumerator()) {

    if ([string]::IsNullOrWhiteSpace($item.Value)) {
        throw "Missing required .env variable: $($item.Key)"
    }
}

if (-not $SourceUseWindowsAuthentication) {
    throw @"
MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION must be true.

Current script configuration expects Windows Authentication
for the local source SQL Server.
"@
}

# ============================================================
# CHECK SQLCMD
# ============================================================

$sqlCmdCommand = Get-Command `
    $SqlCmdPath `
    -ErrorAction SilentlyContinue

if (-not $sqlCmdCommand) {
    throw "sqlcmd not found: $SqlCmdPath"
}

# ============================================================
# CHECK SQLPACKAGE
# ============================================================

if (-not (Test-Path $SqlPackagePath)) {

    throw @"
SqlPackage not found:

$SqlPackagePath

Install with:

dotnet tool install -g microsoft.sqlpackage --allow-roll-forward
"@
}

# ============================================================
# CREATE BACPAC DIRECTORY
# ============================================================

if (-not (Test-Path $BacpacDirectory)) {

    Write-Host "Creating backup directory:"
    Write-Host "  $BacpacDirectory"

    New-Item `
        -ItemType Directory `
        -Path $BacpacDirectory `
        -Force |
        Out-Null
}

# ============================================================
# GENERATE BACPAC FILE
# ============================================================

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

$bacpac = Join-Path `
    $BacpacDirectory `
    "${SourceDatabase}_${timestamp}.bacpac"

# ============================================================
# SOURCE CONNECTION STRING
# ============================================================
#
# Local SQL Server:
# - Windows Authentication
# - Encryption enabled
# - Trust self-signed/untrusted certificate
#
# ============================================================

$sourceConnection = if ($SourceUseWindowsAuthentication) {
    "Server=$SourceServer;Database=$SourceDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=False"
} else {
    "Server=$SourceServer;Database=$SourceDatabase;User ID=$SourceUser;Password=$SourcePassword;Encrypt=True;TrustServerCertificate=False"
}

# ============================================================
# DESTINATION CONNECTION STRING
# ============================================================
#
# Remote SQL Server:
# - SQL Authentication
# - Encryption enabled
# - Trust self-signed/untrusted certificate
#
# ============================================================

$destinationConnection = @(
    "Server=$DestinationServer"
    "Database=$DestinationDatabase"
    "User ID=$DestinationUser"
    "Password=$DestinationPassword"
    "Encrypt=True"
    "TrustServerCertificate=False"
) -join ";"

# ============================================================
# SAFE DATABASE NAME
# ============================================================

$destinationDatabaseIdentifier =
    "[" +
    $DestinationDatabase.Replace("]", "]]") +
    "]"

$destinationDatabaseLiteral =
    $DestinationDatabase.Replace("'", "''")

# ============================================================
# SQLCMD HELPER
# ============================================================

function Invoke-SqlCmd {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [switch]$WindowsAuthentication,

        [string]$User,

        [string]$Password
    )

    $arguments = @(
        "-S", $Server,
        "-d", $Database,

        # Exit with error code when SQL fails
        "-b",

        "-Q", $Query
    )

    if ($WindowsAuthentication) {

        # Windows Authentication
        $arguments += "-E"
    }
    else {

        # SQL Server Authentication
        $arguments += @(
            "-U", $User,
            "-P", $Password
        )
    }

    & $SqlCmdPath @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed against $Server"
    }
}

# ============================================================
# DISPLAY CONFIGURATION
# ============================================================

Write-Host "============================================"
Write-Host " MSSQL DATABASE CLONE"
Write-Host "============================================"
Write-Host ""

Write-Host "SOURCE"
Write-Host "  Server   : $SourceServer"
Write-Host "  Database : $SourceDatabase"
Write-Host "  Auth     : Windows Authentication"
Write-Host ""

Write-Host "DESTINATION"
Write-Host "  Server   : $DestinationServer"
Write-Host "  Database : $DestinationDatabase"
Write-Host "  User     : $DestinationUser"
Write-Host ""

Write-Host "BACPAC"
Write-Host "  $bacpac"
Write-Host ""

# ============================================================
# CLONE DATABASE
# ============================================================

try {

    # ========================================================
    # 1/5 TEST SOURCE DATABASE
    # ========================================================

    Write-Host "[1/5] Testing source database..."

    $sourceTestQuery = @"
SET NOCOUNT ON;

SELECT
    DB_NAME() AS database_name,
    COUNT(*) AS table_count
FROM sys.tables;
"@

    Invoke-SqlCmd `
        -Server $SourceServer `
        -Database $SourceDatabase `
        -Query $sourceTestQuery `
        -WindowsAuthentication:$SourceUseWindowsAuthentication `
        -User $SourceUser `
        -Password $SourcePassword

    # ========================================================
    # 2/5 EXPORT SOURCE DATABASE
    # ========================================================

    Write-Host ""
    Write-Host "[2/5] Exporting source to BACPAC..."
    Write-Host ""

    & $SqlPackagePath `
        "/Action:Export" `
        "/SourceConnectionString:$sourceConnection" `
        "/TargetFile:$bacpac" `
        "/p:VerifyExtraction=True"

    if ($LASTEXITCODE -ne 0) {
        throw "SqlPackage export failed."
    }

    if (-not (Test-Path $bacpac)) {
        throw "BACPAC was not created: $bacpac"
    }

    $bacpacSize = (Get-Item $bacpac).Length

    Write-Host ""
    Write-Host "BACPAC created:"
    Write-Host "  File : $bacpac"
    Write-Host "  Size : $([math]::Round($bacpacSize / 1MB, 2)) MB"

    # ========================================================
    # 3/5 TEST DESTINATION SERVER
    # ========================================================

    Write-Host ""
    Write-Host "[3/5] Testing destination server..."

    $destinationTestQuery = @"
SET NOCOUNT ON;

SELECT
    @@SERVERNAME AS server_name,
    SUSER_SNAME() AS login_name;
"@

    Invoke-SqlCmd `
        -Server $DestinationServer `
        -Database "master" `
        -Query $destinationTestQuery `
        -User $DestinationUser `
        -Password $DestinationPassword

    # ========================================================
    # 4/5 DROP DESTINATION + IMPORT
    # ========================================================

    Write-Host ""
    Write-Host "[4/5] Importing clone..."
    Write-Host ""
    Write-Host "WARNING: Existing destination database will be deleted."
    Write-Host ""

    $dropDatabaseQuery = @"
IF DB_ID(N'$destinationDatabaseLiteral') IS NOT NULL
BEGIN
    ALTER DATABASE $destinationDatabaseIdentifier
        SET SINGLE_USER
        WITH ROLLBACK IMMEDIATE;

    DROP DATABASE $destinationDatabaseIdentifier;
END;
"@

    Write-Host "Removing existing destination database..."

    Invoke-SqlCmd `
        -Server $DestinationServer `
        -Database "master" `
        -Query $dropDatabaseQuery `
        -User $DestinationUser `
        -Password $DestinationPassword

    Write-Host ""
    Write-Host "Importing BACPAC..."

    & $SqlPackagePath `
        "/Action:Import" `
        "/SourceFile:$bacpac" `
        "/TargetConnectionString:$destinationConnection"

    if ($LASTEXITCODE -ne 0) {
        throw "SqlPackage import failed."
    }

    # ========================================================
    # 5/5 VERIFY DESTINATION
    # ========================================================

    Write-Host ""
    Write-Host "[5/5] Verifying destination database..."

    $verifyQuery = @"
SET NOCOUNT ON;

SELECT
    DB_NAME() AS database_name,
    COUNT(*) AS table_count
FROM sys.tables;
"@

    Invoke-SqlCmd `
        -Server $DestinationServer `
        -Database $DestinationDatabase `
        -Query $verifyQuery `
        -User $DestinationUser `
        -Password $DestinationPassword

    # ========================================================
    # SUCCESS
    # ========================================================

    Write-Host ""
    Write-Host "============================================"
    Write-Host " DATABASE CLONE SUCCESS"
    Write-Host "============================================"
    Write-Host ""

    Write-Host "Source"
    Write-Host "  Server   : $SourceServer"
    Write-Host "  Database : $SourceDatabase"
    Write-Host ""

    Write-Host "Destination"
    Write-Host "  Server   : $DestinationServer"
    Write-Host "  Database : $DestinationDatabase"
    Write-Host ""

    Write-Host "BACPAC"
    Write-Host "  $bacpac"
    Write-Host ""

    exit 0
}
catch {

    Write-Host ""

    Write-Error "DATABASE CLONE FAILED: $($_.Exception.Message)"

    exit 1
}
