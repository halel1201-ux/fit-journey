-- ═══ 💰 עלות מוצר ועמלה מהרווח — 2026-08-15 ═══
-- העמלה חושבה כאחוז ממחיר המכירה, בעוד שהכוונה היא אחוז מהרווח.
-- על מוצר ב-350 ש"ח שעולה 200, ההפרש בעמלה של 25% הוא בין 87.50
-- לבין 37.50 — פי 2.3. כאן נוספת העלות, והחישוב עובר לרווח.

ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS cost numeric(10,2);

/* גם העלות מצולמת בשורת ההזמנה, לצד המחיר והאחוז: עדכון עלות
   בעתיד אסור שישנה את הרווח המדווח על עסקאות שכבר בוצעו. */
ALTER TABLE shop_orders ADD COLUMN IF NOT EXISTS product_cost numeric(10,2);

/* סיכום העמלות מציג כעת גם את הרווח בפועל, לא רק את המחזור. */
DROP VIEW IF EXISTS v_presenter_commissions;
CREATE VIEW v_presenter_commissions
WITH (security_invoker = on) AS
SELECT o.presenter_id,
       coalesce(max(p.name), max(o.presenter_name))                       AS presenter_name,
       max(p.markets)                                                     AS markets,
       max(p.pct)                                                         AS current_pct,
       count(*)                                                           AS orders,
       sum(o.product_price * o.qty)                                       AS gross,
       sum((o.product_price - coalesce(o.product_cost, 0)) * o.qty)       AS profit,
       sum(coalesce(o.commission_amount, 0))                              AS commission
FROM shop_orders o
LEFT JOIN presenters p ON p.id = o.presenter_id
WHERE o.status <> 'cancelled' AND o.presenter_id IS NOT NULL
GROUP BY o.presenter_id;

REVOKE ALL ON v_presenter_commissions FROM anon;

/* רווחיות לפי מוצר — כדי לראות מה באמת מכניס, ולא רק מה נמכר.
   מוצר בלי עלות מסומן, כי עבורו הרווח אינו ידוע והוא מוצג כמלוא
   המחיר — נתון שמטעה אם לא שמים לב אליו. */
CREATE OR REPLACE VIEW v_product_profit
WITH (security_invoker = on) AS
SELECT o.product_id,
       max(o.product_name)                                          AS product_name,
       count(*)                                                     AS orders,
       sum(o.qty)                                                   AS units,
       sum(o.product_price * o.qty)                                 AS revenue,
       sum(coalesce(o.product_cost, 0) * o.qty)                     AS cost,
       sum((o.product_price - coalesce(o.product_cost, 0)) * o.qty) AS profit,
       sum(coalesce(o.commission_amount, 0))                        AS commissions,
       bool_or(o.product_cost IS NULL)                              AS missing_cost
FROM shop_orders o
WHERE o.status <> 'cancelled'
GROUP BY o.product_id;

REVOKE ALL ON v_product_profit FROM anon;

SELECT 'product cost ready' AS r;
