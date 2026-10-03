-- ══ הקשחה לפי דוח האבטחה (04/10/2026) ══

-- ── 1. תצוגות הפיצול: קריאה בלבד ──
-- v_split_ledger / v_split_balance רצות בהרשאות הבעלים (security definer),
-- וזה מכוון: הן מסננות בעצמן לפי המייל של הקורא (בכיר / סגן / בעלים),
-- וסגן אינו רואה ב-RLS את הקבלות של הבכיר. הקריאה בטוחה.
-- אבל authenticated קיבל עליהן גם INSERT/UPDATE/DELETE, ו-v_split_ledger
-- היא תצוגה פשוטה — כלומר ניתנת לעדכון, והעדכון עובר אל receipts
-- בהרשאות הבעלים ועוקף את ה-RLS. סגן היה יכול לשנות לעצמו את אחוז
-- החלוקה או למחוק קבלות. הקוד רק קורא מהן.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON v_split_ledger  FROM authenticated, anon, public;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON v_split_balance FROM authenticated, anon, public;

-- ── 2. search_path קבוע לפונקציות SECURITY DEFINER שלא היה להן ──
-- כולן פונות רק לטבלאות ב-public.
ALTER FUNCTION _in_community(text)          SET search_path = public, pg_temp;
ALTER FUNCTION update_own_last_seen()       SET search_path = public, pg_temp;
ALTER FUNCTION fn_autopilot_enqueue()       SET search_path = public, pg_temp;
ALTER FUNCTION fn_no_show_count()           SET search_path = public, pg_temp;
ALTER FUNCTION fn_studio_promote_waitlist() SET search_path = public, pg_temp;
ALTER FUNCTION fn_studio_recount()          SET search_path = public, pg_temp;

-- ── 3. לא לאורחים ──
-- פונקציות טריגר ועדכון "נראה לאחרונה" — אין להן משמעות למי שלא מחובר.
-- למחוברים ההרשאה נשמרת בדיוק כמו היום.
-- נשארות פתוחות לאורחים בכוונה: request_freelancer (טופס ההרשמה
-- ב-join.html מוגש לפני שיש חשבון) ו-_in_community (נבדקת בתוך מדיניות
-- הקהילה, ולאורח מחזירה false — אין מה לדלוף).
REVOKE EXECUTE ON FUNCTION update_own_last_seen()       FROM public, anon;
REVOKE EXECUTE ON FUNCTION fn_autopilot_enqueue()       FROM public, anon;
REVOKE EXECUTE ON FUNCTION fn_no_show_count()           FROM public, anon;
REVOKE EXECUTE ON FUNCTION fn_studio_promote_waitlist() FROM public, anon;
REVOKE EXECUTE ON FUNCTION fn_studio_recount()          FROM public, anon;
GRANT  EXECUTE ON FUNCTION update_own_last_seen()       TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION fn_autopilot_enqueue()       TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION fn_no_show_count()           TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION fn_studio_promote_waitlist() TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION fn_studio_recount()          TO authenticated, service_role;
