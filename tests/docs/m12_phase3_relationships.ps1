# M12 gate: Phase 3 relationship tables are valid against every phase's entities, and each module ERD is current.
$ents = (Get-ChildItem docs -Recurse -Filter '*entities.md' | Where-Object { $_.DirectoryName -match 'phase' } | Sort-Object FullName | ForEach-Object { Resolve-Path -Relative $_.FullName }) -join ','
foreach ($m in 'lic', 'src', 'billing') {
  python tools/reserved_words.py "docs/phase3/${m}_relationships.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py relations $ents "docs/phase3/${m}_relationships.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py erd $ents "docs/phase3/${m}_relationships.md" "docs/erd/phase3_${m}.mmd" --check
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
