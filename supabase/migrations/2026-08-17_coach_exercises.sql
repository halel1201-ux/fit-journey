-- ═══ 🎬 מאגר תרגילים פרטי למאמן — 2026-08-17 ═══
-- כשמאמן מעלה סרטון לתרגיל שאין לו סרטון במאגר הכללי, הסרטון נשמר
-- כאן תחת שם התרגיל שאליו הוצמד, ומתמזג לספריית התרגילים שלו בלבד.
--
-- custom_exercises הקיימת היא גלובלית ובניהול אדמין; זו נפרדת ממנה
-- בכוונה, כדי שמאמן לא ישנה את המאגר של כולם.

CREATE TABLE IF NOT EXISTS coach_exercises (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email  text NOT NULL,
  name         text NOT NULL,
  muscle_group text,
  video_url    text,
  thumb_url    text,
  cues         text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (coach_email, name)
);
CREATE INDEX IF NOT EXISTS idx_coach_ex ON coach_exercises(coach_email, name);

ALTER TABLE coach_exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ce_owner ON coach_exercises;
CREATE POLICY ce_owner ON coach_exercises FOR ALL TO authenticated
  USING      (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

/* המתאמן חייב לקרוא — אחרת תרגיל עם סרטון של המאמן יוצג אצלו בלי
   הדגמה, וזו בדיוק הסיבה שהסרטון הועלה. */
DROP POLICY IF EXISTS ce_client_sel ON coach_exercises;
CREATE POLICY ce_client_sel ON coach_exercises FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c
                 WHERE c.email = (auth.jwt()->>'email')
                   AND c.coach_email = coach_exercises.coach_email));

CREATE OR REPLACE FUNCTION fn_coach_ex_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_coach_ex_touch ON coach_exercises;
CREATE TRIGGER trg_coach_ex_touch BEFORE UPDATE ON coach_exercises
  FOR EACH ROW EXECUTE FUNCTION fn_coach_ex_touch();

SELECT 'coach exercises ready' AS r;
