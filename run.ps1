<#
.SYNOPSIS
  Talentra build and gate runner (PowerShell 5.1+).

.EXAMPLE
  .\run.ps1 up                    # drop + recreate the database, apply ddl/*.sql in name order (ON_ERROR_STOP)
  .\run.ps1 gate M6               # up, load the test harness, run every test tagged m01..m06, PASS/FAIL per file
  .\run.ps1 test                  # gate for the highest milestone that has tests (run before every commit)
  .\run.ps1 test -Evidence        # same, and save the output under docs/evidence/
  .\run.ps1 lint                  # lint the current database without rebuilding it
  .\run.ps1 dict                  # export dictionary/columns.csv and dictionary/tables.csv from the catalog
  .\run.ps1 erd -Schemas ref,profile,job -Out docs/erd/phase1_generated.mmd
  .\run.ps1 settings              # print the server settings recorded in docs/04_environment.md
  .\run.ps1 psql                  # interactive psql on the database

  Connection settings come from .env (never committed; copy .env.example):
  PGHOST, PGPORT, PGUSER, PGPASSWORD, PGBIN, TALENTRA_DB
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('up', 'gate', 'test', 'lint', 'dict', 'erd', 'settings', 'psql')]
  [string]$Command = 'test',
  [Parameter(Position = 1)]
  [string]$Milestone,
  [string[]]$Schemas,
  [string]$Out = 'docs/erd/generated.mmd',
  [switch]$Evidence
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ---------- configuration ----------
if (Test-Path '.env') {
  foreach ($line in Get-Content '.env') {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
      Set-Item -Path ("env:" + $Matches[1]) -Value ($Matches[2].Trim('"', "'"))
    }
  }
}
if (-not $env:PGHOST)      { $env:PGHOST = 'localhost' }
if (-not $env:PGPORT)      { $env:PGPORT = '5432' }
if (-not $env:PGUSER)      { $env:PGUSER = 'postgres' }
if (-not $env:PGBIN)       { $env:PGBIN = 'C:\Program Files\PostgreSQL\18\bin' }
if (-not $env:TALENTRA_DB) { $env:TALENTRA_DB = 'talentra' }
$env:PGCLIENTENCODING = 'UTF8'
$Db = $env:TALENTRA_DB
$Psql = Join-Path $env:PGBIN 'psql.exe'
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql. Set PGBIN in .env." }

# ---------- output (mirrored into the evidence log) ----------
$script:Log = New-Object System.Collections.Generic.List[string]
function Say([string]$Text, [string]$Color = 'Gray') {
  Write-Host $Text -ForegroundColor $Color
  $script:Log.Add($Text)
}

# ---------- process helpers ----------
function Format-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
  return $a
}

function Invoke-Exe([string]$File, [string[]]$Arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.Arguments = ($Arguments | ForEach-Object { Format-Arg $_ }) -join ' '
  $psi.UseShellExecute = $false
  $psi.WorkingDirectory = $PSScriptRoot   # Set-Location does not change the .NET current directory
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEndAsync()
  $stderr = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
}

function Invoke-Psql([string[]]$Arguments, [string]$Database = $Db) {
  Invoke-Exe $Psql (@('-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', $Database) + $Arguments)
}

# psql prefixes script messages with "psql:<file>:<line>: "; strip it for readable output.
function Get-Lines([string]$Text) {
  if (-not $Text) { return @() }
  $Text -split "`r?`n" | Where-Object { $_ -ne '' } | ForEach-Object { $_ -replace '^psql:[^:]+:\d+:\s*', '' }
}

function Assert-Ok($Result, [string]$What) {
  if ($Result.Code -ne 0) {
    Say "FAIL  $What" 'Red'
    foreach ($l in (Get-Lines ($Result.Out + "`n" + $Result.Err))) { Say "      $l" 'Red' }
    throw "$What failed"
  }
}

# ---------- commands ----------
function Invoke-Up {
  $r = Invoke-Psql -Database 'postgres' -Arguments @(
    '-c', "DROP DATABASE IF EXISTS $Db WITH (FORCE)",
    '-c', "CREATE DATABASE $Db TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER icu ICU_LOCALE 'und' LOCALE 'C'")
  Assert-Ok $r "create database $Db"
  $files = @(Get-ChildItem 'ddl' -Filter '*.sql' | Sort-Object Name)
  foreach ($f in $files) {
    Assert-Ok (Invoke-Psql -Arguments @('-f', "ddl/$($f.Name)")) "ddl/$($f.Name)"
  }
  Say "up    $Db rebuilt from $($files.Count) ddl files" 'Green'
}

function Import-Harness {
  Assert-Ok (Invoke-Psql -Arguments @('-c', 'DROP SCHEMA IF EXISTS qa CASCADE')) 'drop qa'
  foreach ($f in (Get-ChildItem 'tests/_qa' -Filter '*.sql' | Sort-Object Name)) {
    Assert-Ok (Invoke-Psql -Arguments @('-f', "tests/_qa/$($f.Name)")) "tests/_qa/$($f.Name)"
  }
}

