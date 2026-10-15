-- M1: standard domains (docket Rule group 3). Every column holding one of these kinds of data uses the domain;
-- the catalog lint (tests/_qa/10_lint.sql) flags columns whose name implies a domain but do not use it.

-- Person name: up to 150 chars, any script, no word-order assumption. Empty string is not a "missing" value (RG5).
CREATE DOMAIN d_person_name AS varchar(150)
  CONSTRAINT ck_d_person_name_not_blank CHECK (btrim(VALUE) <> '');
COMMENT ON DOMAIN d_person_name IS 'Person name, UTF-8, max 150, any script or word order';

-- Email: max 254, stored lowercase. Plain varchar (not citext): lowercase storage makes a normal unique index
-- case-insensitive by construction. Format check is deliberately loose; deliverability is the provider's job.
CREATE DOMAIN d_email AS varchar(254)
  CONSTRAINT ck_d_email_lowercase CHECK (VALUE = lower(VALUE))
  CONSTRAINT ck_d_email_format    CHECK (VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
COMMENT ON DOMAIN d_email IS 'Email address, max 254, lowercase';

-- Phone: E.164 (+, country code, up to 15 digits). The country is a separate <col>_country_id column.
CREATE DOMAIN d_phone_e164 AS varchar(16)
  CONSTRAINT ck_d_phone_e164_format CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$');
COMMENT ON DOMAIN d_phone_e164 IS 'Phone number in E.164 format';

-- Money: fixed precision, never float. Sign is a per-column CHECK (ledgers may be signed).
-- Every d_money column has a companion <col>_currency_code or currency_code (lint-enforced).
CREATE DOMAIN d_money AS numeric(14,2);
COMMENT ON DOMAIN d_money IS 'Money amount, numeric(14,2); paired with an ISO 4217 currency code column';

CREATE DOMAIN d_currency_code AS char(3)
  CONSTRAINT ck_d_currency_code_format CHECK (VALUE ~ '^[A-Z]{3}$');
COMMENT ON DOMAIN d_currency_code IS 'ISO 4217 alphabetic currency code';

-- Percentage: 0-100 with two decimals. Ratios (0-1) are stored as percentages to keep one domain.
CREATE DOMAIN d_pct AS numeric(5,2)
  CONSTRAINT ck_d_pct_range CHECK (VALUE BETWEEN 0 AND 100);
COMMENT ON DOMAIN d_pct IS 'Percentage 0.00-100.00';

-- Coordinates: WGS84 decimal degrees, 6 dp (about 0.11 m). Source is recorded per table (geocoder or user pin).
CREATE DOMAIN d_lat AS numeric(9,6)
  CONSTRAINT ck_d_lat_range CHECK (VALUE BETWEEN -90 AND 90);
COMMENT ON DOMAIN d_lat IS 'Latitude, WGS84 decimal degrees, 6 dp';

CREATE DOMAIN d_lng AS numeric(9,6)
  CONSTRAINT ck_d_lng_range CHECK (VALUE BETWEEN -180 AND 180);
COMMENT ON DOMAIN d_lng IS 'Longitude, WGS84 decimal degrees, 6 dp';

-- Lookup code: the stable machine key of an enumeration row (RG3 Enumeration). Display text lives in ref.ui_translation.
CREATE DOMAIN d_code AS varchar(40)
  CONSTRAINT ck_d_code_format CHECK (VALUE ~ '^[a-z][a-z0-9_]*$');
COMMENT ON DOMAIN d_code IS 'Lookup code, lowercase snake_case, max 40';
