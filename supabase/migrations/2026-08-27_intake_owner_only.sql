-- ═══ 🔒 שאלוני הקליטה — רק לבעל המשפך — 2026-08-27 ═══
--
-- המדיניות התירה קריאה לכל מאמן בתפקיד 'senior'. הטבלה אינה מכילה
-- שיוך למאמן בכלל — אין בה coach_email — ולכן "בכיר" פירושו בפועל
-- *כל* השאלונים: שמות, טלפונים ותשובות של אנשים שעדיין לא לקוחות.
--
-- היום יש בכיר אחד וזה בעל העסק, ולכן איש לא נחשף. אבל 'senior' הוא
-- התפקיד שמקבל כל מאמן שנרשם לפלטפורמה — ברגע שיוסף אחד, הוא יראה
-- את המשפך של מישהו אחר בלי שאף צד יידע. פרצה שנפתחת מעצמה בעתיד
-- מסוכנת יותר מפרצה שרואים.
--
-- ההרשאה עוברת ל-'admin' בלבד: זהו תפקיד הבעלים, ולא מה שמקבלים
-- בהרשמה. אם בעתיד יהיו כמה משפכים, הפתרון הוא עמודת שיוך ולא
-- הרחבה חוזרת של התפקיד.

-- ── מי מאבד גישה בעקבות השינוי ──
-- מוצג לפני, כדי שלא יתגלה אחרי.
SELECT c.email, c.role,
       'מאבד גישה לשאלוני קליטה' AS הערה
  FROM coaches c
 WHERE c.role = 'senior'
   AND c.email <> 'halel1201@gmail.com'
   AND NOT EXISTS (SELECT 1 FROM coaches a WHERE a.email = c.email AND a.role = 'admin');

DROP POLICY IF EXISTS "admin reads intake" ON public.intake_forms;
CREATE POLICY "admin reads intake" ON public.intake_forms
  FOR SELECT USING (
    (auth.jwt() ->> 'email') = 'halel1201@gmail.com'
    OR EXISTS (SELECT 1 FROM public.coaches c
                WHERE c.email = (auth.jwt() ->> 'email')
                  AND c.role = 'admin')
  );

-- ── אימות: מי כן יראה מעכשיו ──
SELECT c.email, c.role
  FROM coaches c
 WHERE c.role = 'admin' OR c.email = 'halel1201@gmail.com'
 ORDER BY c.email;

-- ── ניקוי שורת הבדיקה ──
DELETE FROM intake_forms WHERE full_name = 'בדיקת מערכת — למחיקה';

SELECT 'intake forms are owner-only now' AS r;
