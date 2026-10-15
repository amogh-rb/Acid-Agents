# M5 gate: the data dictionary is complete and cannot drift; the design docs match the built database.
#  1. Export the dictionary from the fresh database into a temp folder.
#  2. Row count equals information_schema column count; every row has a class; every NULL row has a reason.
#  3. The committed dictionary/*.csv equals the fresh export (regenerate with .\run.ps1 dict).
#  4. entities.md / relationships.md match the catalog (tables, delete classes, FKs, ON DELETE, nullability).
$ErrorActionPreference = 'Stop'
$psql = Join-Path $env:PGBIN 'psql.exe'
$out = Join-Path $env:TEMP ('talentra_dict_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $out | Out-Null
try {
  & $psql -X -q -v ON_ERROR_STOP=1 -d $env:TALENTRA_DB -v ("outdir=" + ($out -replace '\\', '/')) -f tools/export_dictionary.sql
  if ($LASTEXITCODE -ne 0) { exit 1 }

  $cols = Import-Csv (Join-Path $out 'columns.csv')
  $expected = [int](& $psql -X -q -t -A -d $env:TALENTRA_DB -c "SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name) WHERE t.table_type = 'BASE TABLE' AND c.table_schema NOT IN ('pg_catalog','information_schema','qa')")
  if ($cols.Count -ne $expected) { Write-Output "FAIL  dictionary has $($cols.Count) rows, information_schema has $expected base-table columns"; exit 1 }
  Write-Output "PASS  dictionary rows = information_schema base-table columns ($expected)"

  $noClass = @($cols | Where-Object { -not $_.sensitive_class })
  $noReason = @($cols | Where-Object { $_.nullability -eq 'NULL' -and -not $_.null_reason })
  if ($noClass.Count -gt 0 -or $noReason.Count -gt 0) {
    $noClass | ForEach-Object { Write-Output "no class: $($_.schema_name).$($_.table_name).$($_.column_name)" }
    $noReason | ForEach-Object { Write-Output "no null reason: $($_.schema_name).$($_.table_name).$($_.column_name)" }
    Write-Output 'FAIL  dictionary rows without class or null reason'; exit 1
  }
  Write-Output "PASS  every dictionary row has a sensitive class; every nullable row has a reason"

  foreach ($f in 'columns.csv', 'tables.csv') {
    $fresh = (Get-Content (Join-Path $out $f) -Raw -Encoding UTF8) -replace "`r`n", "`n"
    $committed = if (Test-Path "dictionary/$f") { (Get-Content "dictionary/$f" -Raw -Encoding UTF8) -replace "`r`n", "`n" } else { '' }
    if ($fresh -ne $committed) { Write-Output "FAIL  dictionary/$f is out of date; run .\run.ps1 dict and commit"; exit 1 }
  }
  Write-Output 'PASS  committed dictionary/*.csv equals the fresh catalog export'

  python tools/design_docs.py compare docs/phase1/entities.md docs/phase1/relationships.md (Join-Path $out 'columns.csv') (Join-Path $out 'tables.csv')
  if ($LASTEXITCODE -ne 0) { exit 1 }
} finally {
  Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
}
