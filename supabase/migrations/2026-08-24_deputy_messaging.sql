-- ═══ 💬 סגן שולח הודעות — 2026-08-24 ═══
--
-- הצ'אט האישי קיבל מדיניות סגן, אבל שאר נתיבי התקשורת לא: הצ'אט
-- הקבוצתי, קבצים מצורפים והתראות. סגן שמלווה מתאמן וגם אינו יכול
-- לענות לו אינו מלווה, ולכן כל הנתיבים נסגרים כאן יחד.
--
-- העיקרון בכולם זהה: הסגן פועל בשמו בלבד. sender_email נכפה למי
-- שמחובר, ולכן גם אם יעקוף את הממשק — אי אפשר להתחזות לבכיר.

-- ── 1. הצ'אט האישי ──
-- נוצרה כבר במיגרציה של השיוך פר-לקוח. נכתבת שוב כאן כדי שהמיגרציה
-- הזאת תעמוד בפני עצמה, ולמקרה שהקודמת הופעלה חלקית.
DROP POLICY IF EXISTS dep_sel_messages ON messages;
CREATE POLICY dep_sel_messages ON messages FOR SELECT TO authenticated
  USING (is_deputy_client(client_email));

DROP POLICY IF EXISTS dep_ins_messages ON messages;
CREATE POLICY dep_ins_messages ON messages FOR INSERT TO authenticated
  WITH CHECK (is_deputy_client(client_email)
              AND sender_email = (auth.jwt()->>'email'));

-- ── 2. הצ'אט הקבוצתי ──
-- כאן לא היה כלום. group_messages מפתוחה ב-coach_email של הבכיר
-- ואין בה client_email, ולכן התנאי הוא "אני סגן פעיל של הבכיר הזה"
-- ולא "הלקוח הזה הונגש לי": הקבוצה שייכת לבכיר כולה.
DROP POLICY IF EXISTS dep_sel_group_messages ON group_messages;
CREATE POLICY dep_sel_group_messages ON group_messages FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM coach_deputies d
                 WHERE d.deputy_email = (auth.jwt()->>'email')
                   AND d.senior_email = group_messages.coach_email
                   AND d.active));

DROP POLICY IF EXISTS dep_ins_group_messages ON group_messages;
CREATE POLICY dep_ins_group_messages ON group_messages FOR INSERT TO authenticated
  WITH CHECK (sender_email = (auth.jwt()->>'email')
              AND EXISTS (SELECT 1 FROM coach_deputies d
                          WHERE d.deputy_email = (auth.jwt()->>'email')
                            AND d.senior_email = group_messages.coach_email
                            AND d.active));

-- ── 3. התראה למתאמן ──
-- שליחת ההודעה קוראת את מזהה ההתראות של המתאמן. בלי קריאה היא
-- נכשלת בשקט והמתאמן פשוט לא מקבל התראה — הודעה שנשלחה ואיש לא
-- יודע עליה.
DROP POLICY IF EXISTS dep_sel_push_tokens ON push_tokens;
CREATE POLICY dep_sel_push_tokens ON push_tokens FOR SELECT TO authenticated
  USING (is_deputy_client(user_email));

-- ── 4. קבצים והקלטות קוליות ──
-- הצ'אט מעלה לדלי client-files. בלי הרשאה, צירוף קובץ או הודעה
-- קולית נכשלים אחרי שההודעה כבר נראית כאילו נשלחת.
DROP POLICY IF EXISTS dep_files_select ON storage.objects;
CREATE POLICY dep_files_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'client-files'
         AND EXISTS (SELECT 1 FROM coach_deputies d
                     WHERE d.deputy_email = (auth.jwt()->>'email') AND d.active));

DROP POLICY IF EXISTS dep_files_insert ON storage.objects;
CREATE POLICY dep_files_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'client-files'
              AND EXISTS (SELECT 1 FROM coach_deputies d
                          WHERE d.deputy_email = (auth.jwt()->>'email') AND d.active));

-- ── 5. אבחון ──
-- אם שליחה עדיין נכשלת, זה מראה בדיוק איפה. מריצים כשמחוברים
-- כסגן; כל שורה שמחזירה false היא החוליה שנשברה.
CREATE OR REPLACE FUNCTION deputy_selftest(p_client text)
RETURNS TABLE (בדיקה text, תוצאה boolean, פרטים text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE me text := (auth.jwt()->>'email');
BEGIN
  RETURN QUERY SELECT 'מחובר'::text, me IS NOT NULL, COALESCE(me,'—')::text;
  RETURN QUERY SELECT 'קיים כמאמן'::text,
    EXISTS (SELECT 1 FROM coaches WHERE email = me),
    'נדרש כדי להיכנס לפאנל'::text;
  RETURN QUERY SELECT 'סגן פעיל'::text,
    EXISTS (SELECT 1 FROM coach_deputies WHERE deputy_email = me AND active),
    (SELECT COALESCE(string_agg(senior_email, ', '), 'אין')
       FROM coach_deputies WHERE deputy_email = me AND active);
  RETURN QUERY SELECT 'המתאמן הונגש'::text,
    is_deputy_client(p_client),
    p_client;
  RETURN QUERY SELECT 'רואה את המתאמן'::text,
    EXISTS (SELECT 1 FROM clients WHERE email = p_client),
    'דרך מדיניות הקריאה'::text;
END
$fn$;
REVOKE ALL ON FUNCTION deputy_selftest(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION deputy_selftest(text) TO authenticated;

SELECT 'deputy messaging ready' AS r;
