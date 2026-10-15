# M7 gate: Phase 2 entity lists (Administration, Organisation and account, Gig) are well-formed and name-safe.
foreach ($m in 'admin', 'org', 'gig') {
  python tools/reserved_words.py "docs/phase2/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py entities "docs/phase2/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
