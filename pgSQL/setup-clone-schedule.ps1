# powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ".\setup-clone-schedule.ps1"
# ============================================================
# AOI DATABASE AUTO CLONE - SCHEDULE
# Every day at 12:00 PM
# ============================================================

$taskName   = "AOI Database Auto Clone"
$scriptPath = Join-Path $PSScriptRoot "clone-db.ps1"

# ------------------------------------------------------------
# Check Clone Script
# ------------------------------------------------------------

if (!(Test-Path $scriptPath)) {
    throw "Clone script not found: $scriptPath"
}

# ------------------------------------------------------------
# Action
# ------------------------------------------------------------

$action = New-ScheduledTaskAction `
    -Execute (Join-Path $PSHOME "powershell.exe") `
    -Argument "-NoProfile -ExecutionPolicy RemoteSigned -File `"$scriptPath`""

# ------------------------------------------------------------
# Trigger
# Every day at 01:00 PM
# ------------------------------------------------------------

$trigger = New-ScheduledTaskTrigger `
    -Daily `
    -At "01:00AM"

# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# ------------------------------------------------------------
# Create / Update Task
# ------------------------------------------------------------

$existingTask = Get-ScheduledTask `
    -TaskName $taskName `
    -ErrorAction SilentlyContinue

if ($existingTask) {

    Write-Host "Updating existing scheduled task..."

    Set-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings

}
else {

    Write-Host "Creating new scheduled task..."

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Clone aoi_db to aoi_db_clone on PostgreSQL server 100.116.118.114 every day at 12:00 PM"

}

# ------------------------------------------------------------
# Show Result
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " AOI DATABASE AUTO CLONE SCHEDULE"
Write-Host "========================================"

Get-ScheduledTaskInfo `
    -TaskName $taskName |
    Select-Object `
        TaskName,
        LastRunTime,
        LastTaskResult,
        NextRunTime,
        NumberOfMissedRuns
