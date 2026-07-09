-- ═══ 🎁 REFERRAL PROGRAM — 2026-07-09 ═══
-- Each client gets a personal referral code to share. A new client attributed to
-- that code creates a pending referral; the coach rewards both in one click.
-- Additive; regular coach flows untouched.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS referral_code    text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS referred_by_code text;   -- code the client signed up with
CREATE UNIQUE INDEX IF NOT EXISTS uq_clients_referral_code ON clients(referral_code) WHERE referral_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS referrals (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email    text NOT NULL,
  referrer_email text NOT NULL,
  referee_email  text NOT NULL,
  referee_name   text,
  status         text NOT NULL DEFAULT 'pending',   -- pending | rewarded
  reward_note    text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  rewarded_at    timestamptz,
  UNIQUE (referee_email)                             -- a client can only be referred once
);
CREATE INDEX IF NOT EXISTS idx_referrals_coach ON referrals(coach_email, status);

-- ══ RLS ══ coach/owner manages their own; client sees referrals they are part of; admin all
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ref_sel ON referrals;
CREATE POLICY ref_sel ON referrals FOR SELECT TO authenticated USING (
  coach_email = (auth.jwt()->>'email')
  OR referrer_email = (auth.jwt()->>'email')
  OR referee_email = (auth.jwt()->>'email')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS ref_all ON referrals;
CREATE POLICY ref_all ON referrals FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

SELECT 'referral program ready' AS r;
