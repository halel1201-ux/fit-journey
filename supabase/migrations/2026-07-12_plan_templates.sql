-- ═══ 📚 PLAN TEMPLATE LIBRARY — 2026-07-12 ═══
-- Reusable training / nutrition templates a coach saves once and applies to any
-- client in one click. Additive.

CREATE TABLE IF NOT EXISTS plan_templates (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email text NOT NULL,
  kind        text NOT NULL,        -- training | nutrition
  name        text NOT NULL,
  plan        jsonb NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_plan_templates ON plan_templates(coach_email, kind, created_at DESC);

ALTER TABLE plan_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pt_all ON plan_templates;
CREATE POLICY pt_all ON plan_templates FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

SELECT 'plan_templates ready' AS r;
