-- ══ קוד הנחה: חודש מנוי פרילנסר במתנה + 250 טוקנים (תוכנית אחת ותפריט אחד) ══
-- אושר ע"י הלל 16/10/2026: חודש · נעול לתוכנית ולתפריט · רק לנרשמים חדשים · 50 מימושים לקוד.
--
-- הזרימה: join.html?code=... → redeem_promo (anon) יוצר שורת פרילנסר פעילה מיד, בלי אישור ידני →
-- נשלח קישור כניסה למייל (signInWithOtp, כמו היום) → המתאמן נכנס עם גישה ל-30 יום.
--
-- שינויים בפונקציות קיימות חלים רק על מי שמימש קוד (promo_lock לא ריק). שאר המשתמשים — ללא שינוי.
-- הרצה חוזרת בטוחה.

-- ── טבלאות ──
CREATE TABLE IF NOT EXISTS promo_codes (
  code        text PRIMARY KEY,                 -- תמיד באותיות גדולות
  days        int  NOT NULL CHECK (days BETWEEN 1 AND 365),
  tokens      int  NOT NULL CHECK (tokens BETWEEN 0 AND 10000),
  max_uses    int  NOT NULL CHECK (max_uses > 0),
  uses        int  NOT NULL DEFAULT 0,
  active      boolean NOT NULL DEFAULT false,   -- נפתח רק כשהלל מאשר
  lock_kind   text NOT NULL DEFAULT 'one_plan_one_menu',
  terms_version text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;   -- אין policies: קריאה/כתיבה רק דרך הפונקציות

CREATE TABLE IF NOT EXISTS promo_redemptions (
  id          bigserial PRIMARY KEY,
  code        text NOT NULL REFERENCES promo_codes(code),
  email       text NOT NULL,
  name        text,
  phone       text,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code, email)
);
ALTER TABLE promo_redemptions ENABLE ROW LEVEL SECURITY;

ALTER TABLE clients ADD COLUMN IF NOT EXISTS promo_code text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS promo_lock text;   -- 'one_plan_one_menu' = טוקני המתנה נעולים
COMMENT ON COLUMN clients.promo_lock IS 'טוקני מתנה מקוד הנחה: מותר רק תוכנית אחת (plan) ותפריט אחד (nutrition). מתבטל ברכישת מסלול.';

-- ── מימוש ──
-- הודעות השגיאה כלליות בכוונה ככל האפשר. "רק לנרשמים חדשים" חושפת שהמייל כבר קיים —
-- מחיר מודע של התנאי שהלל ביקש.
CREATE OR REPLACE FUNCTION redeem_promo(p_code text, p_name text, p_email text, p_phone text DEFAULT NULL,
                                        p_enhancement text DEFAULT NULL, p_waiver_version text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_code  text := upper(btrim(COALESCE(p_code, '')));
  v_email text := lower(btrim(COALESCE(p_email, '')));
  pc      promo_codes%ROWTYPE;
  v_until date;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'כתובת מייל לא תקינה'; END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'חסר שם'; END IF;

  SELECT * INTO pc FROM promo_codes WHERE code = v_code FOR UPDATE;   -- נעילה: שני מימושים במקביל לא יעברו את התקרה
  IF NOT FOUND OR NOT pc.active THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF pc.uses >= pc.max_uses THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'exhausted');
  END IF;
  IF p_waiver_version IS NULL OR p_waiver_version <> pc.terms_version THEN
    RAISE EXCEPTION 'לא נחתם התקנון של הקוד';
  END IF;
  -- רק נרשמים חדשים: אין חשבון התחברות, אין שורת מתאמן/מאמן, ולא מימש קוד בעבר
  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM clients WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM coaches WHERE lower(email) = v_email)
     OR EXISTS (SELECT 1 FROM promo_redemptions WHERE email = v_email) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_new');
  END IF;

  v_until := current_date + pc.days;
  INSERT INTO clients (email, name, phone, coach_email, client_type,
                       coaching_start, coaching_end, freelancer_status, freelancer_since, access_until,
                       tokens_balance, promo_code, promo_lock,
                       enhancement_status, waiver_signed_at, waiver_version)
  VALUES (v_email, btrim(p_name), NULLIF(btrim(COALESCE(p_phone, '')), ''), 'halel1201@gmail.com', 'freelancer',
          current_date, v_until, 'active', current_date, v_until,
          pc.tokens, pc.code, pc.lock_kind,
          NULLIF(btrim(COALESCE(p_enhancement, '')), ''), now(), p_waiver_version);

  INSERT INTO promo_redemptions (code, email, name, phone)
  VALUES (pc.code, v_email, btrim(p_name), NULLIF(btrim(COALESCE(p_phone, '')), ''));
  UPDATE promo_codes SET uses = uses + 1 WHERE code = pc.code;

  RETURN jsonb_build_object('ok', true, 'until', v_until, 'tokens', pc.tokens, 'left', pc.max_uses - pc.uses - 1);
