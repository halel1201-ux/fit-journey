-- ══ שלושה מסלולים עצמאיים ══
--
-- חודש · 100 ש"ח · 200 טוקנים
-- שלושה חודשים · 250 ש"ח, במבצע 200 · 500 טוקנים
-- חצי שנה · 500 ש"ח, במבצע 350 · 1000 טוקנים
--
-- המסלול נשמר על הבקשה, כדי שהאישור יידע כמה ימים וכמה טוקנים
-- לתת בלי שהבעלים יזכור. עד כה הוא היה קבוע בקוד.
--
-- הרצה חוזרת בטוחה.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS freelancer_plan text;   -- m1 | m3 | m6

COMMENT ON COLUMN clients.freelancer_plan IS
  'המסלול שנרכש: m1 חודש · m3 שלושה חודשים · m6 חצי שנה.';


-- ── פרטי המסלולים, במקום אחד ──
-- הקוד לא צריך להכיר מחירים; הוא שולח מפתח מסלול והמסד יודע
-- כמה ימים וכמה טוקנים. שינוי מחיר או מבצע נעשה כאן בלבד.
CREATE OR REPLACE FUNCTION freelancer_plan_spec(p_plan text)
RETURNS TABLE (days int, tokens int, label text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT t.d, t.tk, t.l FROM (VALUES
    ('m1',  30,  200, 'חודש'),
    ('m3',  90,  500, 'שלושה חודשים'),
    ('m6', 180, 1000, 'חצי שנה')
  ) AS t(k, d, tk, l)
  WHERE t.k = COALESCE(p_plan, 'm3')
$$;


-- ── האישור לוקח את הפרטים מהמסלול ──
-- p_tokens ו-p_days נשארו כדי לאפשר חריגה ידנית, אבל כברירת מחדל
-- הם נגזרים מהמסלול שנרכש ולא מקבוע בקוד.
CREATE OR REPLACE FUNCTION approve_freelancer(p_client text, p_tokens int DEFAULT NULL,
                                              p_days int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_from date;
  v_plan text;
  v_days int;
  v_tok  int;
  r      record;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF caller <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה מאשר פרילנסר'; END IF;
  IF NOT EXISTS (SELECT 1 FROM clients WHERE email = p_client) THEN
    RAISE EXCEPTION 'המתאמן לא נמצא';
  END IF;

  SELECT COALESCE(freelancer_plan, 'm3'),
         GREATEST(COALESCE(access_until, current_date - 1), current_date - 1)
    INTO v_plan, v_from
    FROM clients WHERE email = p_client;

  SELECT COALESCE(p_days, s.days), COALESCE(p_tokens, s.tokens)
    INTO v_days, v_tok
    FROM freelancer_plan_spec(v_plan) s;

  UPDATE clients
     SET client_type      = 'freelancer',
         freelancer_status = 'active',
         freelancer_since = COALESCE(freelancer_since, current_date),
         access_until     = v_from + v_days,
         tokens_balance   = COALESCE(tokens_balance, 0) + COALESCE(v_tok, 0)
   WHERE email = p_client
  RETURNING email, freelancer_since, access_until, tokens_balance INTO r;

  RETURN jsonb_build_object('email', r.email, 'since', r.freelancer_since,
                            'until', r.access_until, 'balance', r.tokens_balance,
                            'plan', v_plan, 'days', v_days, 'tokens', v_tok);
END
$fn$;


-- ── ההרשמה מקבלת מסלול ──
CREATE OR REPLACE FUNCTION request_freelancer(
  p_name text, p_email text, p_phone text,
  p_enhancement text DEFAULT NULL, p_waiver_version text DEFAULT NULL,
  p_plan text DEFAULT 'm3')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_plan  text := COALESCE(NULLIF(btrim(COALESCE(p_plan, '')), ''), 'm3');
  v_exists boolean;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'כתובת מייל לא תקינה';
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'חסר שם'; END IF;
  IF p_waiver_version IS NULL OR btrim(p_waiver_version) = '' THEN
    RAISE EXCEPTION 'לא נחתם התקנון';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM freelancer_plan_spec(v_plan)) THEN
    RAISE EXCEPTION 'מסלול לא מוכר';
  END IF;

  SELECT EXISTS (SELECT 1 FROM clients WHERE email = v_email) INTO v_exists;
  IF v_exists THEN
    RETURN jsonb_build_object('ok', true, 'status', 'received');
  END IF;

  INSERT INTO clients (email, name, phone, coach_email,
                       freelancer_status, freelancer_plan, pending_since,
                       enhancement_status, waiver_signed_at, waiver_version)
  VALUES (v_email, btrim(p_name), NULLIF(btrim(COALESCE(p_phone, '')), ''),
          'halel1201@gmail.com', 'pending', v_plan, current_date,
          NULLIF(btrim(COALESCE(p_enhancement, '')), ''), now(), p_waiver_version);

  RETURN jsonb_build_object('ok', true, 'status', 'received');
END
$fn$;


REVOKE ALL ON FUNCTION freelancer_plan_spec(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION freelancer_plan_spec(text) TO authenticated;

REVOKE ALL ON FUNCTION approve_freelancer(text, int, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION approve_freelancer(text, int, int) TO authenticated;

REVOKE ALL ON FUNCTION request_freelancer(text, text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION request_freelancer(text, text, text, text, text, text) TO anon, authenticated;

-- הגרסה בת חמשת הפרמטרים הוחלפה ואינה נחוצה עוד.
DROP FUNCTION IF EXISTS request_freelancer(text, text, text, text, text);
