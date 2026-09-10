-- ══ מספר אימון וסוג אימון לשיבוץ בסטודיו ══
--
-- מתאמן משתבץ לשיעור, ובעל הסטודיו רואה ליד השם איזה אימון זה
-- אצלו השבוע ומה הוא כולל: "אימון 2: גב, יד קדמית".
--
-- למה זה במסד ולא בדפדפן:
-- בעל סטודיו רשאי לקרוא תוכנית אימונים רק של מתאמן שהוא המאמן
-- הרשום שלו. בשיעור יושבים גם מתאמנים של מאמנים אחרים, ותוכניתם
-- סגורה בפניו — ונכון שתישאר סגורה. הפונקציה הזאת רצה בהרשאות
-- המסד ומחזירה **רק את התווית**, לא את התוכנית. בעל הסטודיו
-- רואה מה המתאמן עושה אצלו, ולא את העבודה של המאמן שלו.
--
-- הרצה חוזרת בטוחה.


-- ── שם האימון מתוך יום בתוכנית ──
-- שמות הימים במסד כתובים בשלושה פורמטים:
--   "יום א׳ — PUSH" · "אימון 1 — PUSH" · "אימון A — פלג גוף עליון"
-- הכלל: מה שאחרי הקו המפריד. אין קו — רשימת השרירים של אותו יום.
-- אין גם אותה — השם כמו שהוא. שלושת הפורמטים מכוסים בלי לגעת
-- באף תוכנית קיימת.
CREATE OR REPLACE FUNCTION fj_split_label(p_day jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  v_title text;
  v_after text;
  v_musc  text;
BEGIN
  IF p_day IS NULL OR jsonb_typeof(p_day) <> 'object' THEN RETURN NULL; END IF;

  v_title := COALESCE(NULLIF(btrim(COALESCE(p_day->>'day', '')), ''),
                      NULLIF(btrim(COALESCE(p_day->>'name', '')), ''));

  -- מפריד ארוך או נקודתיים בלבד. מקף רגיל אינו מפריד, כי הוא
  -- מופיע גם בתוך שמות ("פול-באדי") והיה חותך אותם.
  v_after := btrim(COALESCE(substring(v_title from '[—–]\s*(.+)$'),
                            substring(v_title from ':\s*(.+)$'), ''));

  IF v_after <> '' THEN RETURN v_after; END IF;

  IF jsonb_typeof(p_day->'muscles') = 'array' THEN
    SELECT string_agg(btrim(x), ', ')
      INTO v_musc
      FROM jsonb_array_elements_text(p_day->'muscles') AS t(x)
     WHERE btrim(x) <> '';
  END IF;

  RETURN COALESCE(NULLIF(v_musc, ''), NULLIF(v_title, ''));
END
$fn$;


-- ── התוויות לכל השיבוצים בטווח ──
-- מחזירה שורה לכל שיבוץ: מספר האימון בשבוע, סוג האימון, והתווית
-- המוכנה. הספירה היא של **כל** שיבוצי המתאמן באותו שבוע — גם
-- כאלה שמחוץ לטווח המבוקש — אחרת שיעור ביום חמישי היה נספר
-- כאימון הראשון רק מפני שהוצג לבדו.
CREATE OR REPLACE FUNCTION studio_week_workouts(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (booking_id bigint, seq int, split_day int, split_total int, label text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;

  RETURN QUERY
  WITH all_bk AS (
    -- כל שיבוצי הסטודיו של הקורא, עם השבוע שאליו הם שייכים.
    -- שבוע = ראשון עד שבת, לפי שעון ישראל: EXTRACT(DOW) מחזיר 0
    -- לראשון, וחיסורו מהתאריך מחזיר את יום ראשון של אותו שבוע.
    SELECT b.id,
           b.client_email,
           s.slot_start,
           ((s.slot_start AT TIME ZONE 'Asia/Jerusalem')::date
             - EXTRACT(DOW FROM (s.slot_start AT TIME ZONE 'Asia/Jerusalem'))::int) AS wk
      FROM studio_bookings b
      JOIN studio_slots s ON s.id = b.slot_id
     WHERE b.owner_email = caller
       AND COALESCE(b.status, '') <> 'cancelled'
  ),
  wanted AS (
    -- אילו (מתאמן, שבוע) רלוונטיים לטווח שהוצג
    SELECT DISTINCT a.client_email, a.wk
      FROM all_bk a
     WHERE a.slot_start >= p_from AND a.slot_start < p_to
  ),
  seqd AS (
    SELECT a.id,
           a.client_email,
           a.slot_start,
           row_number() OVER (PARTITION BY a.client_email, a.wk
                              ORDER BY a.slot_start, a.id)::int AS n
      FROM all_bk a
      JOIN wanted w ON w.client_email = a.client_email AND w.wk = a.wk
  ),
  plans AS (
    -- התוכנית הפעילה. נשמרת גם כמערך וגם כאובייקט עם active.
    SELECT tp.client_email,
           CASE WHEN jsonb_typeof(tp.plan) = 'array' THEN tp.plan ELSE tp.plan->'active' END AS days
      FROM training_plans tp
  )
  SELECT q.id,
         q.n,
         CASE WHEN k.total > 0 THEN ((q.n - 1) % k.total) + 1 END,
         NULLIF(k.total, 0),
         CASE WHEN k.total > 0
              THEN fj_split_label(p.days -> ((q.n - 1) % k.total))
         END
    FROM seqd q
    LEFT JOIN plans p ON p.client_email = q.client_email
    LEFT JOIN LATERAL (
      SELECT CASE WHEN jsonb_typeof(p.days) = 'array'
                  THEN jsonb_array_length(p.days) ELSE 0 END AS total
    ) k ON true
   WHERE q.slot_start >= p_from AND q.slot_start < p_to;
END
$fn$;


REVOKE ALL ON FUNCTION fj_split_label(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION fj_split_label(jsonb) TO authenticated;

REVOKE ALL ON FUNCTION studio_week_workouts(timestamptz, timestamptz) FROM public, anon;
GRANT EXECUTE ON FUNCTION studio_week_workouts(timestamptz, timestamptz) TO authenticated;
