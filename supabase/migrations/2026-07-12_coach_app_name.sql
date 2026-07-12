-- ═══ 📱 PER-COACH BRANDED APP NAME — 2026-07-12 ═══
-- Optional app display name for a coach's branded PWA (dynamic manifest). Additive.
ALTER TABLE coaches ADD COLUMN IF NOT EXISTS app_name text;
SELECT 'app_name ready' AS r;
