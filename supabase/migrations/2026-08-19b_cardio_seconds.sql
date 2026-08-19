-- ═══ ⏱ אירובי: צבירה בשניות — 2026-08-19 ═══
-- הצבירה בעצירה חושבה בדקות שלמות, ולכן ריצה קצרה מדקה נצברה כאפס
-- והמונה "חזר אחורה" בכל עצירה. מקור האמת עובר לשניות.
--
-- minutes נשאר קיים כעמודה מחושבת, כדי שכל מה שקורא אותו — תצוגת
-- המאמן ויומן השנה — ימשיך לעבוד בלי שינוי.

ALTER TABLE daily_cardio ADD COLUMN IF NOT EXISTS seconds int NOT NULL DEFAULT 0;

-- שמירה על נתונים שכבר נצברו לפני השינוי
UPDATE daily_cardio SET seconds = minutes * 60
 WHERE seconds = 0 AND minutes > 0;

ALTER TABLE daily_cardio DROP COLUMN IF EXISTS minutes;
ALTER TABLE daily_cardio
  ADD COLUMN minutes int GENERATED ALWAYS AS (seconds / 60) STORED;

SELECT 'cardio seconds ready' AS r;
