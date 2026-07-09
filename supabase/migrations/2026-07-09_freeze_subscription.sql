-- ═══ ❄️ SUBSCRIPTION / PACKAGE FREEZE — 2026-07-09 ═══
-- A coach can pause a client's coaching period. Freezing pushes coaching_end
-- forward by the frozen days (period preserved); while frozen the client can't
-- book studio slots and studio-punch skips them (no session deducted).
-- Additive: nullable column, no impact on existing coach/client flows.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS frozen_until date;

SELECT 'freeze column ready' AS r;
