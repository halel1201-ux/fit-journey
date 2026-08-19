-- ═══ ❤️ אירובי יומי — 2026-08-19 ═══
-- שורה אחת למתאמן ליום. המתאמן מפעיל ועוצר שעון, המאמן קובע יעד דקות
-- וצופה בתוצאה. תוספת בלבד: אינה נוגעת ב-workout_logs, daily_steps או
-- daily_habits, וכל הפיצ'רים הקיימים ממשיכים לעבוד בלעדיה.

CREATE TABLE IF NOT EXISTS daily_cardio (
  client_email  text NOT NULL,
  date          date NOT NULL,
  minutes       int  NOT NULL DEFAULT 0,   -- דקות שנצברו והסתיימו
  /* מתי הופעל השעון שרץ כרגע. נשמר בשרת ולא בדפדפן, כדי שסגירת
     האפליקציה באמצע אירובי לא תאפס את הספירה: בטעינה מחדש מחשבים
     את הזמן שעבר מהחותמת הזו ומוסיפים אותו לתצוגה. NULL = עצור. */
  running_since timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (client_email, date)
);
CREATE INDEX IF NOT EXISTS idx_daily_cardio_client ON daily_cardio(client_email, date DESC);

ALTER TABLE daily_cardio ENABLE ROW LEVEL SECURITY;

-- קריאה: המתאמן עצמו, המאמן שלו, מאמן סטודיו פעיל, סגן פעיל, אדמין.
DROP POLICY IF EXISTS dc_sel ON daily_cardio;
CREATE POLICY dc_sel ON daily_cardio FOR SELECT TO authenticated USING (
  client_email = auth.email()
  OR EXISTS (SELECT 1 FROM clients c
             WHERE c.email = daily_cardio.client_email AND c.coach_email = auth.email())
  OR EXISTS (SELECT 1 FROM clients c JOIN studio_coaches sc ON sc.studio_owner_email = c.studio_owner_email
             WHERE c.email = daily_cardio.client_email AND sc.coach_email = auth.email() AND sc.status = 'active')
  OR EXISTS (SELECT 1 FROM clients c JOIN coach_deputies d ON d.senior_email = c.coach_email
             WHERE c.email = daily_cardio.client_email AND d.deputy_email = auth.email() AND d.active)
  OR auth.email() = 'halel1201@gmail.com');

/* כתיבה: המתאמן בלבד. השעון הוא שלו — מאמן שיכתוב לכאן ישבש מדידה
   של מישהו אחר, ולכן היעד נשמר בנפרד על כרטיס הלקוח. */
DROP POLICY IF EXISTS dc_cud ON daily_cardio;
CREATE POLICY dc_cud ON daily_cardio FOR ALL TO authenticated
  USING      (client_email = auth.email() OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (client_email = auth.email() OR auth.email() = 'halel1201@gmail.com');

-- יעד הדקות היומי שהמאמן קובע. NULL = לא הוגדר אירובי למתאמן הזה,
-- ואז הווידג'ט כלל לא מוצג לו.
ALTER TABLE clients ADD COLUMN IF NOT EXISTS cardio_daily_min int;

SELECT 'daily cardio ready' AS r;