END
$fn$;
REVOKE ALL ON FUNCTION redeem_promo(text, text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION redeem_promo(text, text, text, text, text, text) TO anon, authenticated;

-- בדיקת קוד לפני הטופס (בלי לחשוף כמה נשארו מעבר ל"יש/אין")
CREATE OR REPLACE FUNCTION check_promo(p_code text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT jsonb_build_object('ok', active AND uses < max_uses, 'reason',
              CASE WHEN NOT active THEN 'invalid' WHEN uses >= max_uses THEN 'exhausted' END,
              'days', days, 'tokens', tokens, 'terms_version', terms_version)
       FROM promo_codes WHERE code = upper(btrim(COALESCE(p_code, '')))),
    jsonb_build_object('ok', false, 'reason', 'invalid'));
$$;
REVOKE ALL ON FUNCTION check_promo(text) FROM public;
GRANT EXECUTE ON FUNCTION check_promo(text) TO anon, authenticated;

-- סטטוס להלל בלבד: כמה מומשו ומי
CREATE OR REPLACE FUNCTION promo_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF COALESCE(auth.jwt()->>'email', '') <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('code', c.code, 'active', c.active, 'uses', c.uses, 'max', c.max_uses,
            'redemptions', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', r.email, 'name', r.name, 'phone', r.phone, 'at', r.redeemed_at)
                                                       ORDER BY r.redeemed_at DESC), '[]'::jsonb)
                              FROM promo_redemptions r WHERE r.code = c.code)) ORDER BY c.created_at DESC), '[]'::jsonb)
          FROM promo_codes c);
END
$fn$;
REVOKE ALL ON FUNCTION promo_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION promo_status() TO authenticated;

-- ── נעילת טוקני המתנה ──
-- זהה לגרסה הקיימת, ובנוסף: למי שיש promo_lock — רק plan אחד ו-nutrition אחד (ניכוי שלא הוחזר).
CREATE OR REPLACE FUNCTION spend_tokens(p_amount int, p_label text, p_kind text DEFAULT 'plan')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_bal  int;
  v_id   bigint;
  v_lock text;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'סכום לא תקין'; END IF;

  -- מאמן
  IF EXISTS (SELECT 1 FROM coaches WHERE email = caller) THEN
    UPDATE coach_tokens
       SET balance = balance - p_amount, updated_at = now()
     WHERE coach_email = caller AND balance >= p_amount
    RETURNING balance INTO v_bal;
    IF v_bal IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient',
        'balance', COALESCE((SELECT balance FROM coach_tokens WHERE coach_email = caller), 0));
    END IF;
    INSERT INTO token_usage (coach_email, amount, kind, label, balance_after)
    VALUES (caller, p_amount, p_kind, p_label, v_bal);
    RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'actor', 'coach');
  END IF;

  -- פרילנסר
  IF EXISTS (SELECT 1 FROM clients
              WHERE email = caller AND client_type = 'freelancer') THEN
    IF NOT freelancer_active(caller) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'expired',
        'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
    END IF;
    SELECT promo_lock INTO v_lock FROM clients WHERE email = caller;
    IF v_lock = 'one_plan_one_menu' THEN
      IF COALESCE(p_kind, '') NOT IN ('plan', 'nutrition')
         OR EXISTS (SELECT 1 FROM client_token_spends
                     WHERE client_email = caller AND kind = p_kind AND refunded_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'promo_limit',
          'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
      END IF;
    END IF;
    UPDATE clients
       SET tokens_balance = tokens_balance - p_amount
     WHERE email = caller AND COALESCE(tokens_balance, 0) >= p_amount
    RETURNING tokens_balance INTO v_bal;
    IF v_bal IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient',
        'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
    END IF;
    INSERT INTO client_token_spends (client_email, amount, kind, label)
    VALUES (caller, p_amount, p_kind, p_label)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'actor', 'freelancer', 'spend_id', v_id);
  END IF;

  RAISE EXCEPTION 'אין ארנק לחשבון הזה';
