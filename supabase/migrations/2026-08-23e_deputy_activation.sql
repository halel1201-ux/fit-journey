-- ═══ 👥 הפעלת סגן — 2026-08-23 ═══
--
-- סגן שנוסף קיבל שורה ב-coach_deputies וסיסמה, אבל אף פעם לא שורה
-- ב-coaches. התוצאה: הוא נכנס ומגיע למסך המתאמן, כי הניתוב מחפש
-- שורת מאמן ולא מוצא — וגם אילו הגיע ל-coach.html, האתחול שם היה
-- מחזיר אותו למסך ההתחברות. כלומר כל מנגנון הסגנים היה בנוי אבל
-- בלתי נגיש בפועל.
--
-- ההפעלה נעשית כאן ולא בדפדפן: לבכיר אין ואסור שתהיה הרשאת כתיבה
-- על coaches — אחרת כל מאמן היה יכול ליצור חשבונות מאמן כרצונו.
-- הפונקציה מוודאת שהמבקש הוא באמת הבכיר של אותו סגן.

CREATE OR REPLACE FUNCTION activate_deputy_coach(p_email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := (auth.jwt()->>'email');
  ok_dep boolean;
BEGIN
  IF p_email IS NULL OR p_email = '' THEN
    RETURN 'bad-input';
  END IF;

  -- רק בכיר של אותו סגן, או מנהל המערכת
  SELECT EXISTS (
    SELECT 1 FROM coach_deputies d
    WHERE d.senior_email = caller
      AND d.deputy_email = p_email
  ) INTO ok_dep;

  IF NOT ok_dep AND caller <> 'halel1201@gmail.com' THEN
    RETURN 'forbidden';
  END IF;

  -- כבר מאמן? לא נוגעים בשורה שלו: אולי הוא בכיר בעצמו, ודריסת
  -- ה-role שלו הייתה מורידה לו הרשאות.
  IF EXISTS (SELECT 1 FROM coaches WHERE email = p_email) THEN
    RETURN 'exists';
  END IF;

  INSERT INTO coaches (email, name, role)
  VALUES (p_email, split_part(p_email, '@', 1), 'regular');

  RETURN 'created';
END
$fn$;

REVOKE ALL ON FUNCTION activate_deputy_coach(text) FROM public;
GRANT EXECUTE ON FUNCTION activate_deputy_coach(text) TO authenticated;

COMMENT ON FUNCTION activate_deputy_coach(text) IS
  'פותח שורת מאמן לסגן, כדי שיוכל להיכנס לפאנל. רק הבכיר שלו רשאי.';

-- ── סגנים שכבר הוגדרו לפני התיקון ──
-- הם יושבים ב-coach_deputies בלי שורת מאמן, ובלי זה הם לא יכולים
-- להיכנס. נפתחת להם שורה עכשיו במקום לבקש מכל בכיר להגדיר מחדש.
INSERT INTO coaches (email, name, role)
SELECT DISTINCT d.deputy_email, split_part(d.deputy_email, '@', 1), 'regular'
FROM coach_deputies d
WHERE NOT EXISTS (SELECT 1 FROM coaches c WHERE c.email = d.deputy_email);

SELECT 'deputy activation ready' AS r;
