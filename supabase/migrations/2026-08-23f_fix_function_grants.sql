-- ═══ 🔒 תיקון שתי פרצות שנפתחו במיגרציות של אתמול — 2026-08-23 ═══
--
-- שתיהן נמצאו בבדיקה חיה מול המסד, לא בקריאת קוד.
--
-- 1. activate_deputy_coach נכשלה *פתוח* לקורא אנונימי.
--    התנאי היה  IF NOT ok_dep AND caller <> 'halel1201@gmail.com'
--    ולקורא אנונימי caller הוא NULL. ב-SQL, NULL <> 'x' אינו TRUE
--    אלא NULL, ו-IF NULL אינו מתקיים — כלומר הענף שחוסם לא רץ,
--    והפונקציה המשיכה ויצרה חשבון מאמן. כל מי שמחזיק במפתח הפומבי
--    (והוא בקוד המקור של האתר) יכול היה לפתוח חשבונות מאמן.
--    התיקון: בדיקת NULL מפורשת, ולא הסתמכות על השוואה.
--
-- 2. REVOKE ALL ON FUNCTION ... FROM public אינו מסיר הרשאות שניתנו
--    ישירות לתפקידים anon ו-authenticated — וסופאבייס מעניקה להם
--    הרשאה על פונקציות חדשות כברירת מחדל. run_auto_renewals הייתה
--    ניתנת להרצה מבחוץ: קורא אנונימי יכול היה לחדש מנויים ולייצר
--    חיובי חוב. התיקון: REVOKE מפורש משני התפקידים.

-- ── 1. הגנה שלא נשענת על השוואה ל-NULL ──
CREATE OR REPLACE FUNCTION activate_deputy_coach(p_email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := (auth.jwt()->>'email');
  ok_dep boolean;
BEGIN
  -- בלי משתמש מחובר אין מה לבדוק. זה התנאי שהיה חסר.
  IF caller IS NULL OR caller = '' THEN
    RETURN 'forbidden';
  END IF;
  IF p_email IS NULL OR p_email = '' THEN
    RETURN 'bad-input';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM coach_deputies d
    WHERE d.senior_email = caller
      AND d.deputy_email = p_email
  ) INTO ok_dep;

  IF NOT ok_dep AND caller IS DISTINCT FROM 'halel1201@gmail.com' THEN
    RETURN 'forbidden';
  END IF;

  IF EXISTS (SELECT 1 FROM coaches WHERE email = p_email) THEN
    RETURN 'exists';
  END IF;

  INSERT INTO coaches (email, name, role)
  VALUES (p_email, split_part(p_email, '@', 1), 'regular');

  RETURN 'created';
END
$fn$;

REVOKE ALL ON FUNCTION activate_deputy_coach(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION activate_deputy_coach(text) TO authenticated;

-- ── 2. פונקציות שרק המתזמן צריך להריץ ──
REVOKE ALL ON FUNCTION run_auto_renewals()      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION is_deputy_client(text)   FROM public, anon;
GRANT EXECUTE ON FUNCTION is_deputy_client(text) TO authenticated;

-- ── 3. ניקוי החשבון שנוצר בבדיקה ──
-- נוצר בכוונה כדי להוכיח את הפרצה, ואין לו שום שימוש.
DELETE FROM coaches WHERE email = 'probe@example.invalid';

-- ── 4. חשבונות מאמן שנוצרו דרך הפרצה ──
-- מאמן בלי סגנות ובלי לקוחות, שנוצר היום — סימן לניצול. מוצג ולא
-- נמחק אוטומטית, כי מחיקה עיוורת של חשבונות היא הרסנית יותר מהבעיה.
SELECT c.email, c.created_at
FROM coaches c
WHERE c.role = 'regular'
  AND NOT EXISTS (SELECT 1 FROM coach_deputies d WHERE d.deputy_email = c.email)
  AND NOT EXISTS (SELECT 1 FROM clients cl WHERE cl.coach_email = c.email);
