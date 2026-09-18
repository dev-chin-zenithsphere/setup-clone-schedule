<#
Deprecated compatibility entry point.  The former implementation duplicated the
clone logic, embedded configuration, and did not validate its backup.  Use the
hardened clone script so both entry points have identical safeguards.
#>
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'clone-db.ps1')
exit $LASTEXITCODE
