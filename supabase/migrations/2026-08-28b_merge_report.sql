-- ══ המיזוג מדווח בדיוק מה עשה ══
--
-- דווח מהשטח: אחרי מיזוג נשארו על המסך אימון מאוחד ואימון ישן.
-- שתי סיבות אפשריות, והפונקציה לא אמרה איזו מהן:
--   1. המחיקה לא תפסה.
--   2. היו שלושה חלקים לאותו אימון, ורק שניים סומנו.
--
-- הפונקציה מחזירה כעת כמה מוזגו, כמה נמחקו בפועל, וכמה אימונים
-- נוספים נשארו באותו תאריך - כך שהפאנל יכול לומר "מוזגו 2, נשאר
-- עוד אחד באותו יום" במקום להשאיר את המאמן לנחש.
--
-- שינוי סוג ההחזרה מחייב DROP לפני CREATE.
-- הרצה חוזרת בטוחה.

DROP FUNCTION IF EXISTS merge_workout_logs(bigint[]);

CREATE FUNCTION merge_workout_logs(p_ids bigint[])
RETURNS jsonb
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
  v_date    date;
  v_day     text;
  v_ex      jsonb;
  v_min     int;
  v_rest    text;
  v_vol     numeric;
  v_del     int;
  v_left    int;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'לא מזוהה';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) < 2 THEN
    RAISE EXCEPTION 'צריך לפחות שני אימונים למיזוג';
  END IF;

  SELECT count(*), count(DISTINCT client_email), min(client_email)
    INTO v_found, v_clients, v_client
    FROM workout_logs WHERE id = ANY(p_ids);

  IF v_found <> array_length(p_ids, 1) THEN
    RAISE EXCEPTION 'חלק מהאימונים לא נמצאו';
  END IF;
  IF v_clients <> 1 THEN
    RAISE EXCEPTION 'האימונים אינם של אותו מתאמן';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM clients c
     WHERE c.email = v_client
       AND (c.coach_email = caller OR caller = 'halel1201@gmail.com')
  ) THEN
    RAISE EXCEPTION 'אין הרשאה למתאמן הזה';
  END IF;

  SELECT id, log_date, day_name INTO v_base, v_date, v_day
    FROM workout_logs WHERE id = ANY(p_ids)
   ORDER BY log_date, created_at, id
   LIMIT 1;

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

  SELECT COALESCE(sum(COALESCE((regexp_match(COALESCE(notes, ''),
                                'משך אימון:\s*(\d+)'))[1]::int, 0)), 0)
    INTO v_min
    FROM workout_logs WHERE id = ANY(p_ids);

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
  GET DIAGNOSTICS v_del = ROW_COUNT;

  -- כמה אימונים נוספים נשארו לאותו מתאמן באותו תאריך. אם המתאמן
  -- שלח שלושה חלקים ורק שניים סומנו, זה מה שמסביר את השורה שנשארה.
  SELECT count(*) INTO v_left
    FROM workout_logs
   WHERE client_email = v_client AND log_date = v_date AND id <> v_base;

  RETURN jsonb_build_object(
    'base_id',   v_base,
    'merged',    v_found,
    'deleted',   v_del,
    'same_day',  v_left,
    'log_date',  v_date,
    'day_name',  v_day
  );
END
$fn$;

COMMENT ON FUNCTION merge_workout_logs(bigint[]) IS
  'ממזג אימונים שנשלחו בחלקים לרשומה אחת, ומדווח כמה נמחקו וכמה נשארו באותו יום.';

REVOKE ALL ON FUNCTION merge_workout_logs(bigint[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION merge_workout_logs(bigint[]) TO authenticated;
