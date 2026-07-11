-- ═══ 🤖 PANEL ASSISTANT AUDIT LOG — 2026-07-11 ═══
-- Every assistant query/action a coach runs (panel now; WhatsApp later). Additive.

CREATE TABLE IF NOT EXISTS assistant_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email text NOT NULL,
  query       text NOT NULL,
  answer      text,
  action      text,                    -- null | reminder | freeze | unfreeze
  channel     text NOT NULL DEFAULT 'panel',   -- panel | whatsapp | telegram
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assistant_log ON assistant_log(coach_email, created_at DESC);

ALTER TABLE assistant_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS al_all ON assistant_log;
CREATE POLICY al_all ON assistant_log FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

SELECT 'assistant log ready' AS r;
