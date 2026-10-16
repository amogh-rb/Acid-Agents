<#
.SYNOPSIS
  Daily retention job (M22, D35): anonymises candidates past their window and deletes rows past the retention stated
  in each table comment. Run as the database owner from Windows Task Scheduler, for example daily at 02:30:
    schtasks /Create /SC DAILY /ST 02:30 /TN "Talentra retention" /TR "powershell -NoProfile -File <repo>\tools\run_retention.ps1"
  Each run is audited in audit.audit_event (action retention_purged) with the counts per table.
#>
param([string]$Database = '')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path '.env') {
  foreach ($line in Get-Content '.env') {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2].Trim('"', "'") }
  }
}
if (-not $Database) { $Database = if ($env:TALENTRA_DB) { $env:TALENTRA_DB } else { 'talentra' } }
$psql = Join-Path $env:PGBIN 'psql.exe'
$out = & $psql -X -q -t -A -d $Database -v ON_ERROR_STOP=1 -c "SET app.current_user_id = '1'; SELECT admin.run_retention();"
if ($LASTEXITCODE -ne 0) { throw "retention run failed on $Database" }
Write-Output ("{0:yyyy-MM-dd HH:mm:ss} retention {1}: {2}" -f (Get-Date), $Database, ($out -join ''))
