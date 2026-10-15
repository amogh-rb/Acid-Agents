-- M19 seed, step 0: parameters, deterministic random helper, multilingual name pools.
\ir _preamble.sql

CREATE SCHEMA seed;

-- PostgreSQL has no round(double precision, integer); the seed formulas mix random() doubles with rounding to -2/-3 digits
CREATE FUNCTION public.round(double precision, integer) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT round($1::numeric, $2) $$;

CREATE TABLE seed.params AS
SELECT :candidates::bigint    AS n_cand,
       :jobs::bigint          AS n_job,
       :applications::bigint  AS n_app,
       :organisations::bigint AS n_org,
       :gig_workers::bigint   AS n_gw,
       :gig_requests::bigint  AS n_gig;
ALTER TABLE seed.params
  ADD COLUMN n_hiring     bigint,      -- organisations that employ recruiters (employer + staffing agency)
  ADD COLUMN n_rec        bigint,      -- recruiters (2 per hiring organisation)
  ADD COLUMN n_consult    bigint,
  ADD COLUMN n_requester  bigint,      -- individual gig requesters
  ADD COLUMN u_admin      bigint,      -- user id ranges: <range>+1 .. <range>+n
  ADD COLUMN u_cand       bigint,
  ADD COLUMN u_rec        bigint,
  ADD COLUMN u_consult    bigint,
  ADD COLUMN u_gw         bigint,
  ADD COLUMN u_requester  bigint,
  ADD COLUMN n_user       bigint;
UPDATE seed.params SET
  n_hiring = floor(0.70 * n_org),
  n_rec = 2 * floor(0.70 * n_org),
  n_consult = greatest(20, n_org / 20),
  n_requester = greatest(10, n_gig / 10),
  u_admin = 1, u_cand = 6;
UPDATE seed.params SET u_rec = u_cand + n_cand;
UPDATE seed.params SET u_consult = u_rec + n_rec;
UPDATE seed.params SET u_gw = u_consult + n_consult;
UPDATE seed.params SET u_requester = u_gw + n_gw;
UPDATE seed.params SET n_user = u_requester + n_requester;

-- identity sequences continue after explicitly loaded ids (call after OVERRIDING SYSTEM VALUE loads)
CREATE FUNCTION seed.sync_sequences() RETURNS integer
LANGUAGE plpgsql AS
$$
DECLARE
  r record;
  v_max bigint;
  v_n integer := 0;
BEGIN
  FOR r IN SELECT n.nspname, c.relname
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'id' AND a.attidentity <> ''
            WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND n.nspname NOT IN ('seed', 'qa', 'pg_catalog') LOOP
    EXECUTE format('SELECT max(id) FROM %I.%I', r.nspname, r.relname) INTO v_max;
    IF v_max IS NOT NULL THEN
      PERFORM setval(pg_get_serial_sequence(format('%I.%I', r.nspname, r.relname), 'id'), v_max);
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END
$$;

-- Deterministic pseudo-random in [0,1): the same seed gives the same dataset regardless of plan or parallelism.
CREATE FUNCTION seed.h(p_n bigint, p_salt integer) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT (abs(hashtextextended(p_n::text || ':' || p_salt::text, 20261015)) % 1000000007) / 1000000007.0 $$;

-- index in 1..p_n from a unit random
CREATE FUNCTION seed.pick(p_n bigint, p_salt integer, p_size integer) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT 1 + floor(seed.h(p_n, p_salt) * p_size)::integer $$;

-- weighted pick: cumulative weights in an array, returns 1-based index
CREATE FUNCTION seed.wpick(p_n bigint, p_salt integer, p_cum double precision[]) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$
  SELECT coalesce((SELECT min(i) FROM generate_subscripts(p_cum, 1) i WHERE seed.h(p_n, p_salt) < p_cum[i]), array_length(p_cum, 1))
$$;

