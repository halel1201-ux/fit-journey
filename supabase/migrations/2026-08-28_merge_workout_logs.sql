-- ══ מיזוג אימונים שנשלחו בחלקים ══
--
-- מתאמן שלוחץ "סיים ושלח" באמצע האימון וממשיך אחר כך מייצר שתי
-- רשומות לאותו אימון. היומן מציג אותן כשני אימונים, והנפח, המשך
-- והשיאים מחושבים לא נכון.
--
-- למה פונקציה ולא מדיניות: למאמן יש כיום קריאה בלבד על
-- workout_logs, והמחיקה שמורה למתאמן. פתיחת UPDATE/DELETE גורפים
-- הייתה נותנת למאמן למחוק כל יומן. הפונקציה נותנת יכולת אחת
-- בדיוק - למזג רשומות קיימות של מתאמן שלו - ואינה מקבלת תוכן
-- מהדפדפן, כך שאי אפשר להזריק דרכה תרגילים שלא תועדו.
--
-- הרצה חוזרת בטוחה.

CREATE OR REPLACE FUNCTION merge_workout_logs(p_ids bigint[])
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller    text := auth.jwt()->>'email';
  v_client  text;
  v_clients int;
  v_found   int;
  v_base    bigint;
  v_ex      jsonb;
  v_min     int;
  v_rest    text;
  v_vol     numeric;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'לא מזוהה';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) < 2 THEN
    RAISE EXCEPTION 'צריך לפחות שני אימונים למיזוג';
  END IF;

  -- ── כל הרשומות קיימות ושייכות לאותו מתאמן ──
  -- בלי הבדיקה הזאת אפשר היה לצרף id של מתאמן אחר לרשימה, והוא
  -- היה נמחק בשקט.
  SELECT count(*), count(DISTINCT client_email), min(client_email)
    INTO v_found, v_clients, v_client
    FROM workout_logs WHERE id = ANY(p_ids);

  IF v_found <> array_length(p_ids, 1) THEN
    RAISE EXCEPTION 'חלק מהאימונים לא נמצאו';
  END IF;
  IF v_clients <> 1 THEN
    RAISE EXCEPTION 'האימונים אינם של אותו מתאמן';
  END IF;

  -- ── המתאמן שייך לקורא ──
  -- סגן אינו כאן במכוון: מיזוג מוחק רשומות, ולסגן אין מסלול אישור
  -- לפעולה הזאת.
  IF NOT EXISTS (
    SELECT 1 FROM clients c
     WHERE c.email = v_client
       AND (c.coach_email = caller OR caller = 'halel1201@gmail.com')
  ) THEN
    RAISE EXCEPTION 'אין הרשאה למתאמן הזה';
  END IF;

  -- ── הרשומה שנשארת: המוקדמת ביותר ──
  SELECT id INTO v_base
    FROM workout_logs WHERE id = ANY(p_ids)
   ORDER BY log_date, created_at, id
   LIMIT 1;

  -- ── איחוד התרגילים ──
  -- שלב א: כל התרגילים לפי סדר האימונים ואז סדרם בתוך כל אימון.
  -- שלב ב: תרגיל שחוזר בשני החלקים מתאחד לאחד והסטים מצטרפים לפי
  -- אותו סדר. LEFT JOIN כדי שתרגיל בלי סטים לא ייעלם.
  WITH ranked AS (
    SELECT id, exercises,
           ROW_NUMBER() OVER (ORDER BY log_date, created_at, id) AS ord
      FROM workout_logs WHERE id = ANY(p_ids)
  ),
  items AS (
    SELECT r.ord, e.idx, e.ex
      FROM ranked r,
           LATERAL jsonb_array_elements(COALESCE(r.exercises, '[]'::jsonb))
             WITH ORDINALITY AS e(ex, idx)
  ),
  flat AS (
    SELECT i.ord, i.idx, i.ex, s.st, s.sidx
      FROM items i
      LEFT JOIN LATERAL jsonb_array_elements(COALESCE(i.ex->'sets', '[]'::jsonb))
        WITH ORDINALITY AS s(st, sidx) ON TRUE
  ),
  grouped AS (
    -- תרגיל בלי שם אינו מתאחד עם תרגיל אחר בלי שם: שניהם היו
    -- נבלעים לאחד. מפתח ייחודי לכל אחד שומר עליהם נפרדים.
    SELECT CASE WHEN COALESCE(ex->>'name', '') = ''
                THEN '#' || ord || ':' || idx
                ELSE ex->>'name' END                               AS nm,
           min(ord * 100000 + idx)                                 AS first_at,
           (array_agg(ex ORDER BY ord, idx))[1]                    AS proto,
           COALESCE(jsonb_agg(st ORDER BY ord, idx, sidx)
                    FILTER (WHERE st IS NOT NULL), '[]'::jsonb)    AS sets
      FROM flat
     GROUP BY CASE WHEN COALESCE(ex->>'name', '') = ''
                   THEN '#' || ord || ':' || idx
                   ELSE ex->>'name' END
  )
  SELECT COALESCE(jsonb_agg(jsonb_set(proto, '{sets}', sets) ORDER BY first_at), '[]'::jsonb)
    INTO v_ex
    FROM grouped;

  -- ── משך האימון מצטבר ──
  -- ההערה נכתבת ע"י האפליקציה כ"משך אימון: N דקות". סוכמים את N,
  -- ושומרים כל טקסט אחר שהמתאמן הוסיף כדי שלא יאבד.
  SELECT COALESCE(sum(COALESCE((regexp_match(COALESCE(notes, ''),
                                'משך אימון:\s*(\d+)'))[1]::int, 0)), 0)
    INTO v_min
    FROM workout_logs WHERE id = ANY(p_ids);

  -- הסדר חייב להיות בתוך string_agg: ORDER BY בתת-שאילתה אינו
  -- מובטח לשרוד את הצבירה.
  SELECT NULLIF(string_agg(t, ' · ' ORDER BY ord), '')
    INTO v_rest
    FROM (
      SELECT btrim(regexp_replace(COALESCE(notes, ''),
                   'משך אימון:\s*\d+\s*דקות\s*', '', 'g')) AS t,
             ROW_NUMBER() OVER (ORDER BY log_date, created_at, id) AS ord
        FROM workout_logs WHERE id = ANY(p_ids)
    ) x
   WHERE t <> '';

  SELECT COALESCE(sum(COALESCE(total_volume, 0)), 0)
    INTO v_vol
    FROM workout_logs WHERE id = ANY(p_ids);

  UPDATE workout_logs
     SET exercises    = v_ex,
         total_volume = v_vol,
         notes        = CASE WHEN v_min > 0
                             THEN 'משך אימון: ' || v_min || ' דקות'
                                  || COALESCE(' · ' || v_rest, '')
                             ELSE v_rest END
   WHERE id = v_base;

  DELETE FROM workout_logs
   WHERE id = ANY(p_ids) AND id <> v_base;

  RETURN v_base;
END
$fn$;

COMMENT ON FUNCTION merge_workout_logs(bigint[]) IS
  'ממזג אימונים שנשלחו בחלקים לרשומה אחת. רק המאמן של המתאמן.';

REVOKE ALL ON FUNCTION merge_workout_logs(bigint[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION merge_workout_logs(bigint[]) TO authenticated;
