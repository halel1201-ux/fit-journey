-- ═══ 🚫 סימון היעדרות ע"י המאמן שאימן — 2026-08-13 ═══
-- עד כה sbook_upd התירה עדכון רק ללקוח עצמו, לבעל הסטודיו או לאדמין,
-- ולכן מאמן שעבד בשיעור לא יכול היה לסמן שמתאמן נעדר — הכפתור נכשל
-- בשקט. הנוכחות היא ברירת מחדל ("מי שלא ביטל — הגיע"), והמאמן מסמן
-- נעדרים בלבד, ולכן ההרשאה הזו נדרשת לו כדי לעשות את עבודתו.
--
-- ההרחבה מכוונת בכוונה: רק מאמן פעיל באותו סטודיו, ורק על שיבוץ
-- שמשויך אליו (coach_email). מאמן לא יכול לגעת בשיבוצים של עמיתיו.

DROP POLICY IF EXISTS sbook_upd ON studio_bookings;
CREATE POLICY sbook_upd ON studio_bookings FOR UPDATE TO authenticated
  USING (
    client_email = (auth.jwt()->>'email')
    OR owner_email = (auth.jwt()->>'email')
    -- המאמן שאותו שיבוץ משויך אליו, בתנאי שהוא מאמן פעיל בסטודיו
    OR (coach_email = (auth.jwt()->>'email') AND EXISTS (
          SELECT 1 FROM studio_coaches sc
          WHERE sc.studio_owner_email = studio_bookings.owner_email
            AND sc.coach_email = (auth.jwt()->>'email')
            AND sc.status = 'active'))
    OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (
    client_email = (auth.jwt()->>'email')
    OR owner_email = (auth.jwt()->>'email')
    OR (coach_email = (auth.jwt()->>'email') AND EXISTS (
          SELECT 1 FROM studio_coaches sc
          WHERE sc.studio_owner_email = studio_bookings.owner_email
            AND sc.coach_email = (auth.jwt()->>'email')
            AND sc.status = 'active'))
    OR auth.email() = 'halel1201@gmail.com');

SELECT 'studio coach attendance ready' AS r;
