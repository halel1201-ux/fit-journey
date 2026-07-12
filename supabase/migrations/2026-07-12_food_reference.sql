-- ═══ 🥗 NATIONAL FOOD REFERENCE (4,600+ items) — 2026-07-12 ═══
-- Full Israeli National Nutrition Database (Tzameret, Ministry of Health), per
-- 100g. Powers the autopilot's food answers via keyword retrieval (only the
-- relevant rows are pulled per question — a huge DB without huge prompt cost).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS food_reference (
  id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name     text NOT NULL,          -- Hebrew name (shmmitzrach)
  name_en  text,
  kcal     int  NOT NULL,          -- food_energy, per 100g
  protein  numeric,
  carbs    numeric,
  fat      numeric,
  fiber    numeric,
  sodium   int
);
CREATE INDEX IF NOT EXISTS idx_food_ref_name_trgm ON food_reference USING gin (name gin_trgm_ops);

ALTER TABLE food_reference ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS foodref_read ON food_reference;
CREATE POLICY foodref_read ON food_reference FOR SELECT TO anon, authenticated USING (true);

SELECT 'food_reference ready' AS r;
