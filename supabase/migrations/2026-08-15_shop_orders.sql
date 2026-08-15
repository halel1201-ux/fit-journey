-- ═══ 🛒 הזמנות מהחנות דרך בוט טלגרם — 2026-08-15 ═══
-- שיחה בטלגרם היא חסרת הקשר: כל הודעה מגיעה בנפרד. כדי לשאול כתובת,
-- אמצעי תשלום ומפנה, הבוט חייב לזכור איפה כל לקוח נמצא — וזה תפקיד
-- העמודה step. ההזמנה נשמרת כטיוטה מהרגע הראשון, כך שגם מי שנטש
-- באמצע נשאר גלוי ואפשר לחזור אליו.

CREATE TABLE IF NOT EXISTS shop_orders (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- מי מולנו בטלגרם
  tg_chat_id       bigint NOT NULL,
  tg_username      text,
  tg_name          text,

  -- צילום המוצר בזמן ההזמנה. שם ומחיר נשמרים כאן ולא נקראים מהקטלוג,
  -- כי שינוי מחיר עתידי אסור שישנה הזמנות שכבר בוצעו.
  product_id       bigint,
  product_name     text,
  product_price    numeric(10,2),
  qty              int NOT NULL DEFAULT 1,

  -- פרטי משלוח
  customer_name    text,
  customer_phone   text,
  address          text,
  payment_method   text,

  -- שיוך לפרזנטור. גם האחוז וגם הסכום מצולמים: החוזה עשוי להשתנות,
  -- ומגיע לפרזנטור מה שסוכם ביום המכירה.
  presenter_email  text,
  presenter_name   text,
  commission_pct   numeric(6,2),
  commission_amount numeric(12,2),

  -- draft = בתוך השיחה · submitted = הלקוח אישר · ואז מעקב ידני
  status           text NOT NULL DEFAULT 'draft',
  step             text NOT NULL DEFAULT 'referrer',
  note             text,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  submitted_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_orders_chat   ON shop_orders(tg_chat_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_status ON shop_orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_pres   ON shop_orders(presenter_email, submitted_at DESC);

-- טלגרם שולח את אותו עדכון שוב כשלא קיבל תשובה מהירה. בלי המפתח
-- הזה אותה לחיצה הייתה יוצרת הזמנה כפולה — ועמלה כפולה.
CREATE TABLE IF NOT EXISTS tg_updates (
  update_id  bigint PRIMARY KEY,
  seen_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE shop_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE tg_updates  ENABLE ROW LEVEL SECURITY;

-- הטבלאות מכילות שם, טלפון וכתובת — מידע אישי. גישה לאדמין בלבד;
-- הבוט עצמו כותב עם service_role שעוקף RLS.
DROP POLICY IF EXISTS orders_admin ON shop_orders;
CREATE POLICY orders_admin ON shop_orders FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com')
  WITH CHECK (auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS tgupd_admin ON tg_updates;
CREATE POLICY tgupd_admin ON tg_updates FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com')
  WITH CHECK (auth.email() = 'halel1201@gmail.com');

CREATE OR REPLACE FUNCTION fn_orders_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_orders_touch ON shop_orders;
CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON shop_orders
  FOR EACH ROW EXECUTE FUNCTION fn_orders_touch();

-- סיכום עמלות לפרזנטור, לפי הסכומים שצולמו בזמן ההזמנה
CREATE OR REPLACE VIEW v_presenter_commissions AS
SELECT presenter_email,
       max(presenter_name)                    AS presenter_name,
       count(*)                               AS orders,
       sum(product_price * qty)               AS gross,
       sum(coalesce(commission_amount, 0))    AS commission
FROM shop_orders
WHERE status <> 'cancelled' AND presenter_email IS NOT NULL
GROUP BY presenter_email;

SELECT 'shop_orders ready' AS r;
