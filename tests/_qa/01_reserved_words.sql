-- Loads the MySQL reserved-word list (single source: tools/mysql_reserved_words.txt). psql runs from the repo root.
CREATE TEMP TABLE tmp_word (line text);
\copy tmp_word (line) FROM 'tools/mysql_reserved_words.txt'
INSERT INTO qa.mysql_reserved_word (word)
SELECT DISTINCT lower(btrim(line)) FROM tmp_word WHERE btrim(line) <> '' AND line NOT LIKE '#%';
