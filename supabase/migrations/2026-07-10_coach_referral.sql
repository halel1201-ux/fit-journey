-- ═══ 🤝 COACH REFERRAL — 2026-07-10 ═══
-- A coach refers another coach; when the referred coach's subscription is
-- activated (admin moves them off 'pending'), the referrer earns bonus tokens.
-- Tracked on the coaches row to avoid fragile anonymous signup inserts. Additive.

ALTER TABLE coaches ADD COLUMN IF NOT EXISTS referral_code      text;
ALTER TABLE coaches ADD COLUMN IF NOT EXISTS referred_by_code   text;   -- code used at signup
ALTER TABLE coaches ADD COLUMN IF NOT EXISTS referral_rewarded  boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS uq_coaches_referral_code ON coaches(referral_code) WHERE referral_code IS NOT NULL;

SELECT 'coach referral columns ready' AS r;
