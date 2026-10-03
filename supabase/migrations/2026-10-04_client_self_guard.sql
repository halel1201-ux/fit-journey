-- ══ סגירת פרצה: מתאמן עדכן לעצמו שדות רגישים בשורה שלו ══
-- המדיניות cl_upd מתירה ללקוח לעדכן את השורה של עצמו (email = הקורא),
-- והרשאת UPDATE ניתנה על כל העמודות. כלומר כל מתאמן, עם המפתח הציבורי
-- וההתחברות שלו, יכול היה לתת לעצמו טוקנים, להאריך גישה וליווי,
-- ואפילו להעביר את עצמו למאמן אחר.
--
-- המדיניות נשארת כפי שהיא — הדשבורד באמת מעדכן את השורה של המתאמן
-- (פרופיל, משקל, פציעות, מחזור, הפשרה). מה שנוסף הוא שער: כשהמתאמן
-- עצמו מעדכן את השורה שלו ישירות, מותר לשנות רק את מה שהאפליקציה
-- משנה בפועל. כל השאר נדחה.
--
-- לא מושפעים: המאמן של הלקוח, הבעלים, ופעולות בשרת (SECURITY DEFINER
-- כמו spend_tokens, ו-Edge Functions עם מפתח השרת) — שם current_user
-- אינו 'authenticated'.
--
-- שדה חדש שהמתאמן צריך לעדכן בעצמו? להוסיף אותו לרשימה כאן.

CREATE OR REPLACE FUNCTION guard_client_self_update()
RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  caller  text := auth.jwt() ->> 'email';
  allowed text[] := ARRAY[
    -- פרופיל (dashboard: saveProfile)
    'name', 'phone', 'age', 'height', 'gender', 'current_weight', 'body_fat', 'goal',
    'activity_level', 'enhancement_status',
    -- יעדים (פרופיל, ועורך התפריט העצמי של העצמאי)
    'target_calories', 'target_protein', 'target_carbs', 'target_fat', 'target_water',
    -- פציעות, מעקב מחזור, נוכחות
    'injuries', 'period_active', 'period_updated_at', 'last_seen'
  ];
  o jsonb := to_jsonb(OLD);
  n jsonb := to_jsonb(NEW);
  unfreezing boolean := (OLD.frozen_until IS NOT NULL AND NEW.frozen_until IS NULL);
  k text;
BEGIN
  IF current_user <> 'authenticated' OR caller IS NULL OR caller <> OLD.email
     OR caller = COALESCE(OLD.coach_email, '') OR caller = 'halel1201@gmail.com' THEN
    RETURN NEW;
  END IF;

  FOR k IN SELECT jsonb_object_keys(n) LOOP
    CONTINUE WHEN (n -> k) IS NOT DISTINCT FROM (o -> k);
    CONTINUE WHEN k = ANY (allowed);
    -- קוד הפניה: נוצר פעם אחת, כשאין עדיין
    CONTINUE WHEN k = 'referral_code' AND (o ->> k) IS NULL;
    -- הפשרה עצמית: מבטלים הקפאה, חוסמים הקפאה חוזרת, ומקצרים את הסיום
    -- בימים שלא נוצלו. הארכה — לא.
    CONTINUE WHEN k = 'frozen_until' AND unfreezing;
    CONTINUE WHEN k = 'freeze_blocked_until' AND unfreezing;
    CONTINUE WHEN k = 'coaching_end' AND unfreezing
      AND NEW.coaching_end IS NOT NULL AND OLD.coaching_end IS NOT NULL
      AND NEW.coaching_end <= OLD.coaching_end;
    RAISE EXCEPTION 'אין הרשאה לשנות את השדה %', k USING ERRCODE = '42501';
  END LOOP;
  RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION guard_client_self_update() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_client_self_update ON clients;
CREATE TRIGGER trg_guard_client_self_update
  BEFORE UPDATE ON clients
  FOR EACH ROW EXECUTE FUNCTION guard_client_self_update();
