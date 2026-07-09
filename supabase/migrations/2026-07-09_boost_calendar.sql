-- ═══ BOOST-STYLE STUDIO CALENDAR — 2026-07-09 ═══
-- Class types (colored), a weekly recurring template (same every week, coach
-- varies), and concrete dated instances materialized into studio_slots.

-- class types (colored, default coach + capacity)
CREATE TABLE IF NOT EXISTS studio_class_types (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  name text NOT NULL,
  color text NOT NULL DEFAULT '#6d8cff',
  default_coach_email text,
  default_capacity int NOT NULL DEFAULT 8,
  duration_min int NOT NULL DEFAULT 60,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sct_owner ON studio_class_types(owner_email);

-- weekly recurring template (weekday 0=Sun..6=Sat + time)
CREATE TABLE IF NOT EXISTS studio_recurring_classes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  class_type_id bigint REFERENCES studio_class_types(id) ON DELETE CASCADE,
  weekday int NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time text NOT NULL,                 -- 'HH:MM'
  duration_min int NOT NULL DEFAULT 60,
  coach_email text,
  max_trainees int NOT NULL DEFAULT 8,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_src_owner ON studio_recurring_classes(owner_email, weekday);

-- extend concrete slots with class/coach/status/visibility/recurrence link
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS class_type_id bigint;
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS coach_email text;
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS recurring_id bigint;
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'scheduled';   -- scheduled | done | cancelled
ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS visible boolean NOT NULL DEFAULT true;
-- prevent duplicate materialization of the same recurring class on the same date
CREATE UNIQUE INDEX IF NOT EXISTS uq_slot_recurring_date
  ON studio_slots(recurring_id, ((slot_start AT TIME ZONE 'Asia/Jerusalem')::date))
  WHERE recurring_id IS NOT NULL;

-- ══ RLS ══ (owner writes; studio coaches + studio clients read; admin all)
ALTER TABLE studio_class_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_recurring_classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sct_sel ON studio_class_types;
CREATE POLICY sct_sel ON studio_class_types FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_class_types.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR EXISTS (SELECT 1 FROM clients c WHERE c.email = (auth.jwt()->>'email') AND c.studio_owner_email = studio_class_types.owner_email)
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS sct_all ON studio_class_types;
CREATE POLICY sct_all ON studio_class_types FOR ALL TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

DROP POLICY IF EXISTS src_sel ON studio_recurring_classes;
CREATE POLICY src_sel ON studio_recurring_classes FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_recurring_classes.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR EXISTS (SELECT 1 FROM clients c WHERE c.email = (auth.jwt()->>'email') AND c.studio_owner_email = studio_recurring_classes.owner_email)
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS src_all ON studio_recurring_classes;
CREATE POLICY src_all ON studio_recurring_classes FOR ALL TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

SELECT 'boost calendar schema ready' AS r;
