-- ═══ 🗑 אדמין מוחק התראות של מאמנים — 2026-08-16 ═══
-- לאדמין הייתה קריאה על ההתראות (הפאנל מציג אותן), אבל לא מחיקה.
-- התראות ישנות, כפולות או שגויות נשארו תקועות אצל המאמן בלי דרך
-- לנקות אותן.
--
-- ההרשאה ניתנת לאדמין בלבד. מאמן ממשיך לראות ולסמן כנקרא את שלו,
-- ואינו מקבל הרשאת מחיקה — כדי שלא ימחוק בטעות התראה שהיא חלק
-- מתיעוד (התראות נטישה, לידים, חידושים).

DROP POLICY IF EXISTS notif_admin_del ON coach_notifications;
CREATE POLICY notif_admin_del ON coach_notifications FOR DELETE TO authenticated
  USING (auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS notif_admin_sel ON coach_notifications;
CREATE POLICY notif_admin_sel ON coach_notifications FOR SELECT TO authenticated
  USING (auth.email() = 'halel1201@gmail.com');

SELECT 'admin notification delete ready' AS r;
