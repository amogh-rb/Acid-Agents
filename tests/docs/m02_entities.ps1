# M2 gate: entity names are snake_case, singular and not reserved; entity rows are complete.
python tools/reserved_words.py docs/phase1/entities.md
if ($LASTEXITCODE -ne 0) { exit 1 }
python tools/design_docs.py entities docs/phase1/entities.md
if ($LASTEXITCODE -ne 0) { exit 1 }
