"""Draft a module's entity and relationship tables from its DDL file and the built catalog.

  python tools/draft_design_docs.py <ddl file> <module name> <owner> <out prefix> [--tier2 table,table]

Reads tables the DDL file creates (CREATE TABLE, ref.create_lookup, ALTER TABLE of a stub) and, from the
dictionary export (dictionary/columns.csv, tables.csv; run .\\run.ps1 dict first), writes:
  <out prefix>_entities.md       entity | schema | module | purpose | tier | delete class | owner
  <out prefix>_relationships.md  child.column | parent | cardinality | optional? | ON DELETE | reason
Purposes and reasons come from the table and column comments (the comment contract), so the docs say
exactly what the DDL says. FKs already documented in docs/phase1/relationships.md are not repeated.
Review the drafts by hand, then validate with tools/design_docs.py (relations / compare).
"""
import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF = re.compile(r"([a-z0-9_]+)\.([a-z0-9_]+)\(([a-z0-9_]+)\) ON DELETE (RESTRICT|CASCADE|SET NULL|NO ACTION|SET DEFAULT)")
SKIP_COLUMNS = {"created_by", "updated_by", "label_key"}


def strip_tag(text):
    return re.sub(r"^\[[A-Za-z-]+\]\s*", "", re.sub(r"\s*\[(integration|api)-write\]", "", text or "")).strip()


def main(argv):
    ddl, module, owner, prefix = argv[:4]
    tier2 = set(argv[argv.index("--tier2") + 1].split(",")) if "--tier2" in argv else set()
    sql = pathlib.Path(ddl).read_text(encoding="utf-8")
    created = re.findall(r"CREATE TABLE ([a-z_]+)\.([a-z0-9_]+) \(", sql)
    lookups = [tuple(x.split(".")) for x in re.findall(r"create_lookup\('([a-z_]+\.[a-z0-9_]+)'", sql)]
    extended = re.findall(r"ALTER TABLE ([a-z_]+)\.([a-z0-9_]+)\s*\n\s*ADD COLUMN", sql)
    tables = list(dict.fromkeys(extended + lookups + created))

    with open(ROOT / "dictionary/tables.csv", encoding="utf-8", newline="") as f:
        tmeta = {(r["schema_name"], r["table_name"]): r for r in csv.DictReader(f)}
    with open(ROOT / "dictionary/columns.csv", encoding="utf-8", newline="") as f:
        cols = [r for r in csv.DictReader(f)]
    documented = set()
    for line in (ROOT / "docs/phase1/relationships.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\| ([a-z0-9_]+)\.([a-z0-9_]+) \|", line)
        if m:
            documented.add(m.groups())

    lookup_set = set(lookups)
    ent = ["| entity | schema | module | purpose (one line) | tier | delete class | owner |",
           "|---|---|---|---|---|---|---|"]
    for schema, name in tables:
        t = tmeta[(schema, name)]
        tier = "ref" if (schema, name) in lookup_set else ("2" if name in tier2 else "1")
        purpose = strip_tag(t["description"]).replace("|", "/")
        if (schema, name) in extended:
            purpose = "Stub from Phase 1, extended here: " + purpose
        ent.append(f"| {name} | {schema} | {module} | {purpose} | {tier} | {t['delete_class']} | {owner} |")

    rel = ["| child.column | parent | cardinality | optional? | ON DELETE | reason |", "|---|---|---|---|---|---|"]
    for r in cols:
        key = (r["schema_name"], r["table_name"])
        if key not in set(tables) or r["column_name"] in SKIP_COLUMNS or not r["references_to"]:
            continue
        if (r["table_name"], r["column_name"]) in documented:
            continue
        refs = REF.findall(r["references_to"])
        simple = [x for x in refs if x[2] in ("id", "code")]
        ps, pt, pc, od = (simple or refs)[0]
        parent = f"{ps}.{pt}" if pc in ("id", "code") else f"{ps}.{pt}({pc})"
        optional = "yes" if r["nullability"] == "NULL" else "no"
        desc = r["description"].replace("|", "/").rstrip(".")
        if optional == "yes":
            reason = f"NULL: {r['null_reason']}. {desc}"
        else:
            reason = desc
        if od == "CASCADE":
            reason = "Owned child: " + reason
        card = "1:1" if "(unique" in desc.lower() or "unique)" in desc.lower() else "N:1"
        rel.append(f"| {r['table_name']}.{r['column_name']} | {parent} | {card} | {optional} | {od} | {reason} |")

    pathlib.Path(prefix + "_entities.md").write_text("\n".join(ent) + "\n", encoding="utf-8", newline="\n")
    pathlib.Path(prefix + "_relationships.md").write_text("\n".join(rel) + "\n", encoding="utf-8", newline="\n")
    print(f"drafted {len(ent) - 2} entities and {len(rel) - 2} relationships -> {prefix}_*.md")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
