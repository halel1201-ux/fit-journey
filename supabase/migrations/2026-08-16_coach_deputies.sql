-- ═══ 👥 סגן למאמן בכיר, עם אישור לפני החלה — 2026-08-16 ═══
--
-- העיקרון המנחה: הסגן לא מקבל הרשאת כתיבה בכלל. אילו היינו חוסמים
-- אותו רק בממשק, כל מי שיודע לפתוח קונסולה היה עוקף — "אבטחה" שהיא
-- בעצם בקשה יפה. במקום זה הוא מקבל קריאה בלבד על לקוחות הבכיר,
-- ויכול רק להוסיף הצעת שינוי. ההחלה נעשית ע"י הבכיר, שממילא מורשה.
--
-- אף מדיניות קיימת אינה משתנה: כל מה שכאן הוא תוספת. מאמן שאינו
-- סגן ולקוח שאינו משויך אינם מושפעים בשום צורה.

CREATE TABLE IF NOT EXISTS coach_deputies (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  senior_email  text NOT NULL,
  deputy_email  text NOT NULL,
  active        boolean NOT NULL DEFAULT true,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (senior_email, deputy_email)
);
CREATE INDEX IF NOT EXISTS idx_deputies_deputy ON coach_deputies(deputy_email, active);

CREATE TABLE IF NOT EXISTS pending_changes (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  senior_email  text NOT NULL,
  deputy_email  text NOT NULL,
  client_email  text NOT NULL,
  kind          text NOT NULL,          -- 'training_plan' | 'nutrition_plan'
  payload       jsonb NOT NULL,         -- הערך המוצע במלואו
  summary       text,                   -- תיאור קריא לבכיר
  status        text NOT NULL DEFAULT 'pending',   -- pending | approved | rejected
  note          text,                   -- נימוק הדחייה
  created_at    timestamptz NOT NULL DEFAULT now(),
  decided_at    timestamptz
);
CREATE INDEX IF NOT EXISTS idx_pending_senior ON pending_changes(senior_email, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pending_deputy ON pending_changes(deputy_email, created_at DESC);

ALTER TABLE coach_deputies  ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_changes ENABLE ROW LEVEL SECURITY;

-- ── מי סגן של מי ──
-- הבכיר מנהל את הסגנים שלו; הסגן רואה את השורה שלו כדי לדעת שהוא סגן.
DROP POLICY IF EXISTS dep_senior_all ON coach_deputies;
CREATE POLICY dep_senior_all ON coach_deputies FOR ALL TO authenticated
  USING      (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS dep_deputy_sel ON coach_deputies;
CREATE POLICY dep_deputy_sel ON coach_deputies FOR SELECT TO authenticated
  USING (deputy_email = (auth.jwt()->>'email'));

-- ── הצעות שינוי ──
-- הסגן מוסיף הצעות בשמו בלבד, ורואה את שלו. הוא אינו יכול לעדכן
-- סטטוס — אחרת היה מאשר את עצמו.
DROP POLICY IF EXISTS pc_deputy_ins ON pending_changes;
CREATE POLICY pc_deputy_ins ON pending_changes FOR INSERT TO authenticated
  WITH CHECK (
    deputy_email = (auth.jwt()->>'email')
    AND status = 'pending'
    AND EXISTS (SELECT 1 FROM coach_deputies d
                WHERE d.deputy_email = (auth.jwt()->>'email')
                  AND d.senior_email = pending_changes.senior_email
                  AND d.active));

DROP POLICY IF EXISTS pc_deputy_sel ON pending_changes;
CREATE POLICY pc_deputy_sel ON pending_changes FOR SELECT TO authenticated
  USING (deputy_email = (auth.jwt()->>'email') OR senior_email = (auth.jwt()->>'email')
         OR auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS pc_senior_upd ON pending_changes;
CREATE POLICY pc_senior_upd ON pending_changes FOR UPDATE TO authenticated
  USING      (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- ── קריאה בלבד ללקוחות הבכיר ──
-- מדיניות נוספת, לא החלפה: מדיניות SELECT קיימות ממשיכות לפעול,
-- ו-Postgres מאחד אותן ב-OR. הסגן אינו מקבל UPDATE בשום מקום.
DROP POLICY IF EXISTS cl_deputy_sel ON clients;
CREATE POLICY cl_deputy_sel ON clients FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM coach_deputies d
                 WHERE d.deputy_email = (auth.jwt()->>'email')
                   AND d.senior_email = clients.coach_email
                   AND d.active));

DROP POLICY IF EXISTS tp_deputy_sel ON training_plans;
CREATE POLICY tp_deputy_sel ON training_plans FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM coach_deputies d
                 JOIN clients c ON c.email = training_plans.client_email
                 WHERE d.deputy_email = (auth.jwt()->>'email')
                   AND d.senior_email = c.coach_email
                   AND d.active));

DROP POLICY IF EXISTS np_deputy_sel ON nutrition_plans;
CREATE POLICY np_deputy_sel ON nutrition_plans FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM coach_deputies d
                 JOIN clients c ON c.email = nutrition_plans.client_email
                 WHERE d.deputy_email = (auth.jwt()->>'email')
                   AND d.senior_email = c.coach_email
                   AND d.active));

DROP POLICY IF EXISTS wl_deputy_sel ON workout_logs;
CREATE POLICY wl_deputy_sel ON workout_logs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM coach_deputies d
                 JOIN clients c ON c.email = workout_logs.client_email
                 WHERE d.deputy_email = (auth.jwt()->>'email')
                   AND d.senior_email = c.coach_email
                   AND d.active));

SELECT 'coach deputies ready' AS r;
