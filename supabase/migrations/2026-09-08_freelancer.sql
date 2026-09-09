-- ══ שלב 1 — מסלול פרילנסר: מסד ══
--
-- מתאמן פרילנסר בונה לעצמו תוכנית ותפריט בלי מאמן אנושי.
-- 200 ש"ח לשלושה חודשים, 500 טוקנים.
--
-- שלוש החלטות שנקבעו ומקודדות כאן:
--   · הספירה מתחילה ברגע שהבעלים מאשר גישה — לא בהרשמה ולא בתשלום.
--   · ביום ה-91 הגישה נסגרת, אבל הטוקנים נשמרים כרזרבה לחידוש.
--   · מעבר למסלול עם מאמן הוא תשלום מלא, בלי זיכוי.
--   · בקשה שלא אושרה תוך שלושה ימי עסקים מתבטלת. אין מסלול החזר:
--     בקשת הביט אינה מאושרת ידנית, ולכן הכסף כלל אינו עובר.
--
-- הפרילנסר אינו ישות נפרדת אלא שורה ב-clients שה-coach_email שלה
-- הוא בעל הפלטפורמה. כך כל ה-RLS, הצ'אט והצ'ק-אין ממשיכים לעבוד
-- בלי מסלול הרשאות שני, ובלי תנאי "מאמן ריק" שעלול להיפתח לרווחה.
--
-- כל העמודות nullable ובלי DEFAULT: אף שורה קיימת אינה נכתבת מחדש,
-- ו-JS ישן מהמטמון ממשיך לרוץ נכון על הסכימה החדשה.
--
-- הרצה חוזרת בטוחה.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS client_type        text,        -- NULL/'coached' | 'freelancer'
  ADD COLUMN IF NOT EXISTS tokens_balance     int,
  ADD COLUMN IF NOT EXISTS freelancer_since   date,        -- יום האישור
  ADD COLUMN IF NOT EXISTS access_until       date,        -- freelancer_since + 90
  ADD COLUMN IF NOT EXISTS enhancement_status text,        -- natural|enhanced|peptides|NULL
  ADD COLUMN IF NOT EXISTS waiver_signed_at   timestamptz,
  ADD COLUMN IF NOT EXISTS waiver_version     text,
  ADD COLUMN IF NOT EXISTS pending_since      date,        -- יום הגשת הבקשה
  ADD COLUMN IF NOT EXISTS freelancer_status  text,        -- pending|active|expired|rejected
  -- שדות הפרופיל האישי. חסרו במסד, ובלעדיהם הבינה מייצרת תוכנית
  -- ותפריט גנריים — הרגע השביר ביותר אצל מתאמן שאין לו מאמן.
  ADD COLUMN IF NOT EXISTS height             int,         -- ס"מ
  ADD COLUMN IF NOT EXISTS age                int,
  ADD COLUMN IF NOT EXISTS body_fat           numeric,     -- אחוז
  ADD COLUMN IF NOT EXISTS activity_level     text;        -- sedentary|light|moderate|high|athlete

COMMENT ON COLUMN clients.client_type    IS 'freelancer = בונה לעצמו, בלי מאמן. NULL = מתאמן רגיל.';
COMMENT ON COLUMN clients.access_until   IS 'סוף הגישה. הטוקנים שורדים אותו ונשארים כרזרבה.';
COMMENT ON COLUMN clients.waiver_version IS 'גרסת נוסח כתב הוויתור שנחתמה. הנוסח משתנה — חתימה אינה רטרואקטיבית.';

CREATE INDEX IF NOT EXISTS idx_clients_type ON clients(client_type) WHERE client_type IS NOT NULL;


-- ── האם הגישה בתוקף ──
-- מתאמן רגיל אינו מוגבל כאן. פרילנסר בלי תאריך נחשב לא פעיל.
--
-- הפונקציה מקבלת מייל כלשהו, ולכן היא אינה נפתחת למזוהים: היא
-- משמשת רק בתוך spend_tokens, שרצה כבעלים ויכולה לקרוא לה. בלי
-- ההגבלה הזאת כל משתמש מזוהה יכול היה לתשאל על אנשים אחרים.
-- הממשק קורא את access_until מהשורה של עצמו, ואינו זקוק לה.
CREATE OR REPLACE FUNCTION freelancer_active(p_client text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT c.access_until IS NOT NULL AND c.access_until >= current_date
       FROM clients c WHERE c.email = p_client AND c.client_type = 'freelancer'),
    false);
$$;


