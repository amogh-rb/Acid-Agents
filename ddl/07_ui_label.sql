-- M1: UI label and translation base (RG3 "UI label", RG7 multilingual). Every lookup's label_key points here.
-- Fallback rule: requested language, then the single default language (is_default, seeded as English).
-- Keys are never shown to users: ref.ui_text() returns NULL rather than the key when no translation exists.

SET app.current_user_id = '1';   -- system actor for seed rows (admin.app_user id 1 is created in ddl/15_stubs.sql)

CREATE TABLE ref.ui_label (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  label_key        varchar(150) NOT NULL,
  translator_note  varchar(300),
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  updated_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_ui_label PRIMARY KEY (id),
  CONSTRAINT uq_ui_label_label_key UNIQUE (label_key),
  CONSTRAINT ck_ui_label_label_key_format CHECK (label_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$')
);
COMMENT ON TABLE  ref.ui_label IS '[hard-delete] UI string key; one row per key, translations in ref.ui_translation';
COMMENT ON COLUMN ref.ui_label.label_key IS '[Public] Dotted key, for example enum.application_status.applied; never displayed';
COMMENT ON COLUMN ref.ui_label.translator_note IS '[Internal] Context for translators; null: key is self-explanatory';

CREATE TABLE ref.language (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  code             d_code       NOT NULL,
  bcp47_tag        varchar(35)  NOT NULL,
  native_name      varchar(100) NOT NULL,
  label_key        varchar(150) NOT NULL,
  is_ui_supported  boolean      NOT NULL DEFAULT false,
  is_default       boolean      NOT NULL DEFAULT false,
  is_active        boolean      NOT NULL DEFAULT true,
  sort_order       integer      NOT NULL DEFAULT 0,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  updated_by       bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_language PRIMARY KEY (id),
  CONSTRAINT uq_language_code UNIQUE (code),
  CONSTRAINT uq_language_bcp47_tag UNIQUE (bcp47_tag),
  CONSTRAINT fk_language_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_language_sort_order CHECK (sort_order >= 0),
  CONSTRAINT ck_language_default_is_ui CHECK (NOT is_default OR (is_ui_supported AND is_active))
);
CREATE UNIQUE INDEX uq_language_is_default ON ref.language (is_default) WHERE is_default;
COMMENT ON TABLE  ref.language IS '[hard-delete] Lookup: languages for UI, profiles and user-entered content. Exactly one default (fallback) language.';
COMMENT ON COLUMN ref.language.code IS '[Public] Stable machine code, lowercase snake_case (en, hi, zh_hans)';
COMMENT ON COLUMN ref.language.bcp47_tag IS '[Public] BCP 47 language tag (en, hi, zh-Hans)';
COMMENT ON COLUMN ref.language.native_name IS '[Public] Language name in its own script (endonym)';
COMMENT ON COLUMN ref.language.label_key IS '[Public] UI label key for the language name in other UI languages';
COMMENT ON COLUMN ref.language.is_ui_supported IS '[Public] true when the UI is translated into this language; default false';
COMMENT ON COLUMN ref.language.is_default IS '[Public] true for the single fallback language; default false';
COMMENT ON COLUMN ref.language.is_active IS '[Public] false hides the language from new use; default true';
COMMENT ON COLUMN ref.language.sort_order IS '[Public] Display order, ascending; default 0';

CREATE TABLE ref.ui_translation (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  ui_label_id      bigint        NOT NULL,
  language_id      bigint        NOT NULL,
  translated_text  varchar(1000) NOT NULL,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  created_by       bigint        NOT NULL DEFAULT public.current_actor_id(),
  updated_at       timestamptz   NOT NULL DEFAULT now(),
  updated_by       bigint        NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_ui_translation PRIMARY KEY (id),
  CONSTRAINT uq_ui_translation_ui_label_id_language_id UNIQUE (ui_label_id, language_id),
  CONSTRAINT fk_ui_translation_ui_label_id FOREIGN KEY (ui_label_id) REFERENCES ref.ui_label (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_ui_translation_language_id FOREIGN KEY (language_id) REFERENCES ref.language (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_ui_translation_translated_text_not_blank CHECK (btrim(translated_text) <> '')
);
CREATE INDEX idx_ui_translation_language_id ON ref.ui_translation (language_id);
COMMENT ON TABLE  ref.ui_translation IS '[hard-delete] Translation of one UI label into one language (CASCADE: owned by the label)';
COMMENT ON COLUMN ref.ui_translation.ui_label_id IS '[Public] Label being translated';
COMMENT ON COLUMN ref.ui_translation.language_id IS '[Public] Language of translated_text';
COMMENT ON COLUMN ref.ui_translation.translated_text IS '[Public] Display text shown to users, max 1000';

-- Resolve a key for a language with fallback to the default language. NULL when untranslated (key is never shown).
CREATE FUNCTION ref.ui_text(p_label_key text, p_language_code text) RETURNS varchar
LANGUAGE sql STABLE AS
$$
  SELECT t.translated_text
    FROM ref.ui_label l
    JOIN ref.ui_translation t ON t.ui_label_id = l.id
    JOIN ref.language lang    ON lang.id = t.language_id
   WHERE l.label_key = p_label_key
     AND (lang.code = p_language_code OR lang.is_default)
   ORDER BY (lang.code = p_language_code) DESC
   LIMIT 1
$$;

-- Seed: languages used by the UI, profiles and the multilingual seed data.
INSERT INTO ref.ui_label (label_key, translator_note)
SELECT 'language.' || code, 'Name of the language ' || code
  FROM (VALUES ('en'),('hi'),('ta'),('te'),('kn'),('ml'),('mr'),('bn'),('gu'),('pa'),('ur'),('ar'),('zh_hans'),('fr'),('de'),('es')) v(code);

INSERT INTO ref.language (code, bcp47_tag, native_name, label_key, is_ui_supported, is_default, sort_order)
VALUES ('en',      'en',      'English',   'language.en',      true,  true,  1),
       ('hi',      'hi',      'हिन्दी',      'language.hi',      true,  false, 2),
       ('ta',      'ta',      'தமிழ்',      'language.ta',      true,  false, 3),
       ('te',      'te',      'తెలుగు',     'language.te',      false, false, 4),
       ('kn',      'kn',      'ಕನ್ನಡ',      'language.kn',      false, false, 5),
       ('ml',      'ml',      'മലയാളം',    'language.ml',      false, false, 6),
       ('mr',      'mr',      'मराठी',      'language.mr',      false, false, 7),
       ('bn',      'bn',      'বাংলা',      'language.bn',      false, false, 8),
       ('gu',      'gu',      'ગુજરાતી',     'language.gu',      false, false, 9),
       ('pa',      'pa',      'ਪੰਜਾਬੀ',      'language.pa',      false, false, 10),
       ('ur',      'ur',      'اردو',       'language.ur',      false, false, 11),
       ('ar',      'ar',      'العربية',    'language.ar',      false, false, 12),
       ('zh_hans', 'zh-Hans', '简体中文',    'language.zh_hans', false, false, 13),
       ('fr',      'fr',      'Français',  'language.fr',      false, false, 14),
       ('de',      'de',      'Deutsch',   'language.de',      false, false, 15),
       ('es',      'es',      'Español',   'language.es',      false, false, 16);

INSERT INTO ref.ui_translation (ui_label_id, language_id, translated_text)
SELECT l.id, en.id, v.english_name
  FROM (VALUES ('en','English'),('hi','Hindi'),('ta','Tamil'),('te','Telugu'),('kn','Kannada'),('ml','Malayalam'),
               ('mr','Marathi'),('bn','Bengali'),('gu','Gujarati'),('pa','Punjabi'),('ur','Urdu'),('ar','Arabic'),
               ('zh_hans','Chinese (Simplified)'),('fr','French'),('de','German'),('es','Spanish')) v(code, english_name)
  JOIN ref.ui_label l ON l.label_key = 'language.' || v.code
  JOIN ref.language en ON en.code = 'en';