END
$fn$;
REVOKE ALL ON FUNCTION spend_tokens(int, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION spend_tokens(int, text, text) TO authenticated;

-- ── רכישת מסלול אחרי המתנה ──
-- request_freelancer לא נוגע בשורה קיימת. מי שבא מקוד מתנה כן צריך לבקש מסלול בתשלום —
-- לכן רק אצלו: מעדכנים את המסלול המבוקש ומסמנים בקשה, בלי לקצר את הגישה הקיימת.
CREATE OR REPLACE FUNCTION request_freelancer(p_name text, p_email text, p_phone text, p_enhancement text DEFAULT NULL::text,
                                              p_waiver_version text DEFAULT NULL::text, p_plan text DEFAULT 'm3'::text)
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

  -- מי שבא מקוד מתנה: מבקש מסלול בתשלום. מעדכנים את הבקשה (הגישה הנוכחית נשארת עד האישור).
  IF EXISTS (SELECT 1 FROM clients WHERE email = v_email AND promo_code IS NOT NULL) THEN
    UPDATE clients
       SET freelancer_plan = v_plan, pending_since = current_date,
           waiver_signed_at = now(), waiver_version = p_waiver_version
     WHERE email = v_email;
    RETURN jsonb_build_object('ok', true, 'status', 'received');
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

-- אישור מסלול בתשלום מבטל את נעילת המתנה (וכן אם המסלול לא הוגדר — ברירת המחדל m3 כמו קודם)
CREATE OR REPLACE FUNCTION approve_freelancer(p_client text, p_tokens int DEFAULT NULL, p_days int DEFAULT NULL)
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
         tokens_balance   = COALESCE(tokens_balance, 0) + COALESCE(v_tok, 0),
         promo_lock       = NULL
   WHERE email = p_client
  RETURNING email, freelancer_since, access_until, tokens_balance INTO r;

  RETURN jsonb_build_object('email', r.email, 'since', r.freelancer_since,
                            'until', r.access_until, 'balance', r.tokens_balance,
                            'plan', v_plan, 'days', v_days, 'tokens', v_tok);
END
$fn$;

-- ── הקוד עצמו: נוצר כבוי. מופעל רק אחרי "תעלה" של הלל ──
INSERT INTO promo_codes (code, days, tokens, max_uses, active, lock_kind, terms_version)
VALUES ('HF30', 30, 250, 50, false, 'one_plan_one_menu', 'promo-hf30-v1')
ON CONFLICT (code) DO NOTHING;

SELECT 'promo trial ready' AS r;

-- ── הלל מפעיל/משהה קוד מתוך לוח הניהול ──
CREATE OR REPLACE FUNCTION set_promo_active(p_code text, p_active boolean)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v boolean;
BEGIN
  IF COALESCE(auth.jwt()->>'email', '') <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה'; END IF;
  UPDATE promo_codes SET active = p_active WHERE code = upper(btrim(p_code)) RETURNING active INTO v;
  IF v IS NULL THEN RAISE EXCEPTION 'קוד לא נמצא'; END IF;
  RETURN v;
END
$fn$;
REVOKE ALL ON FUNCTION set_promo_active(text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION set_promo_active(text, boolean) TO authenticated;
