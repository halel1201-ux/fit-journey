-- ══ סגירת rename_client_email ══
--
-- מה נמצא בביקורת (11/09/2026):
-- הפונקציה היא SECURITY DEFINER, כלומר עוקפת RLS, ומחליפה את
-- המייל של מתאמן בטבלת הלקוחות **ובכל טבלה בסכימה** שיש בה
-- client_email או user_email. לא הייתה בה שום בדיקת זהות, והיא
-- נשארה פתוחה ל-PUBLIC — כלומר גם ל-anon דרך PostgREST.
--
-- המשמעות: כל מי שמחזיק את המפתח הציבורי (והוא מופיע בקוד המקור
-- של כל דף) יכול היה לקרוא לה עם המייל של מתאמן כלשהו ולהעביר
-- את כל הרשומה שלו — תוכניות, תפריטים, יומנים — לכתובת שבחר.
--
-- איך זה קרה: המיגרציה המקורית עשתה
--   grant execute ... to authenticated, service_role;
-- ולא עשתה revoke. ב-Postgres הרשאת EXECUTE היא PUBLIC כברירת
-- מחדל, ולכן GRANT שנראה נכון אינו סוגר דבר.
--
-- התיקון: שלילה מפורשת מ-public ומ-anon, ובדיקת זהות בתוך
-- הפונקציה — הבעלים, או המאמן הרשום של אותו מתאמן.
--
-- הרצה חוזרת בטוחה.

CREATE OR REPLACE FUNCTION public.rename_client_email(p_old text, p_new text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_coach text;
  r record;
BEGIN
  IF p_old IS NULL OR p_new IS NULL OR p_old = p_new THEN
    RETURN;
  END IF;

  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;

  SELECT coach_email INTO v_coach FROM clients WHERE email = p_old;
  IF v_coach IS NULL AND NOT EXISTS (SELECT 1 FROM clients WHERE email = p_old) THEN
    RAISE EXCEPTION 'המתאמן לא נמצא';
  END IF;

  -- רק הבעלים, או המאמן הרשום של אותו מתאמן
  IF caller <> 'halel1201@gmail.com' AND caller IS DISTINCT FROM v_coach THEN
    RAISE EXCEPTION 'אין הרשאה לשנות את המייל של מתאמן זה';
  END IF;

  -- כתובת תפוסה תשתיק את העדכון ותשאיר נתונים מפוצלים בין שתי
  -- הכתובות. עדיף להיכשל ברעש.
  IF EXISTS (SELECT 1 FROM clients WHERE email = p_new) THEN
    RAISE EXCEPTION 'הכתובת החדשה כבר קיימת במערכת';
  END IF;

  -- הזהות עצמה (גורר CASCADE ל-training_plans / nutrition_plans)
  UPDATE public.clients SET email = p_new WHERE email = p_old;

  -- כל שאר הטבלאות שמפתחות לפי המייל של המתאמן
  FOR r IN
    SELECT c.table_name, c.column_name
      FROM information_schema.columns c
      JOIN information_schema.tables t
        ON t.table_name = c.table_name
       AND t.table_schema = c.table_schema
     WHERE c.table_schema = 'public'
       AND t.table_type   = 'BASE TABLE'
       AND c.column_name IN ('client_email', 'user_email')
  LOOP
    EXECUTE format('update public.%I set %I = $1 where %I = $2',
                   r.table_name, r.column_name, r.column_name)
      USING p_new, p_old;
  END LOOP;
END
$fn$;

REVOKE ALL ON FUNCTION public.rename_client_email(text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.rename_client_email(text, text) TO authenticated, service_role;