function Get-TestFiles([int]$Upto) {
  Get-ChildItem 'tests' -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\_qa\\' } |
    ForEach-Object {
      if ($_.Name -match '^m(\d{2})_.*\.(sql|ps1)$') {
        [pscustomobject]@{
          Num  = [int]$Matches[1]
          Rel  = (Resolve-Path -Relative $_.FullName) -replace '^\.\\', '' -replace '\\', '/'
          Kind = $Matches[2]
        }
      }
    } |
    Where-Object { $_.Num -le $Upto } |
    Sort-Object Num, Rel
}

function Invoke-TestFile($t) {
  if ($t.Kind -eq 'sql') {
    # Each SQL test file runs in one transaction that is always rolled back.
    $r = Invoke-Psql -Arguments @('-c', 'BEGIN', '-f', $t.Rel, '-c', 'ROLLBACK')
  } else {
    $r = Invoke-Exe 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $t.Rel)
  }
  $lines = @(Get-Lines ($r.Out + "`n" + $r.Err))
  if ($r.Code -eq 0) {
    $checks = @($lines | Where-Object { $_ -match 'PASS ' }).Count
    Say ("PASS  {0}  ({1} checks)" -f $t.Rel, $checks) 'Green'
    foreach ($l in $lines) {
      if ($l -match '(PASS .*)$') { Say ("        " + $Matches[1]) 'DarkGray' }
    }
    return $true
  }
  Say "FAIL  $($t.Rel)" 'Red'
  foreach ($l in $lines) { Say "        $l" 'Red' }
  return $false
}

function Invoke-Gate([int]$Upto) {
  $label = 'M{0:D2}' -f $Upto
  Say ("== gate {0}  ({1:yyyy-MM-dd HH:mm:ss}, db {2}) ==" -f $label, (Get-Date), $Db) 'Cyan'
  Invoke-Up
  Import-Harness
  $tests = @(Get-TestFiles $Upto)
  if ($tests.Count -eq 0) { throw "no test files tagged m01..$($label.ToLower())" }
  $failed = 0
  foreach ($t in $tests) { if (-not (Invoke-TestFile $t)) { $failed++ } }
  if ($failed -eq 0) {
    Say ("== gate {0}: PASS ({1}/{1} files) ==" -f $label, $tests.Count) 'Green'
  } else {
    Say ("== gate {0}: FAIL ({1} of {2} files failed) ==" -f $label, $failed, $tests.Count) 'Red'
  }
  return ($failed -eq 0)
}

function Save-Evidence([string]$Name) {
  if (-not $Evidence) { return }
  $path = 'docs/evidence/{0}_{1:yyyyMMdd_HHmm}.txt' -f $Name, (Get-Date)
  New-Item -ItemType Directory -Force 'docs/evidence' | Out-Null
  [System.IO.File]::WriteAllLines((Join-Path $PSScriptRoot $path), $script:Log, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "evidence saved to $path" -ForegroundColor Cyan
}

$ok = $true
try {
  switch ($Command) {
    'up' { Invoke-Up }
    'gate' {
      if ($Milestone -notmatch '^[Mm]?(\d{1,2})$') { throw 'usage: .\run.ps1 gate M6' }
      $ok = Invoke-Gate ([int]$Matches[1])
      Save-Evidence ('gate_M{0:D2}' -f [int]$Matches[1])
    }
    'test' {
      $max = (Get-TestFiles 99 | Measure-Object -Property Num -Maximum).Maximum
      $ok = Invoke-Gate ([int]$max)
      Save-Evidence 'test'
    }
    'lint' {
      Import-Harness
      $ok = $true
      foreach ($t in (Get-ChildItem 'tests/lint' -Filter 'm*.sql' | Sort-Object Name)) {
        if (-not (Invoke-TestFile ([pscustomobject]@{ Rel = "tests/lint/$($t.Name)"; Kind = 'sql' }))) { $ok = $false }
      }
    }
    'dict' {
      New-Item -ItemType Directory -Force 'dictionary' | Out-Null
      Assert-Ok (Invoke-Psql -Arguments @('-f', 'tools/export_dictionary.sql')) 'export dictionary'
      Say 'dict  dictionary/columns.csv, dictionary/tables.csv written (ERD: run.ps1 erd)' 'Green'
    }
    'erd' {
      $list = ($Schemas -join ',')
      Assert-Ok (Invoke-Psql -Arguments @('-v', "schemas=$list", '-o', $Out, '-f', 'tools/export_erd.sql')) 'export erd'
      Say "erd   $Out written (schemas: $(if ($list) { $list } else { 'all' }))" 'Green'
    }
    'settings' {
      $r = Invoke-Psql -Database 'postgres' -Arguments @('-f', 'tools/pg_settings.sql')
      Assert-Ok $r 'settings'
      Write-Host $r.Out
    }
    'psql' { & $Psql -X -d $Db }
  }
} catch {
  Say "ERROR $($_.Exception.Message)" 'Red'
  $ok = $false
}
if (-not $ok) { exit 1 }
