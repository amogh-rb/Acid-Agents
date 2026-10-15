# M16 gate: Phase 4 relationship tables are valid against every phase's entities, and each module ERD is current.
$ents = (Get-ChildItem docs -Recurse -Filter '*entities.md' | Where-Object { $_.DirectoryName -match 'phase' } | Sort-Object FullName | ForEach-Object { Resolve-Path -Relative $_.FullName }) -join ','
foreach ($m in 'notif', 'dw') {
  python tools/reserved_words.py "docs/phase4/${m}_relationships.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py relations $ents "docs/phase4/${m}_relationships.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py erd $ents "docs/phase4/${m}_relationships.md" "docs/erd/phase4_${m}.mmd" --check
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
