-- ═══ 🔔 PROACTIVE RENEWAL NUDGE — 2026-07-09 ═══
-- Markers so the daily renewal-nudge cron nudges each client at most once per
-- expiry window (period ending soon / punch card running low). Additive.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS renewal_nudge_end  date;              -- last coaching_end we nudged for
ALTER TABLE clients ADD COLUMN IF NOT EXISTS renewal_nudge_card boolean NOT NULL DEFAULT false; -- nudged for low card this cycle

SELECT 'renewal nudge markers ready' AS r;
