-- ═══ 💬 הודעות סגן נכתבו לשרשור שאיש לא קורא — 2026-08-24 ═══
--
-- המדיניות שנתנה לסגן לכתוב בדקה שני דברים: שהלקוח הונגש לו, ושהוא
-- כותב בשמו. היא *לא* בדקה לאיזה שרשור ההודעה נכנסת.
--
-- coach_email הוא מה שמזהה שרשור. סגן שכתב עם קוד ישן (או מכל נתיב
-- אחר) הכניס את ההודעה תחת האימייל שלו — הכתיבה הצליחה, ההודעה נשמרה,
-- והבכיר שקורא את השרשור שלו פשוט לא רואה אותה. כשל שקט: נראה כאילו
-- ההודעה נשלחה, ואיש לא מקבל אותה.
--
-- כאן coach_email נכפה להיות המאמן של הלקוח. כתיבה לשרשור שגוי נדחית
-- במקום להיבלע, וההודעות שכבר נכתבו לשרשור מת מוחזרות למקומן.

-- ── 1. אי אפשר לכתוב לשרשור של מישהו אחר ──
DROP POLICY IF EXISTS dep_ins_messages ON messages;
CREATE POLICY dep_ins_messages ON messages FOR INSERT TO authenticated
  WITH CHECK (
    is_deputy_client(client_email)
    AND sender_email = (auth.jwt()->>'email')
    -- השרשור חייב להיות של המאמן שהלקוח שייך אליו
    AND coach_email = (SELECT c.coach_email FROM clients c WHERE c.email = client_email)
  );

-- ── 2. החזרת הודעות שנכתבו לשרשור מת ──
-- רק שורות שה-coach_email שלהן הוא סגן פעיל של המאמן האמיתי של אותו
-- לקוח. הודעות של מאמנים אחרים אינן נוגעות בזה.
UPDATE messages m
   SET coach_email = c.coach_email
  FROM clients c
 WHERE c.email = m.client_email
   AND m.coach_email IS DISTINCT FROM c.coach_email
   AND EXISTS (SELECT 1 FROM coach_deputies d
               WHERE d.deputy_email = m.coach_email
                 AND d.senior_email = c.coach_email);

-- ── 3. אותו דבר בצ'אט הקבוצתי ──
-- הקבוצה שייכת לבכיר. סגן שכתב תחת האימייל שלו פתח קבוצה שנייה ריקה.
UPDATE group_messages g
   SET coach_email = d.senior_email
  FROM coach_deputies d
 WHERE g.coach_email = d.deputy_email
   AND d.active
   AND NOT EXISTS (SELECT 1 FROM clients c WHERE c.coach_email = g.coach_email);

-- ── 4. כמה תוקנו ──
SELECT
  (SELECT count(*) FROM messages m JOIN clients c ON c.email = m.client_email
    WHERE m.coach_email IS DISTINCT FROM c.coach_email) AS הודעות_עדיין_בשרשור_שגוי,
  (SELECT count(*) FROM messages)                        AS סך_הודעות;