-- ══ מסלול כסף אחד ══
-- הניכוי חושב עד היום בדפדפן ונכתב כיתרה מוחלטת: שתי לשוניות פתוחות
-- יכלו לדרוס זו את זו, ומשתמש מזוהה יכול היה לכתוב לעצמו כל מספר.
-- כאן החישוב בשרת, אטומי, ומשרת גם מאמן וגם פרילנסר — מסלול אחד
-- לכסף במקום שניים.
CREATE OR REPLACE FUNCTION spend_tokens(p_amount int, p_label text, p_kind text DEFAULT 'plan')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_bal  int;
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
    UPDATE clients
       SET tokens_balance = tokens_balance - p_amount
     WHERE email = caller AND COALESCE(tokens_balance, 0) >= p_amount
    RETURNING tokens_balance INTO v_bal;
    IF v_bal IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient',
        'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
    END IF;
    RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'actor', 'freelancer');
  END IF;

  RAISE EXCEPTION 'אין ארנק לחשבון הזה';
END
$fn$;


-- ══ אישור פרילנסר ══
-- כאן מתחילה הספירה. הטוקנים מצטברים על מה שכבר יש — מי שחידש
-- אחרי תפוגה נכנס עם הרזרבה שנשמרה לו.
CREATE OR REPLACE FUNCTION approve_freelancer(p_client text, p_tokens int DEFAULT 500,
                                              p_days int DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_from date;
  r      record;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF caller <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה מאשר פרילנסר'; END IF;
  IF NOT EXISTS (SELECT 1 FROM clients WHERE email = p_client) THEN
    RAISE EXCEPTION 'המתאמן לא נמצא';
  END IF;

  -- חידוש בזמן שהגישה עוד בתוקף מאריך את הקיים; אחרת מתחיל מהיום.
  SELECT GREATEST(COALESCE(access_until, current_date - 1), current_date - 1)
    INTO v_from FROM clients WHERE email = p_client;

  UPDATE clients
     SET client_type      = 'freelancer',
         freelancer_since = COALESCE(freelancer_since, current_date),
         access_until     = v_from + p_days,
         tokens_balance   = COALESCE(tokens_balance, 0) + COALESCE(p_tokens, 0)
   WHERE email = p_client
  RETURNING email, freelancer_since, access_until, tokens_balance INTO r;

  RETURN jsonb_build_object('email', r.email, 'since', r.freelancer_since,
                            'until', r.access_until, 'balance', r.tokens_balance);
END
$fn$;


-- ══ טעינת טוקנים בלבד ══
-- רכישת חבילה נוספת באמצע התקופה, בלי לגעת בתאריכים.
CREATE OR REPLACE FUNCTION grant_client_tokens(p_client text, p_tokens int)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_bal  int;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF caller <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה טוען טוקנים'; END IF;
  IF p_tokens IS NULL OR p_tokens <= 0 THEN RAISE EXCEPTION 'כמות לא תקינה'; END IF;

  UPDATE clients SET tokens_balance = COALESCE(tokens_balance, 0) + p_tokens
   WHERE email = p_client RETURNING tokens_balance INTO v_bal;
  IF v_bal IS NULL THEN RAISE EXCEPTION 'המתאמן לא נמצא'; END IF;
  RETURN v_bal;
END
$fn$;


-- ══ חתימה על כתב הוויתור ══
-- נשמרת כרשומה עם חותמת זמן וגרסת נוסח, ולא כתיבת סימון: הנוסח
-- ישתנה, ואי אפשר לחתום רטרואקטיבית על נוסח חדש.
CREATE OR REPLACE FUNCTION sign_waiver(p_version text)
RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_at   timestamptz;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF p_version IS NULL OR btrim(p_version) = '' THEN RAISE EXCEPTION 'חסרה גרסת נוסח'; END IF;

  UPDATE clients
     SET waiver_signed_at = now(), waiver_version = p_version
   WHERE email = caller
  RETURNING waiver_signed_at INTO v_at;
  IF v_at IS NULL THEN RAISE EXCEPTION 'לא נמצאה רשומת מתאמן'; END IF;
  RETURN v_at;
END
$fn$;


REVOKE ALL ON FUNCTION freelancer_active(text)         FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION spend_tokens(int, text, text)   FROM public, anon;
REVOKE ALL ON FUNCTION approve_freelancer(text, int, int) FROM public, anon;
REVOKE ALL ON FUNCTION grant_client_tokens(text, int)  FROM public, anon;
REVOKE ALL ON FUNCTION sign_waiver(text)               FROM public, anon;

GRANT EXECUTE ON FUNCTION spend_tokens(int, text, text)   TO authenticated;
GRANT EXECUTE ON FUNCTION approve_freelancer(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION grant_client_tokens(text, int)  TO authenticated;
GRANT EXECUTE ON FUNCTION sign_waiver(text)               TO authenticated;


-- ══ ימי עסקים ══
-- בישראל שבוע העבודה הוא ראשון עד חמישי. EXTRACT(DOW) מחזיר
-- 0 לראשון ו-5,6 לשישי ושבת — אלה הימים שמדלגים עליהם.
CREATE OR REPLACE FUNCTION add_business_days(p_from date, p_days int)
RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE d date := p_from; left_ int := GREATEST(COALESCE(p_days, 0), 0);
BEGIN
  WHILE left_ > 0 LOOP
    d := d + 1;
    IF EXTRACT(DOW FROM d) NOT IN (5, 6) THEN left_ := left_ - 1; END IF;
  END LOOP;
  RETURN d;
END
$fn$;

COMMENT ON FUNCTION add_business_days(date, int) IS
  'מוסיף ימי עסקים ומדלג על שישי ושבת.';


-- ══ תפוגת בקשות ══
-- בקשה שלא אושרה תוך שלושה ימי עסקים מתבטלת. אין כאן פעולה כספית:
-- אם הבעלים לא אישר את המתאמן הוא גם לא אישר את בקשת הביט, והכסף
-- מעולם לא עבר. הפונקציה רק מסמנת, כדי שהרשימה לא תתמלא בבקשות
-- מתות ושיהיה ברור מה כבר לא רלוונטי.
CREATE OR REPLACE FUNCTION expire_freelancer_requests()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  n int;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF caller <> 'halel1201@gmail.com' THEN RAISE EXCEPTION 'רק בעל הפלטפורמה'; END IF;

  UPDATE clients
     SET freelancer_status = 'expired'
   WHERE freelancer_status = 'pending'
     AND pending_since IS NOT NULL
     AND add_business_days(pending_since, 3) < current_date;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END
$fn$;


-- ══ מאמנים מומלצים ══
-- הדירוג נקבע ידנית ע"י בעל הפלטפורמה ואינו מגיע ממתאמנים: אין
-- טבלת דירוגים, אין ממוצעים, ואין מה לתחזק. מספר נמוך = מופיע
-- קודם; NULL = אינו מוצג ברשימה.
ALTER TABLE coaches
  ADD COLUMN IF NOT EXISTS recommended_rank  int,
  ADD COLUMN IF NOT EXISTS recommended_note  text;

COMMENT ON COLUMN coaches.recommended_rank IS
  'סדר הופעה ברשימת המאמנים המומלצים. נקבע ידנית. NULL = אינו מוצג.';

CREATE INDEX IF NOT EXISTS idx_coaches_recommended
  ON coaches(recommended_rank) WHERE recommended_rank IS NOT NULL;

REVOKE ALL ON FUNCTION expire_freelancer_requests() FROM public, anon;
GRANT EXECUTE ON FUNCTION expire_freelancer_requests() TO authenticated;


-- ══ שמירת תוכנית עצמית ══
-- מתאמן עצמאי בונה לעצמו, ולכן הוא צריך לכתוב ל-training_plans
-- ול-nutrition_plans. במקום להוסיף מדיניות כתיבה על טבלאות שמאמנים
-- חיים מהן — פונקציה אחת שכותבת רק לשורה של הקורא, ורק אם הוא
-- פרילנסר עם גישה בתוקף. מדיניות קיימת אינה נוגעת.
CREATE OR REPLACE FUNCTION save_own_plan(p_kind text, p_plan jsonb)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE caller text := auth.jwt()->>'email';
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF p_kind NOT IN ('training', 'nutrition') THEN RAISE EXCEPTION 'סוג לא מוכר'; END IF;
  IF p_plan IS NULL OR jsonb_typeof(p_plan) <> 'array' THEN RAISE EXCEPTION 'תוכנית לא תקינה'; END IF;

  -- רק פרילנסר, ורק בזמן שהגישה בתוקף. מתאמן עם מאמן אינו כותב
  -- לעצמו תוכנית — המאמן שלו כותב.
  IF NOT freelancer_active(caller) THEN
    RAISE EXCEPTION 'הגישה אינה בתוקף';
  END IF;

  IF p_kind = 'training' THEN
    INSERT INTO training_plans (client_email, plan, updated_at)
    VALUES (caller, p_plan, now())
    ON CONFLICT (client_email) DO UPDATE SET plan = EXCLUDED.plan, updated_at = now();
  ELSE
    INSERT INTO nutrition_plans (client_email, plan, updated_at)
    VALUES (caller, p_plan, now())
    ON CONFLICT (client_email) DO UPDATE SET plan = EXCLUDED.plan, updated_at = now();
  END IF;
  RETURN true;
END
$fn$;

REVOKE ALL ON FUNCTION save_own_plan(text, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION save_own_plan(text, jsonb) TO authenticated;


-- ══ מאמנים מומלצים לפרילנסר ══
-- מחזירה רק את מי שסומן ידנית, ורק שדות ציבוריים. בלי הפונקציה
-- הזאת היה צריך לפתוח לפרילנסר קריאה על טבלת המאמנים כולה.
CREATE OR REPLACE FUNCTION recommended_coaches()
RETURNS TABLE (name text, email text, phone text, note text, rank int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.name, c.email, c.phone, c.recommended_note, c.recommended_rank
    FROM coaches c
   WHERE c.recommended_rank IS NOT NULL
   ORDER BY c.recommended_rank, c.name;
$$;

REVOKE ALL ON FUNCTION recommended_coaches() FROM public, anon;
GRANT EXECUTE ON FUNCTION recommended_coaches() TO authenticated;


-- ══ הרשמה עצמית ══
-- נקראת מדף הרשמה ציבורי, לפני שיש משתמש מזוהה. זו הפונקציה
-- היחידה כאן שפתוחה ל-anon, ולכן היא מוגבלת בכוונה:
--   · יוצרת אך ורק שורה ממתינה. בלי גישה, בלי טוקנים, בלי תאריכים.
--   · מייל שכבר קיים כלקוח אינו נדרס — מוחזרת תשובה ולא שגיאה,
--     כדי שלא יהיה אפשר לגלות דרכה מי רשום ומי לא.
--   · הבעלים משויך כמאמן, כך שכל ה-RLS הקיים ממשיך לעבוד.
--
-- ההגנה האמיתית היא שאין כאן שום דבר בעל ערך: בקשה ממתינה שווה
-- כלום עד שהבעלים מאשר אותה ידנית.
CREATE OR REPLACE FUNCTION request_freelancer(
  p_name text, p_email text, p_phone text,
  p_enhancement text DEFAULT NULL, p_waiver_version text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_exists boolean;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'כתובת מייל לא תקינה';
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'חסר שם';
  END IF;
  IF p_waiver_version IS NULL OR btrim(p_waiver_version) = '' THEN
    RAISE EXCEPTION 'לא נחתם התקנון';
  END IF;

  SELECT EXISTS (SELECT 1 FROM clients WHERE email = v_email) INTO v_exists;

  IF v_exists THEN
    -- לא נוגעים בשורה קיימת. מתאמן פעיל לא יאבד את המאמן או את
    -- התוכנית שלו בגלל טופס, ולא ניתן לברר דרך התשובה מי רשום.
    RETURN jsonb_build_object('ok', true, 'status', 'received');
  END IF;

  INSERT INTO clients (email, name, phone, coach_email,
                       freelancer_status, pending_since,
                       enhancement_status, waiver_signed_at, waiver_version)
  VALUES (v_email, btrim(p_name), NULLIF(btrim(COALESCE(p_phone, '')), ''),
          'halel1201@gmail.com', 'pending', current_date,
          NULLIF(btrim(COALESCE(p_enhancement, '')), ''), now(), p_waiver_version);

  RETURN jsonb_build_object('ok', true, 'status', 'received');
END
$fn$;

COMMENT ON FUNCTION request_freelancer(text, text, text, text, text) IS
  'הרשמה עצמית למסלול העצמאי. יוצרת בקשה ממתינה בלבד — בלי גישה ובלי טוקנים.';

REVOKE ALL ON FUNCTION request_freelancer(text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION request_freelancer(text, text, text, text, text) TO anon, authenticated;


-- ══ תיקון: add_business_days נשארה ציבורית ══
-- פונקציה בלי REVOKE מפורש נשארת EXECUTE ל-PUBLIC כברירת מחדל
-- של Postgres. כאן זה חישוב תאריכים טהור בלי גישה לנתונים, ולכן
-- לא הייתה חשיפה — אבל זו הרשאה שלא התכוונו לתת, והדפוס עצמו
-- מסוכן: הוא חוזר על כל פונקציה שנשכח לנטרל.
REVOKE ALL ON FUNCTION add_business_days(date, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION add_business_days(date, int) TO authenticated;
