-- ═══ 💰 עמלה נצברת רק אחרי אישור תשלום — 2026-08-15 ═══
-- הסיכום ספר כל הזמנה שאינה מבוטלת, כולל כאלה שרק נקלטו ועדיין לא
-- שולמו — ואפילו טיוטות נטושות. כך יכול היה להיווצר חוב לפרזנטור על
-- עסקה שמעולם לא הושלמה. מעתה נספרות רק הזמנות שהאדמין סימן כשולמו
-- (או נשלחו, שכבר עברו דרך אישור התשלום).
--
-- הסכום הממתין מוצג בנפרד, כדי שיהיה ברור מה בצנרת ומה כבר חוב.

DROP VIEW IF EXISTS v_presenter_commissions;
CREATE VIEW v_presenter_commissions
WITH (security_invoker = on) AS
SELECT o.presenter_id,
       coalesce(max(p.name), max(o.presenter_name))                                       AS presenter_name,
       max(p.markets)                                                                     AS markets,
       max(p.pct)                                                                         AS current_pct,

       -- מאושר: התשלום הגיע והאדמין סימן
       count(*) FILTER (WHERE o.status IN ('paid','shipped'))                             AS orders,
       coalesce(sum(o.product_price * o.qty)
                FILTER (WHERE o.status IN ('paid','shipped')), 0)                         AS gross,
       coalesce(sum((o.product_price - coalesce(o.product_cost,0)) * o.qty)
                FILTER (WHERE o.status IN ('paid','shipped')), 0)                         AS profit,
       coalesce(sum(o.commission_amount)
                FILTER (WHERE o.status IN ('paid','shipped')), 0)                         AS commission,

       -- ממתין: נקלט אך טרם אושר תשלום
       count(*) FILTER (WHERE o.status = 'submitted')                                     AS pending_orders,
       coalesce(sum(o.commission_amount) FILTER (WHERE o.status = 'submitted'), 0)        AS pending_commission
FROM shop_orders o
LEFT JOIN presenters p ON p.id = o.presenter_id
WHERE o.presenter_id IS NOT NULL AND o.status <> 'cancelled'
GROUP BY o.presenter_id;

REVOKE ALL ON v_presenter_commissions FROM anon;

-- רווחיות לפי מוצר — גם היא רק על עסקאות שהתשלום בהן אושר
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
WHERE o.status IN ('paid','shipped')
GROUP BY o.product_id;

REVOKE ALL ON v_product_profit FROM anon;

SELECT 'commission on paid ready' AS r;
