# M21 gate: the performance evidence is complete (measured on the seeded databases; this check runs on any machine).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$fail = 0
function Check([string]$label, [bool]$ok) {
  if ($ok) { Write-Output "PASS  $label" } else { Write-Output "FAIL  $label"; $script:fail++ }
}

$base = Import-Csv 'perf/results/baseline_laptop.csv'
$small = Import-Csv 'perf/results/baseline_1pct.csv'
Check "baseline has p50/p95/p99 for every query at both scales" (($base | Where-Object { -not $_.p99_ms }).Count -eq 0 -and ($small | Where-Object { -not $_.p99_ms }).Count -eq 0 -and $base.Count -eq $small.Count)

$idx = @(Import-Csv 'perf/results/index_experiments.csv') + @(Import-Csv 'perf/results/index_experiment_notif_queue.csv')
$modules = 'Profile', 'Jobs and applications', 'Administration', 'Organisation and account', 'Gig marketplace',
           'Licences, devices and sessions', 'Sourcing and consultant requests', 'Subscriptions, wallet and downloads', 'Notifications', 'Analytics'
$missing = @($modules | Where-Object { $m = $_; -not ($idx | Where-Object { $_.module -like "$m*" -and [double]$_.speedup -ge 2 }) })
Check ("every module has an index justified by a before/after measurement (speed-up >= 2)" + $(if ($missing) { ': missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
$plans = @($idx | Where-Object { $n = ($_.index -split '\.')[1]; -not ((Test-Path "perf/plans/${n}_before.txt") -and (Test-Path "perf/plans/${n}_after.txt")) })
Check "before and after plans saved for every index experiment" ($plans.Count -eq 0)

$ex = Import-Csv 'perf/results/extrapolation.csv'
$first = $ex | Where-Object { $_.degradation_rank -eq '1' }
Check "extrapolation covers every query and ranks one first" ($ex.Count -eq $base.Count -and $first)
$doc = Get-Content 'docs/phase5/m21_performance.md' -Raw
Check ("the report names the first query to degrade ({0})" -f $first.query) ($doc -match [regex]::Escape($first.query.Substring(0, 3)) -and $doc -match 'first query to degrade')
Check "the report contains the partitioning note" ($doc -match '(?m)^## 3\. Partitioning note')
if ($fail -gt 0) { exit 1 }
