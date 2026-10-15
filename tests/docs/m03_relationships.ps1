# M3 gate: relationship rows are valid against the entity list, and the design ERD is in step with them.
python tools/reserved_words.py docs/phase1/relationships.md
if ($LASTEXITCODE -ne 0) { exit 1 }
python tools/design_docs.py relations docs/phase1/entities.md docs/phase1/relationships.md
if ($LASTEXITCODE -ne 0) { exit 1 }
python tools/design_docs.py erd docs/phase1/entities.md docs/phase1/relationships.md docs/erd/phase1.mmd --check
if ($LASTEXITCODE -ne 0) { exit 1 }
