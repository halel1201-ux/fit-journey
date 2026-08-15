-- ═══ 🎤 פרזנטורים עצמאיים — 2026-08-15 ═══
-- עד כה פרזנטור היה מאמן עם דגל (coaches.is_presenter), אבל פרזנטור
-- הוא לרוב משפיען או שותף שאין לו שום קשר למערכת ואין לו חשבון בה.
-- כאן הוא ישות עצמאית: שם, מה הוא משווק, ואיזה אחוז מגיע לו.
--
-- המנגנון הישן על coaches נשאר כפי שהוא — הוא משרת הפניות של מתאמנים
-- לליווי, וזה זרם אחר.

CREATE TABLE IF NOT EXISTS presenters (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        text NOT NULL,
  phone       text,
  -- מה הוא משווק: 'app' = האפליקציה · 'shop' = החנות · 'both' = שניהם.
  -- קובע גם היכן הוא מוצג לבחירה.
  markets     text NOT NULL DEFAULT 'shop',
  pct         numeric(6,2) NOT NULL DEFAULT 0,   -- אחוז מכל עסקה
  active      boolean NOT NULL DEFAULT true,     -- כיבוי בלי למחוק היסטוריה
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_presenters_active ON presenters(active, markets);

/* ההזמנה מצביעה על הפרזנטור לפי מזהה. השם והאחוז ממשיכים להישמר
   בשורת ההזמנה עצמה — שינוי שם או אחוז בעתיד אסור שישנה עסקאות
   שכבר בוצעו. */
ALTER TABLE shop_orders ADD COLUMN IF NOT EXISTS presenter_id bigint;
CREATE INDEX IF NOT EXISTS idx_orders_presenter_id ON shop_orders(presenter_id, submitted_at DESC);

ALTER TABLE presenters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS presenters_admin ON presenters;
CREATE POLICY presenters_admin ON presenters FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com')
  WITH CHECK (auth.email() = 'halel1201@gmail.com');

CREATE OR REPLACE FUNCTION fn_presenters_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_presenters_touch ON presenters;
CREATE TRIGGER trg_presenters_touch BEFORE UPDATE ON presenters
  FOR EACH ROW EXECUTE FUNCTION fn_presenters_touch();

/* סיכום החוב לכל פרזנטור, לפי הסכומים שצולמו בזמן העסקה.
   security_invoker כדי שה-VIEW יכבד את הרשאות מי שקורא אותו — VIEW
   רגיל רץ בהרשאות הבעלים ועוקף RLS. */
DROP VIEW IF EXISTS v_presenter_commissions;
CREATE VIEW v_presenter_commissions
WITH (security_invoker = on) AS
SELECT o.presenter_id,
       coalesce(max(p.name), max(o.presenter_name))  AS presenter_name,
       max(p.markets)                                AS markets,
       max(p.pct)                                    AS current_pct,
       count(*)                                      AS orders,
       sum(o.product_price * o.qty)                  AS gross,
       sum(coalesce(o.commission_amount, 0))         AS commission
FROM shop_orders o
LEFT JOIN presenters p ON p.id = o.presenter_id
WHERE o.status <> 'cancelled' AND o.presenter_id IS NOT NULL
GROUP BY o.presenter_id;

REVOKE ALL ON v_presenter_commissions FROM anon;

SELECT 'presenters ready' AS r;
