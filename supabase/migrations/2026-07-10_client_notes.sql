-- ═══ 📝 PRIVATE CLIENT NOTES / CRM TIMELINE — 2026-07-10 ═══
-- Coach-only notes per client (calls, decisions, observations). Never visible to
-- the client. Additive.

CREATE TABLE IF NOT EXISTS client_notes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email  text NOT NULL,
  client_email text NOT NULL,
  body         text NOT NULL,
  kind         text NOT NULL DEFAULT 'note',   -- note | call | meeting | decision
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_client_notes ON client_notes(coach_email, client_email, created_at DESC);

-- ══ RLS ══ coach owns their notes ONLY (clients must never read them)
ALTER TABLE client_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cn_all ON client_notes;
CREATE POLICY cn_all ON client_notes FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

SELECT 'client notes ready' AS r;
