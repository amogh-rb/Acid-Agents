"""Validate the Phase design docs and render the design ERD from them.

  python tools/design_docs.py entities  ENTITIES.md
  python tools/design_docs.py relations ENTITIES.md RELATIONSHIPS.md
  python tools/design_docs.py erd       ENTITIES.md RELATIONSHIPS.md OUT.mmd [--check]

entities:   unique names, schema, delete class, tier and owner are valid.
relations:  every child and parent is a known entity; parent schema matches; cardinality,
            optional and ON DELETE values are valid; FK column is [role_]<parent>_id|_code;
            optional rows give a NULL reason; CASCADE rows say the child is owned;
            SET NULL only on optional FKs.
erd:        writes a Mermaid erDiagram from the relationship table (--check: fail if OUT differs).
Rows whose child cell starts with '(' (for example "(each lookup).label_key") are notes, not checked.
"""
import pathlib
import re
import sys

DELETE_CLASSES = {"soft-delete", "hard-delete", "append-only", "derived"}
TIERS = {"1", "2", "3", "ref"}
OWNERS = {"A", "B", "C"}
CARDINALITIES = {"N:1", "1:1"}
ON_DELETE = {"RESTRICT", "CASCADE", "SET NULL", "NO ACTION"}


def clean(cell):
    return cell.replace("`", "").replace("*", "").strip()


def read_tables(path):
    """Yield (lineno, {header: cell}) for every markdown table row."""
    headers = None
    for lineno, line in enumerate(pathlib.Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip().startswith("|"):
            headers = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if headers is None:
            headers = [clean(c).lower() for c in cells]
            continue
        if all(re.fullmatch(r":?-{3,}:?", c) for c in cells if c):
            continue
        yield lineno, dict(zip(headers, cells))


def load_entities(path, problems):
    entities = {}
    for lineno, row in read_tables(path):
        if "entity" not in row or "delete class" not in row:
            continue
        name = clean(row["entity"])
        where = f"{path}:{lineno}: {name}"
        if name in entities:
            problems.append(f"{where}: duplicate entity")
        entities[name] = clean(row.get("schema", ""))
        if clean(row["delete class"]) not in DELETE_CLASSES:
            problems.append(f"{where}: delete class '{row['delete class']}' not in {sorted(DELETE_CLASSES)}")
        if clean(row.get("tier", "")) not in TIERS:
            problems.append(f"{where}: tier '{row.get('tier')}' not in {sorted(TIERS)}")
        if clean(row.get("owner", "")) not in OWNERS:
            problems.append(f"{where}: owner '{row.get('owner')}' not in {sorted(OWNERS)}")
        if not clean(row.get("purpose (one line)", "")):
            problems.append(f"{where}: purpose is empty")
        if not entities[name]:
            problems.append(f"{where}: schema is empty")
    return entities


def load_relations(path, entities, problems):
    relations = []
    for lineno, row in read_tables(path):
        if "child.column" not in row:
            continue
        child_cell = clean(row["child.column"])
        if child_cell.startswith("("):
            continue
        where = f"{path}:{lineno}: {child_cell}"
        if child_cell.count(".") != 1:
            problems.append(f"{where}: child.column must be table.column")
            continue
        child, column = child_cell.split(".")
        parent_cell = clean(row.get("parent", ""))
        if parent_cell.count(".") != 1:
            problems.append(f"{where}: parent must be schema.table")
            continue
        parent_schema, parent = parent_cell.split(".")
        card = clean(row.get("cardinality", ""))
        optional = clean(row.get("optional?", "")).lower()
        on_delete = clean(row.get("on delete", "")).upper()
        reason = clean(row.get("reason", ""))

        if child not in entities:
            problems.append(f"{where}: child table '{child}' is not in the entity list")
        if parent not in entities:
            problems.append(f"{where}: parent '{parent}' is not in the entity list")
        elif entities[parent] != parent_schema:
            problems.append(f"{where}: parent schema '{parent_schema}' but entity list says '{entities[parent]}'")
        if card not in CARDINALITIES:
            problems.append(f"{where}: cardinality '{card}' not in {sorted(CARDINALITIES)}")
        if optional not in {"yes", "no"}:
            problems.append(f"{where}: optional? must be yes or no")
        if on_delete not in ON_DELETE:
            problems.append(f"{where}: ON DELETE '{on_delete}' not in {sorted(ON_DELETE)}")
        if not re.fullmatch(rf"([a-z0-9_]+_)?{re.escape(parent)}_(id|code)", column):
            problems.append(f"{where}: FK column should be [role_]{parent}_id or [role_]{parent}_code (RG1)")
        if not reason:
            problems.append(f"{where}: reason is empty")
        if optional == "yes" and "null" not in reason.lower():
            problems.append(f"{where}: optional FK needs a reason that says what NULL means")
        if on_delete == "CASCADE" and "own" not in reason.lower():
            problems.append(f"{where}: CASCADE is only for owned children; say so in the reason")
        if on_delete == "SET NULL" and optional != "yes":
            problems.append(f"{where}: SET NULL needs an optional FK")
        relations.append((child, column, parent_schema, parent, card, optional))
    return relations


def render_erd(entities, relations):
    lines = ["erDiagram",
             "  %% Design ERD generated from docs/phase1/relationships.md by tools/design_docs.py.",
             "  %% Entity = <schema>__<table>. Actor FKs (created_by/updated_by -> app_user) and lookup label_key FKs omitted.",
             "  %% ||--o{ mandatory parent, |o--o{ optional parent, --o| one-to-one."]
    for child, column, parent_schema, parent, card, optional in sorted(relations, key=lambda r: (r[3], r[0], r[1])):
        left = "||" if optional == "no" else "|o"
        right = "o|" if card == "1:1" else "o{"
        child_ent = f"{entities.get(child, '?')}__{child}"
        lines.append(f"  {parent_schema}__{parent} {left}--{right} {child_ent} : \"{column}\"")
    return "\n".join(lines) + "\n"


def report(problems, ok_message):
    for p in problems:
        print(p)
    if problems:
        print(f"FAIL  {len(problems)} problem(s)")
        return 1
    print(f"PASS  {ok_message}")
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    command, problems = argv[0], []
    entities = load_entities(argv[1], problems)
    if command == "entities":
        return report(problems, f"{len(entities)} entities: unique, schema, delete class, tier and owner valid")
    relations = load_relations(argv[2], entities, problems)
    if command == "relations":
        return report(problems, f"{len(relations)} relationships: known entities, naming, cardinality, ON DELETE and reasons valid")
    if command == "erd":
        out = pathlib.Path(argv[3])
        text = render_erd(entities, relations)
        if "--check" in argv:
            current = out.read_text(encoding="utf-8") if out.exists() else ""
            if current.replace("\r\n", "\n") != text:
                problems.append(f"{out} is out of date; run: python tools/design_docs.py erd {argv[1]} {argv[2]} {out}")
            return report(problems, f"{out} matches the relationship table ({len(relations)} lines)")
        out.write_text(text, encoding="utf-8", newline="\n")
        return report(problems, f"{out} written ({len(relations)} relationships)")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
