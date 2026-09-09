-- ══ תיקון ההרשמה, טוקנים מעודכנים, ובקשות טוקנים לפרילנסר ══
--
-- 1. ההרשמה נפלה: coaching_start ו-coaching_end הן NOT NULL בלי
--    ברירת מחדל, ו-request_freelancer לא מילא אותן. אף בקשה לא
--    נכנסה. כאן הן מתמלאות — ובאישור הן מקבלות את חלון הגישה
--    האמיתי, כך שכל מסך שקורא coaching_end רואה תמונה נכונה.
--
-- 2. הטוקנים עודכנו: 250 / 750 / 1500 במקום 200 / 500 / 1000.
--
-- 3. פרילנסר יכול לבקש טוקנים נוספים, כמו מאמן. הבקשות נכנסות
--    לאותה טבלה עם סימון מי ביקש, כדי שמסך הבקשות באדמין יציג
--    את שני הסוגים במקום אחד.
--
-- הרצה חוזרת בטוחה.


-- ── 1. הטוקנים המעודכנים ──
CREATE OR REPLACE FUNCTION freelancer_plan_spec(p_plan text)
RETURNS TABLE (days int, tokens int, label text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT t.d, t.tk, t.l FROM (VALUES
    ('m1',  30,  250, 'חודש'),
    ('m3',  90,  750, 'שלושה חודשים'),
    ('m6', 180, 1500, 'חצי שנה')
  ) AS t(k, d, tk, l)
  WHERE t.k = COALESCE(p_plan, 'm3')
$$;


-- ── 2. ההרשמה ממלאת את העמודות החובה ──
-- בקשה ממתינה מקבלת חלון גישה שכבר נגמר (אתמול), כדי שלא תיחשב
-- לקוח פעיל בשום מסך לפני שאושרה.
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

  -- לא נוגעים בשורה קיימת. מי שכבר רשום לא ידע שהוא רשום, ומי
  -- שמנחש כתובות לא יוכל לברר מי לקוח.
  SELECT EXISTS (SELECT 1 FROM clients WHERE email = v_email) INTO v_exists;
  IF v_exists THEN
    RETURN jsonb_build_object('ok', true, 'status', 'received');
  END IF;

  INSERT INTO clients (email, name, phone, coach_email,
                       coaching_start, coaching_end,
                       freelancer_status, freelancer_plan, pending_since,
                       enhancement_status, waiver_signed_at, waiver_version)
  VALUES (v_email, btrim(p_name), NULLIF(btrim(COALESCE(p_phone, '')), ''),
          'halel1201@gmail.com',
          current_date, current_date - 1,
          'pending', v_plan, current_date,
          NULLIF(btrim(COALESCE(p_enhancement, '')), ''), now(), p_waiver_version);

  RETURN jsonb_build_object('ok', true, 'status', 'received');
END
$fn$;


-- ── 3. האישור קובע את חלון הגישה בכל המקומות ──
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
         coaching_start   = COALESCE(freelancer_since, current_date),
         coaching_end     = v_from + v_days,
         tokens_balance   = COALESCE(tokens_balance, 0) + COALESCE(v_tok, 0)
   WHERE email = p_client
  RETURNING email, freelancer_since, access_until, tokens_balance INTO r;

  RETURN jsonb_build_object('email', r.email, 'since', r.freelancer_since,
                            'until', r.access_until, 'balance', r.tokens_balance,
                            'plan', v_plan, 'days', v_days, 'tokens', v_tok);
END
$fn$;


-- ── 4. מי ביקש טוקנים ──
-- הטבלה נבנתה למאמנים, ושם העמודה coach_email נשאר כפי שהוא כדי
-- לא לשבור קוד קיים. NULL = מאמן, כמו כל השורות שכבר קיימות.
ALTER TABLE token_requests
  ADD COLUMN IF NOT EXISTS requester_kind text;

COMMENT ON COLUMN token_requests.requester_kind IS
  'freelancer = בקשה של מתאמן עצמאי. NULL או coach = מאמן.';

CREATE INDEX IF NOT EXISTS idx_token_requests_pending
  ON token_requests(status, created_at) WHERE status = 'pending';


-- ── 5. פרילנסר מבקש טוקנים ──
-- המחיר נקבע כאן ולא בדפדפן: חבילה = 250 טוקנים ב-100 ש"ח, אותו
-- יחס כמו במסלול החודשי. הכמות היא מספר חבילות, כדי שלא תיווצר
-- בקשה במחיר שהמבקש בחר לעצמו.
CREATE OR REPLACE FUNCTION request_client_tokens(p_packs int DEFAULT 1)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller  text := auth.jwt()->>'email';
  v_packs int  := COALESCE(p_packs, 1);
  v_name  text;
  v_is_fl boolean;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF v_packs < 1 OR v_packs > 10 THEN RAISE EXCEPTION 'כמות לא תקינה'; END IF;

  SELECT name, (client_type = 'freelancer' OR freelancer_status IS NOT NULL)
    INTO v_name, v_is_fl
    FROM clients WHERE email = caller;

  IF NOT COALESCE(v_is_fl, false) THEN
    RAISE EXCEPTION 'רק מתאמן עצמאי מבקש טוקנים כאן';
  END IF;

  -- בקשה ממתינה אחת בכל רגע: שליחה חוזרת אינה יוצרת ערימה
  IF EXISTS (SELECT 1 FROM token_requests
              WHERE coach_email = caller AND status = 'pending') THEN
    RAISE EXCEPTION 'כבר יש לך בקשה שממתינה לאישור';
  END IF;

  INSERT INTO token_requests (coach_email, coach_name, tokens, price, status, requester_kind)
  VALUES (caller, v_name, 250 * v_packs, 100 * v_packs, 'pending', 'freelancer');

  RETURN jsonb_build_object('ok', true, 'tokens', 250 * v_packs, 'price', 100 * v_packs);
END
$fn$;


REVOKE ALL ON FUNCTION freelancer_plan_spec(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION freelancer_plan_spec(text) TO authenticated;

REVOKE ALL ON FUNCTION approve_freelancer(text, int, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION approve_freelancer(text, int, int) TO authenticated;

REVOKE ALL ON FUNCTION request_freelancer(text, text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION request_freelancer(text, text, text, text, text, text) TO anon, authenticated;

REVOKE ALL ON FUNCTION request_client_tokens(int) FROM public, anon;
GRANT EXECUTE ON FUNCTION request_client_tokens(int) TO authenticated;
