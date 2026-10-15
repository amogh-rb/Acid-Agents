"""Check entity, table and column names in design documents before they become DDL.

Reads markdown tables and checks every name found in a column headed entity, table, parent,
column, child.column or name:
  * snake_case (RG1)
  * not a reserved word in PostgreSQL (pg_reserved_words.txt) or MySQL (mysql_reserved_words.txt)
  * table names are singular (RG1)

Usage:  python tools/reserved_words.py docs/phase1/entities.md [more files ...]
Exit code 1 when any problem is found.
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
NAME_HEADERS = {"entity", "table", "parent", "column", "child.column", "name"}
TABLE_HEADERS = {"entity", "table", "parent"}
SNAKE = re.compile(r"^[a-z][a-z0-9_]*$")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")


def load_words(filename):
    lines = (HERE / filename).read_text(encoding="utf-8").splitlines()
    return {w.strip().lower() for w in lines if w.strip() and not w.startswith("#")}


RESERVED = load_words("pg_reserved_words.txt") | load_words("mysql_reserved_words.txt")


def looks_plural(name):
    return name.endswith("s") and not name.endswith(("ss", "us", "is"))


def split_row(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def check_name(raw, header):
    """Return problems for one cell. 'profile.candidate_skill' checks every part.
    Cells starting with '(' are notes such as "(each lookup).label_key" and are skipped."""
    text = raw.replace("`", "").replace("*", "").strip()
    if text.startswith("("):
        return []
    match = IDENT.search(text)
    if not match:
        return []
    parts = [p for p in match.group(0).split(".") if p]
    problems = []
    for part in parts:
        if not SNAKE.match(part):
            problems.append(f"'{part}' is not snake_case")
        if part.lower() in RESERVED:
            problems.append(f"'{part}' is a reserved word (PostgreSQL or MySQL)")
    if header in TABLE_HEADERS:
        table = parts[-1]
    elif len(parts) >= 2:
        table = parts[-2]          # schema.table.column or table.column
    else:
        table = None
    if table and looks_plural(table):
        problems.append(f"table '{table}' looks plural; use a singular noun")
    return problems


def check_file(path):
    problems = []
    checked = 0
    headers = None
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip().startswith("|"):
            headers = None
            continue
        cells = split_row(line)
        if headers is None:
            headers = [c.lower().strip("` ") for c in cells]
            continue
        if all(re.fullmatch(r":?-{3,}:?", c) for c in cells if c):
            continue
        for header, cell in zip(headers, cells):
            if header in NAME_HEADERS and cell:
                checked += 1
                for p in check_name(cell, header):
                    problems.append(f"{path}:{lineno}: {p}")
    return checked, problems


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    total, all_problems = 0, []
    for arg in argv:
        checked, problems = check_file(pathlib.Path(arg))
        total += checked
        all_problems += problems
    for p in all_problems:
        print(p)
    if all_problems:
        print(f"FAIL  {len(all_problems)} problem(s) in {total} names")
        return 1
    print(f"PASS  {total} names checked: snake_case, singular, no PostgreSQL/MySQL reserved words")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
