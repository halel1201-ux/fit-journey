-- ═══ 🔄 WIN-BACK MARKER — 2026-07-09 ═══
-- Timestamp of the last win-back offer sent to a churned client, so the coach's
-- win-back list doesn't keep re-surfacing the same person. Additive.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS winback_sent_at timestamptz;

SELECT 'winback marker ready' AS r;
