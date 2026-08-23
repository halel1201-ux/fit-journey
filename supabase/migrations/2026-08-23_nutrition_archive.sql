-- ═══ 🗄 ארכיון תפריטים — 2026-08-23 ═══
-- לתוכניות האימון כבר יש ארכיון בתוך plan.archive, ואפשר לשחזר בלוק
-- שהוחלף. לתפריטים לא היה כלום: כל החלפה דרסה את הקודם לתמיד.
--
-- זה נעשה קריטי עם אישור הצעות מסגן — הבכיר מאשר שינוי, והתפריט
-- שהיה נמחק בלי דרך חזרה.
--
-- עמודה נפרדת ולא שינוי המבנה של plan: plan הוא מערך ארוחות שכל
-- הקוד קורא ישירות, והפיכתו לאובייקט הייתה שוברת כל קורא קיים.

ALTER TABLE nutrition_plans
  ADD COLUMN IF NOT EXISTS archive jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN nutrition_plans.archive IS
  'בלוקים שהוחלפו: [{label, plan, archived_at}] — לשחזור';

SELECT 'nutrition archive ready' AS r;
