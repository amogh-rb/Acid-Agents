# M23 gate (B80-B82): backup/restore evidence, security note and the Gate 2 checklist are complete; every milestone on
# the board is Defined and Tested. (The drill itself runs on the seeded database: tools/backup_restore.ps1.)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$fail = 0
function Check([string]$label, [bool]$ok) {
  if ($ok) { Write-Output "PASS  $label" } else { Write-Output "FAIL  $label"; $script:fail++ }
}

$ev = Get-ChildItem 'docs/evidence' -Filter 'backup_restore_*.txt' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
Check "backup/restore evidence exists" ($null -ne $ev)
if ($ev) {
  $t = Get-Content $ev.FullName -Raw
  Check ("restore verified: row counts match, indexes valid, policies restored ({0})" -f $ev.Name) ($t -match 'data check: PASS' -and $t -match 'mismatches: 0')
  Check "restore time logged against the assumed RTO and within it" ($t -match 'WITHIN RTO')
}
Check "security design note exists (docs/phase5/m22_security.md)" (Test-Path 'docs/phase5/m22_security.md')
Check "Gate 2 checklist exists (docs/phase5/gate2_checklist.md)" (Test-Path 'docs/phase5/gate2_checklist.md')

$rows = Get-Content 'docs/milestones.md' | Where-Object { $_ -match '^\| M\d' }
$open = @($rows | Where-Object { $c = $_ -split '\|'; -not ($c[5] -match '✅' -and $c[7] -match '✅') } | ForEach-Object { ($_ -split '\|')[1].Trim() })
Check ("every milestone on the board is Defined and Tested" + $(if ($open) { ': open ' + ($open -join ', ') } else { '' })) ($open.Count -eq 0)
if ($fail -gt 0) { exit 1 }
