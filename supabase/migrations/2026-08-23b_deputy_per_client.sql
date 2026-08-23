-- ═══ 👥 סגן: שיוך פר-לקוח, לא פר-מאמן — 2026-08-23 ═══
--
-- המיגרציה הקודמת נתנה לסגן קריאה על *כל* לקוחות הבכיר, מעצם היותו
-- סגן. זה רחב מדי: בכיר שרוצה שסגן ילווה שלושה מתאמנים נאלץ לחשוף
-- לו את כל התיק. כאן השיוך הופך להיות מפורש — הבכיר מנגיש לקוח
-- אחד-אחד, ורק מה שהונגש נראה.
--
-- שתי דרישות נצברות ומתקיימות שתיהן: הלקוח מונגש לסגן (client_deputies)
-- *וגם* הסגן פעיל אצל הבכיר (coach_deputies.active). כיבוי הסגן
-- מנתק אותו מכל הלקוחות בבת אחת בלי לגעת בשיוכים, והדלקה מחזירה
-- אותם — בלי לבנות את הרשימה מחדש.
--
-- כל מדיניות שנוצרת כאן היא החלפה של מדיניות סגן קיימת בלבד.
-- מדיניות של מאמן, מתאמן או אדמין אינה נוגעת בזה: Postgres מאחד
-- מדיניות SELECT ב-OR, ולכן הידוק ענף הסגן אינו מצמצם אף אחד אחר.

CREATE TABLE IF NOT EXISTS client_deputies (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  client_email  text NOT NULL,
  deputy_email  text NOT NULL,
  senior_email  text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_email, deputy_email)
);
CREATE INDEX IF NOT EXISTS idx_cldep_deputy ON client_deputies(deputy_email);
CREATE INDEX IF NOT EXISTS idx_cldep_senior ON client_deputies(senior_email);

ALTER TABLE client_deputies ENABLE ROW LEVEL SECURITY;

-- הבכיר מנהל את השיוכים שלו; הסגן רואה למי הוא משויך ולא יותר.
DROP POLICY IF EXISTS cldep_senior_all ON client_deputies;
CREATE POLICY cldep_senior_all ON client_deputies FOR ALL TO authenticated
  USING      (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS cldep_deputy_sel ON client_deputies;
CREATE POLICY cldep_deputy_sel ON client_deputies FOR SELECT TO authenticated
  USING (deputy_email = (auth.jwt()->>'email'));

-- ── התנאי, במקום אחד ──
-- אותו EXISTS חוזר בכל טבלה. פונקציה אחת במקום שכפול: אם התנאי
-- ישתנה, הוא ישתנה פעם אחת ולא בשמונה-עשרה מדיניות שאולי נשכח אחת
-- מהן. SECURITY DEFINER כדי שהקריאה ל-client_deputies בתוך מדיניות
-- של טבלה אחרת לא תיחסם בעצמה, ו-search_path מקובע כדי שלא ניתן
-- יהיה להטות אותה לסכימה אחרת.
CREATE OR REPLACE FUNCTION is_deputy_client(p_client text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM client_deputies cd
    JOIN coach_deputies  d
      ON d.deputy_email = cd.deputy_email
     AND d.senior_email = cd.senior_email
     AND d.active
    WHERE cd.client_email = p_client
      AND cd.deputy_email = (auth.jwt()->>'email')
  );
$$;
REVOKE ALL ON FUNCTION is_deputy_client(text) FROM public;
GRANT EXECUTE ON FUNCTION is_deputy_client(text) TO authenticated;

COMMENT ON FUNCTION is_deputy_client(text) IS
  'האם הלקוח הונגש למשתמש הנוכחי כסגן, והסגן פעיל אצל הבכיר';

-- ── הלקוח עצמו ──
DROP POLICY IF EXISTS cl_deputy_sel ON clients;
CREATE POLICY cl_deputy_sel ON clients FOR SELECT TO authenticated
  USING (is_deputy_client(clients.email));

-- ── כל מה שתלוי בלקוח ──
-- הטבלאות הכספיות אינן ברשימה במכוון: client_packages,
-- client_debt_transactions, receipts, coach_sales, coach_expenses.
-- הסגן לא יקבל עליהן קריאה, ולכן ההסתרה בממשק אינה הקו היחיד.
DO $mig$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'training_plans','nutrition_plans','workout_logs','progress_entries',
    'body_measurements','body_photos','checkins','client_notes',
    'daily_cardio','daily_habits','steps_logs','exercise_notes',
    'cycles','cycle_history','signed_documents','client_ai_reports',
    'peak_week_plans'
  ] LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'dep_sel_' || t, t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (is_deputy_client(client_email))',
      'dep_sel_' || t, t);
  END LOOP;
END
$mig$;

-- המיגרציה הקודמת יצרה מדיניות בשמות אחרים על שלוש מהן; הן מוחלפות
-- כאן ולכן צריכות להיעלם, אחרת ה-OR היה מחזיר את הגישה הרחבה.
DROP POLICY IF EXISTS tp_deputy_sel ON training_plans;
DROP POLICY IF EXISTS np_deputy_sel ON nutrition_plans;
DROP POLICY IF EXISTS wl_deputy_sel ON workout_logs;

-- ── שאלון היכרות — המפתח שם הוא email ──
DROP POLICY IF EXISTS dep_sel_intake_forms ON intake_forms;
CREATE POLICY dep_sel_intake_forms ON intake_forms FOR SELECT TO authenticated
  USING (is_deputy_client(email));

-- ── צ'אט ──
-- סגן שמלווה מתאמן וגם אינו יכול לענות לו אינו מלווה. הוא קורא את
-- השיחה ויכול לכתוב בה, אבל תמיד בשמו: sender_email נכפה למי שהוא,
-- ולכן אי אפשר להתחזות לבכיר. השיחה נשארת תחת coach_email של הבכיר
-- כדי שהיא תישאר שיחה אחת ולא תתפצל לשתיים.
DROP POLICY IF EXISTS dep_sel_messages ON messages;
CREATE POLICY dep_sel_messages ON messages FOR SELECT TO authenticated
  USING (is_deputy_client(client_email));

DROP POLICY IF EXISTS dep_ins_messages ON messages;
CREATE POLICY dep_ins_messages ON messages FOR INSERT TO authenticated
  WITH CHECK (is_deputy_client(client_email)
              AND sender_email = (auth.jwt()->>'email'));

-- ── הצעות שינוי: רק על לקוח שהונגש ──
DROP POLICY IF EXISTS pc_deputy_ins ON pending_changes;
CREATE POLICY pc_deputy_ins ON pending_changes FOR INSERT TO authenticated
  WITH CHECK (
    deputy_email = (auth.jwt()->>'email')
    AND status = 'pending'
    AND is_deputy_client(client_email)
    AND EXISTS (SELECT 1 FROM coach_deputies d
                WHERE d.deputy_email = (auth.jwt()->>'email')
                  AND d.senior_email = pending_changes.senior_email
                  AND d.active));

SELECT 'deputy per-client access ready' AS r;
