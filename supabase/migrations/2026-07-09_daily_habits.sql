-- ═══ 💧 DAILY HABIT TRACKER — 2026-07-09 ═══
-- A lightweight daily check-in: four habit toggles + sleep hours + mood. One row
-- per client per day; the client owns it, the coach reads it for adherence.
-- Additive; independent of existing steps/water tracking.

CREATE TABLE IF NOT EXISTS daily_habits (
  client_email text NOT NULL,
  date         date NOT NULL,
  water        boolean NOT NULL DEFAULT false,   -- drank enough water
  nutrition    boolean NOT NULL DEFAULT false,   -- stuck to the plan
  sleep        boolean NOT NULL DEFAULT false,   -- slept well
  activity     boolean NOT NULL DEFAULT false,   -- moved / hit steps
  mood         int,                              -- 1..5
  sleep_hours  numeric,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (client_email, date)
);
CREATE INDEX IF NOT EXISTS idx_daily_habits_client ON daily_habits(client_email, date DESC);

ALTER TABLE daily_habits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dh_sel ON daily_habits;
CREATE POLICY dh_sel ON daily_habits FOR SELECT TO authenticated USING (
  client_email = auth.email()
  OR EXISTS (SELECT 1 FROM clients c WHERE c.email = daily_habits.client_email AND c.coach_email = auth.email())
  OR EXISTS (SELECT 1 FROM clients c JOIN studio_coaches sc ON sc.studio_owner_email = c.studio_owner_email
             WHERE c.email = daily_habits.client_email AND sc.coach_email = auth.email() AND sc.status='active')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS dh_cud ON daily_habits;
CREATE POLICY dh_cud ON daily_habits FOR ALL TO authenticated
  USING (client_email = auth.email() OR auth.email()='halel1201@gmail.com')
  WITH CHECK (client_email = auth.email() OR auth.email()='halel1201@gmail.com');

SELECT 'daily habits ready' AS r;
