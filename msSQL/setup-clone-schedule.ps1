[CmdletBinding()]
param(
    [string]$TaskName = "SQL Server Database Auto Clone",
    [string]$ScriptPath = (Join-Path $PSScriptRoot "clone-db.ps1"),
    [datetime]$At = (Get-Date "01:00"),
    [ValidateRange(1, 24)]
    [int]$ExecutionTimeLimitHours = 4
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Clone script not found: $ScriptPath"
}

$actionArguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$ScriptPath`""
$action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME "powershell.exe") -Argument $actionArguments
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours $ExecutionTimeLimitHours)

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Set-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
    Write-Host "Updated scheduled task: $TaskName"
}
else {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Clone a SQL Server database with SqlPackage every day at 01:00 AM." | Out-Null
    Write-Host "Created scheduled task: $TaskName"
}

Get-ScheduledTaskInfo -TaskName $TaskName | Select-Object LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
