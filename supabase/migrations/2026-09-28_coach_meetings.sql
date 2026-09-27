-- ═══ 📅 פגישות מאמן–מתאמן — 2026-09-28 ═══
-- פגישת מעקב שהמאמן קובע: פרונטלית, בווידאו או בשיחה. המתאמן רואה
-- אותה במסך הבית, ובאפליקציה היא נכנסת ליומן שלו עם התראה יום לפני.
-- ביטול או הזזה כאן מתעדכנים ביומן בסנכרון הבא.

CREATE TABLE IF NOT EXISTS coach_meetings (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email   text NOT NULL,
  client_email  text NOT NULL,
  starts_at     timestamptz NOT NULL,
  duration_min  int  NOT NULL DEFAULT 30 CHECK (duration_min BETWEEN 5 AND 480),
  kind          text NOT NULL DEFAULT 'video' CHECK (kind IN ('in_person','video','phone')),
  location      text,           -- כתובת לפרונטלי · קישור לווידאו · מספר לשיחה
  topic         text,           -- מטרת הפגישה (ניתוח התקדמות, בדיקת גוף וכו')
  status        text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','cancelled','done')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meet_client ON coach_meetings(client_email, starts_at);
CREATE INDEX IF NOT EXISTS idx_meet_coach  ON coach_meetings(coach_email, starts_at);

ALTER TABLE coach_meetings ENABLE ROW LEVEL SECURITY;

-- המאמן (או סגן, בשם שלו) מנהל את הפגישות שקבע.
DROP POLICY IF EXISTS cm_owner ON coach_meetings;
CREATE POLICY cm_owner ON coach_meetings FOR ALL TO authenticated
  USING      (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

/* המאמן הראשי רואה גם פגישות שסגן קבע עם מתאמן שלו — אחרת הן
   בלתי נראות לו, והוא עלול לקבוע פגישה כפולה באותה שעה. */
DROP POLICY IF EXISTS cm_senior_sel ON coach_meetings;
CREATE POLICY cm_senior_sel ON coach_meetings FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c
                 WHERE c.email = coach_meetings.client_email
                   AND c.coach_email = (auth.jwt()->>'email')));

-- המתאמן קורא את הפגישות שלו בלבד. אין לו הרשאת כתיבה.
DROP POLICY IF EXISTS cm_client_sel ON coach_meetings;
CREATE POLICY cm_client_sel ON coach_meetings FOR SELECT TO authenticated
  USING (client_email = (auth.jwt()->>'email'));

CREATE OR REPLACE FUNCTION fn_coach_meetings_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_coach_meetings_touch ON coach_meetings;
CREATE TRIGGER trg_coach_meetings_touch BEFORE UPDATE ON coach_meetings
  FOR EACH ROW EXECUTE FUNCTION fn_coach_meetings_touch();

SELECT 'coach meetings ready' AS r;
