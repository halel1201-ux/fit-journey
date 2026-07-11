-- ═══ 📞 LEAD CAPTURE (chat) — 2026-07-11 ═══
-- The landing FAQ chat collects a visitor's details into coach_sales as a lead.
-- Add fields for phone / note / source. Additive.

ALTER TABLE coach_sales ADD COLUMN IF NOT EXISTS lead_phone text;
ALTER TABLE coach_sales ADD COLUMN IF NOT EXISTS lead_note  text;
ALTER TABLE coach_sales ADD COLUMN IF NOT EXISTS source     text;   -- chat | pricing | manual

SELECT 'lead capture columns ready' AS r;
