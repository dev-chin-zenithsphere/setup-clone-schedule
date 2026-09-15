[CmdletBinding()]
param(
    [string]$SourceServer = "localhost", [string]$SourceDatabase = "StudentDB",
    [switch]$SourceUseWindowsAuthentication,
    [string]$DestinationServer = "100.116.118.114", [string]$DestinationDatabase = "Students",
    [string]$DestinationUser = "sa", [string]$DestinationPassword,
    [string]$BacpacDirectory = "C:\backup\mssql",
    [string]$SqlCmdPath = "sqlcmd.exe",
    [string]$SqlPackagePath = (Join-Path $env:USERPROFILE ".dotnet\tools\sqlpackage.exe")
)
$ErrorActionPreference = "Stop"; $bound = $PSBoundParameters
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) { Get-Content $envFile | ForEach-Object { $l=$_.Trim(); if($l -and -not $l.StartsWith('#')) { $p=$l -split '=',2; if($p.Count -ne 2){throw "Invalid .env line: $l"}; Set-Item -Path "Env:$($p[0].Trim())" -Value $p[1].Trim() } } }
function FromEnv($name,$envName) { if(-not $bound.ContainsKey($name) -and (Test-Path "Env:$envName")){ Set-Variable -Name $name -Value (Get-Item "Env:$envName").Value -Scope Script } }
FromEnv SourceServer MSSQL_SOURCE_SERVER; FromEnv SourceDatabase MSSQL_SOURCE_DATABASE; FromEnv DestinationServer MSSQL_DESTINATION_SERVER; FromEnv DestinationDatabase MSSQL_DESTINATION_DATABASE; FromEnv DestinationUser MSSQL_DESTINATION_USER; FromEnv DestinationPassword MSSQL_DESTINATION_PASSWORD; FromEnv BacpacDirectory MSSQL_BACPAC_DIRECTORY; FromEnv SqlCmdPath MSSQL_SQLCMD_PATH; FromEnv SqlPackagePath MSSQL_SQLPACKAGE_PATH
if(-not $bound.ContainsKey('SourceUseWindowsAuthentication') -and $env:MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION -eq 'true'){$SourceUseWindowsAuthentication=$true}
if([string]::IsNullOrWhiteSpace($DestinationPassword) -or $DestinationPassword -match '^<.*>$'){throw "Set MSSQL_DESTINATION_PASSWORD in $envFile"}
if(-not(Get-Command $SqlCmdPath -ErrorAction SilentlyContinue)){throw "sqlcmd not found: $SqlCmdPath"}
if(-not(Test-Path $SqlPackagePath)){throw "SqlPackage not found: $SqlPackagePath. Install: dotnet tool install -g microsoft.sqlpackage --allow-roll-forward"}
if(-not(Test-Path $BacpacDirectory)){New-Item -ItemType Directory -Path $BacpacDirectory -Force|Out-Null}
$bacpac=Join-Path $BacpacDirectory ("{0}_{1}.bacpac" -f $SourceDatabase,(Get-Date -Format 'yyyy-MM-dd_HHmmss'))
$sourceConnection="Server=$SourceServer;Database=$SourceDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True"
$destConnection="Server=$DestinationServer;Database=$DestinationDatabase;User ID=$DestinationUser;Password=$DestinationPassword;Encrypt=True;TrustServerCertificate=True"
$destId='['+$DestinationDatabase.Replace(']',']]')+']'; $destLiteral=$DestinationDatabase.Replace("'","''")
function Sql($server,$database,$query,[switch]$Windows){$a=@('-S',$server,'-d',$database,'-b','-Q',$query);if($Windows){$a+='-E'}else{$a+=@('-U',$DestinationUser,'-P',$DestinationPassword)};& $SqlCmdPath @a;if($LASTEXITCODE -ne 0){throw "sqlcmd failed against $server"}}
try {
 Write-Host '[1/5] Testing source database...'; Sql $SourceServer $SourceDatabase 'SET NOCOUNT ON; SELECT DB_NAME() AS database_name, COUNT(*) AS table_count FROM sys.tables;' -Windows:$SourceUseWindowsAuthentication
 Write-Host '[2/5] Exporting source to BACPAC...'; & $SqlPackagePath '/Action:Export' "/SourceConnectionString:$sourceConnection" "/TargetFile:$bacpac" '/p:VerifyExtraction=True'; if($LASTEXITCODE -ne 0){throw 'SqlPackage export failed.'}
 Write-Host '[3/5] Testing destination server...'; Sql $DestinationServer master 'SELECT @@SERVERNAME AS server_name, SUSER_SNAME() AS login_name;'
 Write-Host '[4/5] Importing clone (existing destination data will be deleted)...'; Sql $DestinationServer master "IF DB_ID(N'$destLiteral') IS NOT NULL BEGIN ALTER DATABASE $destId SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $destId; END;"; & $SqlPackagePath '/Action:Import' "/SourceFile:$bacpac" "/TargetConnectionString:$destConnection"; if($LASTEXITCODE -ne 0){throw 'SqlPackage import failed.'}
 Write-Host '[5/5] Verifying destination...'; Sql $DestinationServer $DestinationDatabase 'SET NOCOUNT ON; SELECT DB_NAME() AS database_name, COUNT(*) AS table_count FROM sys.tables;'; Write-Host 'DATABASE CLONE SUCCESS'; Write-Host "BACPAC: $bacpac"
} catch { Write-Error "DATABASE CLONE FAILED: $($_.Exception.Message)"; exit 1 }
