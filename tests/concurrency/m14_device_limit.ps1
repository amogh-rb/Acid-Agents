# M14 gate (B45): the device limit holds under concurrent logins.
# 20 separate psql sessions call app.start_session for the same user at the same moment, each from a different
# device, against a licence that allows 3 devices per user. Expected: exactly 3 active sessions, 17 rejections,
# and 17 audited 'device_limit_exceeded' events.
# Unlike the SQL tests this one must COMMIT (separate sessions cannot see uncommitted rows). It uses its own
# account and user (unique names per run); the gate rebuilds the database before every run.
$ErrorActionPreference = 'Stop'
$psql = Join-Path $env:PGBIN 'psql.exe'
$db = $env:TALENTRA_DB
$tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$attempts = 20
$limit = 3

function Sql([string]$query) {
  $out = & $psql -X -q -t -A -v ON_ERROR_STOP=1 -d $db -c $query
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $query" }
  return ($out | Where-Object { $_ -ne '' } | Select-Object -Last 1)
}

# fixtures (committed)
$user = Sql @"
SET app.current_user_id = '1';
WITH a AS (INSERT INTO org.account (account_name, account_status_code) VALUES ('Concurrency $tag', 'active') RETURNING id),
     l AS (INSERT INTO lic.licence (account_id, licence_name, max_users, max_devices_per_user) SELECT id, 'Concurrency $tag', 1, $limit FROM a RETURNING id),
     u AS (INSERT INTO admin.app_user (user_status_code, login_email) VALUES ('active', 'concurrency.$tag@example.com') RETURNING id),
     s AS (INSERT INTO lic.licence_seat (licence_id, app_user_id) SELECT l.id, u.id FROM l, u RETURNING app_user_id)
SELECT app_user_id FROM s;
"@
if (-not $user) { Write-Output 'FAIL  could not create fixtures'; exit 1 }

# fire 20 logins at once; each process waits on a shared start time so they really overlap
$start = (Get-Date).AddSeconds(2).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
$procs = @()
$outs = @()
for ($i = 1; $i -le $attempts; $i++) {
  $outFile = Join-Path $env:TEMP "talentra_conc_${tag}_$i.txt"
  $outs += $outFile
  $q = "SET app.current_user_id = '$user'; SELECT pg_sleep(greatest(0, extract(epoch FROM (timestamptz '$start+00' - clock_timestamp())))); " +
       "SELECT outcome FROM app.start_session($user, digest('dev-$tag-$i', 'sha256'), digest('tok-$tag-$i', 'sha256'));"
  $procs += Start-Process -FilePath $psql -ArgumentList @('-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-d', $db, '-c', "`"$q`"") `
                          -NoNewWindow -PassThru -RedirectStandardOutput $outFile
}
$procs | Wait-Process -Timeout 60
$failedProcs = @($procs | Where-Object { $_.ExitCode -ne 0 }).Count
$outcomes = $outs | ForEach-Object { (Get-Content $_ -ErrorAction SilentlyContinue | Where-Object { $_ -match '^[a-z_]+$' } | Select-Object -Last 1) }
$outs | ForEach-Object { Remove-Item $_ -ErrorAction SilentlyContinue }

$started = @($outcomes | Where-Object { $_ -eq 'started' }).Count
$rejected = @($outcomes | Where-Object { $_ -eq 'device_limit' }).Count
$active = [int](Sql "SELECT count(*) FROM lic.login_session WHERE app_user_id = $user AND ended_at IS NULL AND expires_at > now();")
$audited = [int](Sql "SELECT count(*) FROM audit.audit_event WHERE audit_action_code = 'device_limit_exceeded' AND (event_detail ->> 'app_user_id')::bigint = $user;")
$history = [int](Sql "SELECT count(*) FROM lic.login_attempt WHERE app_user_id = $user AND login_outcome_code = 'device_limit';")

$ok = $true
function Check([string]$label, [bool]$cond, [string]$detail) {
  if ($cond) { Write-Output "PASS  $label" } else { Write-Output "FAIL  ${label}: $detail"; $script:ok = $false }
}
Check "$attempts concurrent logins all completed" ($failedProcs -eq 0 -and @($outcomes).Count -eq $attempts) "$failedProcs psql failures"
Check "exactly $limit sessions started" ($started -eq $limit -and $active -eq $limit) "started=$started active=$active"
Check "$($attempts - $limit) logins rejected at the device limit" ($rejected -eq ($attempts - $limit)) "rejected=$rejected"
Check "every rejection audited as device_limit_exceeded" ($audited -eq ($attempts - $limit)) "audited=$audited"
Check "every rejection in the login history" ($history -eq ($attempts - $limit)) "history=$history"
if (-not $ok) { exit 1 }
