# M15 gate: Phase 4 entity lists (Notifications, Analytics) are well-formed and name-safe.
foreach ($m in 'notif', 'dw') {
  python tools/reserved_words.py "docs/phase4/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
  python tools/design_docs.py entities "docs/phase4/${m}_entities.md"
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
