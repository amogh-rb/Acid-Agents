# M11 gate: Phase 3 entity lists (Licences, Sourcing, Subscriptions) are well-formed and name-safe.
foreach ($m in 'lic', 'src', 'billing') {
  python tools/reserved_words.py "docs/phase3/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py entities "docs/phase3/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