-- Multilingual names: (locale, kind, ord) -> native script and Latin transliteration. Near-duplicate candidates use the
-- Latin form of the base candidate's native name.
CREATE TABLE seed.name_pool (
  locale  text    NOT NULL,
  kind    char(1) NOT NULL,   -- g given, f family
  ord     integer NOT NULL,
  native  text    NOT NULL,
  latin   text    NOT NULL,
  PRIMARY KEY (locale, kind, ord)
);
INSERT INTO seed.name_pool (locale, kind, ord, native, latin)
SELECT locale, kind, row_number() OVER (PARTITION BY locale, kind ORDER BY ord), native, latin
  FROM (VALUES
  ('en','g',1,'Arjun','Arjun'),('en','g',2,'Priya','Priya'),('en','g',3,'Rahul','Rahul'),('en','g',4,'Sneha','Sneha'),
  ('en','g',5,'Vikram','Vikram'),('en','g',6,'Ananya','Ananya'),('en','g',7,'Karthik','Karthik'),('en','g',8,'Divya','Divya'),
  ('en','g',9,'Rohan','Rohan'),('en','g',10,'Meera','Meera'),('en','g',11,'Aditya','Aditya'),('en','g',12,'Neha','Neha'),
  ('en','g',13,'Suresh','Suresh'),('en','g',14,'Kavya','Kavya'),('en','g',15,'Imran','Imran'),('en','g',16,'Fatima','Fatima'),
  ('en','f',1,'Sharma','Sharma'),('en','f',2,'Iyer','Iyer'),('en','f',3,'Patel','Patel'),('en','f',4,'Reddy','Reddy'),
  ('en','f',5,'Nair','Nair'),('en','f',6,'Gupta','Gupta'),('en','f',7,'Khan','Khan'),('en','f',8,'Menon','Menon'),
  ('en','f',9,'Joshi','Joshi'),('en','f',10,'Das','Das'),('en','f',11,'Kulkarni','Kulkarni'),('en','f',12,'Chopra','Chopra'),
  ('en','f',13,'Rao','Rao'),('en','f',14,'Singh','Singh'),('en','f',15,'Banerjee','Banerjee'),('en','f',16,'Verma','Verma'),
  ('hi','g',1,'अर्जुन','Arjun'),('hi','g',2,'प्रिया','Priya'),('hi','g',3,'राहुल','Rahul'),('hi','g',4,'स्नेहा','Sneha'),
  ('hi','g',5,'विक्रम','Vikram'),('hi','g',6,'अनन्या','Ananya'),('hi','g',7,'कार्तिक','Kartik'),('hi','g',8,'दिव्या','Divya'),
  ('hi','g',9,'रोहन','Rohan'),('hi','g',10,'मीरा','Meera'),('hi','g',11,'आदित्य','Aditya'),('hi','g',12,'नेहा','Neha'),
  ('hi','g',13,'सुरेश','Suresh'),('hi','g',14,'काव्या','Kavya'),('hi','g',15,'अमित','Amit'),('hi','g',16,'पूजा','Pooja'),
  ('hi','f',1,'शर्मा','Sharma'),('hi','f',2,'वर्मा','Verma'),('hi','f',3,'गुप्ता','Gupta'),('hi','f',4,'यादव','Yadav'),
  ('hi','f',5,'मिश्रा','Mishra'),('hi','f',6,'तिवारी','Tiwari'),('hi','f',7,'चौहान','Chauhan'),('hi','f',8,'जोशी','Joshi'),
  ('hi','f',9,'पांडे','Pandey'),('hi','f',10,'अग्रवाल','Agarwal'),('hi','f',11,'सिंह','Singh'),('hi','f',12,'कुमार','Kumar'),
  ('hi','f',13,'सक्सेना','Saxena'),('hi','f',14,'दुबे','Dubey'),('hi','f',15,'त्रिपाठी','Tripathi'),('hi','f',16,'भट्ट','Bhatt'),
  ('ta','g',1,'அர்ஜுன்','Arjun'),('ta','g',2,'பிரியா','Priya'),('ta','g',3,'கார்த்திக்','Karthik'),('ta','g',4,'திவ்யா','Divya'),
  ('ta','g',5,'விக்ரம்','Vikram'),('ta','g',6,'அனன்யா','Ananya'),('ta','g',7,'சுரேஷ்','Suresh'),('ta','g',8,'மீனா','Meena'),
  ('ta','g',9,'ரமேஷ்','Ramesh'),('ta','g',10,'லட்சுமி','Lakshmi'),('ta','g',11,'முருகன்','Murugan'),('ta','g',12,'காவ்யா','Kavya'),
  ('ta','g',13,'அருண்','Arun'),('ta','g',14,'தேவி','Devi'),('ta','g',15,'செல்வி','Selvi'),('ta','g',16,'பாலா','Bala'),
  ('ta','f',1,'ராமன்','Raman'),('ta','f',2,'சுந்தரம்','Sundaram'),('ta','f',3,'குமார்','Kumar'),('ta','f',4,'ஐயர்','Iyer'),
  ('ta','f',5,'நாயர்','Nair'),('ta','f',6,'பிள்ளை','Pillai'),('ta','f',7,'ரெட்டி','Reddy'),('ta','f',8,'கிருஷ்ணன்','Krishnan'),
  ('ta','f',9,'வெங்கடேஷ்','Venkatesh'),('ta','f',10,'சுப்ரமணியம்','Subramaniam'),('ta','f',11,'நடராஜன்','Natarajan'),('ta','f',12,'மூர்த்தி','Murthy'),
  ('ta','f',13,'கோபால்','Gopal'),('ta','f',14,'ராஜன்','Rajan'),('ta','f',15,'ஆறுமுகம்','Arumugam'),('ta','f',16,'சண்முகம்','Shanmugam'),
  ('ar','g',1,'محمد','Mohammed'),('ar','g',2,'فاطمة','Fatima'),('ar','g',3,'أحمد','Ahmed'),('ar','g',4,'عائشة','Aisha'),
  ('ar','g',5,'عمر','Omar'),('ar','g',6,'ليلى','Layla'),('ar','g',7,'يوسف','Yusuf'),('ar','g',8,'مريم','Maryam'),
  ('ar','g',9,'خالد','Khalid'),('ar','g',10,'سارة','Sara'),('ar','g',11,'حسن','Hassan'),('ar','g',12,'زينب','Zainab'),
  ('ar','g',13,'علي','Ali'),('ar','g',14,'نور','Noor'),('ar','g',15,'إبراهيم','Ibrahim'),('ar','g',16,'هدى','Huda'),
  ('ar','f',1,'الخطيب','Al-Khatib'),('ar','f',2,'السيد','Al-Sayed'),('ar','f',3,'المصري','Al-Masri'),('ar','f',4,'الحداد','Al-Haddad'),
  ('ar','f',5,'النجار','Al-Najjar'),('ar','f',6,'القاسم','Al-Qasim'),('ar','f',7,'العلي','Al-Ali'),('ar','f',8,'الشامي','Al-Shami'),
  ('ar','f',9,'منصور','Mansour'),('ar','f',10,'حداد','Haddad'),('ar','f',11,'سالم','Salem'),('ar','f',12,'ناصر','Nasser'),
  ('ar','f',13,'الرشيد','Al-Rashid'),('ar','f',14,'الزعبي','Al-Zoubi'),('ar','f',15,'بركات','Barakat'),('ar','f',16,'خوري','Khoury'),
  ('zh','g',1,'伟','Wei'),('zh','g',2,'芳','Fang'),('zh','g',3,'娜','Na'),('zh','g',4,'敏','Min'),
  ('zh','g',5,'静','Jing'),('zh','g',6,'丽','Li'),('zh','g',7,'强','Qiang'),('zh','g',8,'磊','Lei'),
  ('zh','g',9,'军','Jun'),('zh','g',10,'洋','Yang'),('zh','g',11,'勇','Yong'),('zh','g',12,'艳','Yan'),
  ('zh','g',13,'杰','Jie'),('zh','g',14,'涛','Tao'),('zh','g',15,'明','Ming'),('zh','g',16,'超','Chao'),
  ('zh','f',1,'王','Wang'),('zh','f',2,'李','Li'),('zh','f',3,'张','Zhang'),('zh','f',4,'刘','Liu'),
  ('zh','f',5,'陈','Chen'),('zh','f',6,'杨','Yang'),('zh','f',7,'黄','Huang'),('zh','f',8,'赵','Zhao'),
  ('zh','f',9,'吴','Wu'),('zh','f',10,'周','Zhou'),('zh','f',11,'徐','Xu'),('zh','f',12,'孙','Sun'),
  ('zh','f',13,'马','Ma'),('zh','f',14,'朱','Zhu'),('zh','f',15,'胡','Hu'),('zh','f',16,'林','Lin')) v(locale, kind, ord, native, latin);

-- cumulative locale mix (en, hi, ta, ar, zh) and the matching ref.language codes
CREATE TABLE seed.locale_mix (idx integer PRIMARY KEY, locale text NOT NULL, language_code text NOT NULL, cum double precision NOT NULL);
INSERT INTO seed.locale_mix VALUES (1,'en','en',0.40),(2,'hi','hi',0.65),(3,'ta','ta',0.80),(4,'ar','ar',0.88),(5,'zh','zh_hans',1.00);

SELECT format('seed params: candidates=%s jobs=%s applications=%s organisations=%s recruiters=%s consultants=%s gig_workers=%s gig_requests=%s users=%s',
               n_cand, n_job, n_app, n_org, n_rec, n_consult, n_gw, n_gig, n_user) FROM seed.params \gset
\echo :'format'
