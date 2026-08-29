-- ══ דילאוד מנוהל ══
--
-- המאמן מפעיל שבוע הקלה. שבוע קלנדרי אחד ב-76% מהמשקל ו-40% מהסטים
-- (החזרות ללא שינוי), ואז חזרה אוטומטית לנפח מלא עם 85% מהמשקל
-- ועלייה של 5 נקודות אחוז בשבוע עד 100%.
--
-- למה צילום ולא חישוב מההיסטוריה: המשקל שהמתאמן רואה נגזר מהביצוע
-- שלו. במסלול חיטוב/כללי הוא נלקח מהאימון האחרון בלבד — כלומר אם
-- הוא ירשום 76% בשבוע הדילאוד, זה יהפוך לבסיס והוא ירד בספירלה.
-- לכן משקלי השיא מצולמים ברגע ההפעלה, וכל החישובים בשבועות 0-4
-- נגזרים מהצילום ולא מההיסטוריה החיה.
--
-- הרצה חוזרת בטוחה.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS deload jsonb;

COMMENT ON COLUMN clients.deload IS
  'דילאוד פעיל: {start_date, anchor:{"שם תרגיל": משקל}}. NULL = אין דילאוד.';


-- ── הפעלה ──
-- מחזירה את הצילום כדי שהמאמן יראה מיד על מה זה יעבוד.
CREATE OR REPLACE FUNCTION start_deload(p_client text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller   text := auth.jwt()->>'email';
  v_anchor jsonb;
  v_n      int;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'לא מזוהה';
  END IF;

  -- סגן אינו כאן במכוון: דילאוד משנה את מה שהמתאמן רואה בכל אימון,
  -- ואין לו מסלול אישור לפעולה הזאת.
  IF NOT EXISTS (
    SELECT 1 FROM clients c
     WHERE c.email = p_client
       AND (c.coach_email = caller OR caller = 'halel1201@gmail.com')
  ) THEN
    RAISE EXCEPTION 'אין הרשאה למתאמן הזה';
  END IF;

  -- ── הצילום ──
  -- לכל תרגיל: המשקל הכבד ביותר בשלושת האימונים האחרונים שבהם הוא
  -- בוצע. שלושה ולא אחד, כדי שיום גרוע יחיד לא יקבע את הבסיס.
  -- סטי חימום אינם נספרים — הם אינם מייצגים יכולת.
  WITH recent AS (
    SELECT exercises,
           ROW_NUMBER() OVER (ORDER BY log_date DESC, created_at DESC) AS rn
      FROM workout_logs
     WHERE client_email = p_client
     ORDER BY log_date DESC, created_at DESC
     LIMIT 40
  ),
  per_ex AS (
    SELECT r.rn,
           NULLIF(btrim(e.ex->>'name'), '') AS nm,
           (SELECT max((s->>'weight')::numeric)
              FROM jsonb_array_elements(COALESCE(e.ex->'sets', '[]'::jsonb)) AS s
             WHERE (s->>'weight') ~ '^[0-9]+(\.[0-9]+)?$'
               AND COALESCE(s->>'set_type', 'working') NOT IN ('warm_up', 'warmup', 'warm')
           ) AS w
      FROM recent r,
           LATERAL jsonb_array_elements(COALESCE(r.exercises, '[]'::jsonb)) AS e(ex)
  ),
  ranked AS (
    SELECT nm, w, ROW_NUMBER() OVER (PARTITION BY nm ORDER BY rn) AS k
      FROM per_ex
     WHERE nm IS NOT NULL AND w IS NOT NULL AND w > 0
  )
  SELECT jsonb_object_agg(nm, mx)
    INTO v_anchor
    FROM (SELECT nm, max(w) AS mx FROM ranked WHERE k <= 3 GROUP BY nm) z;

  v_anchor := COALESCE(v_anchor, '{}'::jsonb);
  SELECT count(*) INTO v_n FROM jsonb_object_keys(v_anchor);

  -- תרגיל בלי היסטוריה פשוט אינו בצילום, ולכן יתנהג רגיל. לא מנחשים
  -- מספרים למתאמן.
  UPDATE clients
     SET deload = jsonb_build_object(
           'start_date', to_char(current_date, 'YYYY-MM-DD'),
           'anchor',     v_anchor)
   WHERE email = p_client;

  RETURN jsonb_build_object(
    'start_date', to_char(current_date, 'YYYY-MM-DD'),
    'exercises',  v_n,
    'anchor',     v_anchor);
END
$fn$;

COMMENT ON FUNCTION start_deload(text) IS
  'מפעיל שבוע דילאוד ומצלם את משקלי השיא לכל תרגיל. רק המאמן של המתאמן.';


-- ── ביטול ──
-- מחיקת הדגל בלבד. התוכנית עצמה מעולם לא שונתה, ולכן אין מה לשחזר.
CREATE OR REPLACE FUNCTION cancel_deload(p_client text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'לא מזוהה';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM clients c
     WHERE c.email = p_client
       AND (c.coach_email = caller OR caller = 'halel1201@gmail.com')
  ) THEN
    RAISE EXCEPTION 'אין הרשאה למתאמן הזה';
  END IF;

  UPDATE clients SET deload = NULL WHERE email = p_client;
  RETURN true;
END
$fn$;

COMMENT ON FUNCTION cancel_deload(text) IS
  'מבטל דילאוד. התוכנית לא שונתה מעולם, ולכן אין מה לשחזר.';

REVOKE ALL ON FUNCTION start_deload(text)  FROM public, anon;
REVOKE ALL ON FUNCTION cancel_deload(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION start_deload(text)  TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_deload(text) TO authenticated;
