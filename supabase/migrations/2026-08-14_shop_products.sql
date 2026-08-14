-- ═══ 🧪 קטלוג החנות הפנימית — 2026-08-14 ═══
-- הקטלוג היה רשימה קשיחה בתוך peptides.html, כך שכל הוספת מוצר חייבה
-- עריכת קוד. כאן הוא עובר למסד, והאדמין מנהל אותו מהפאנל.

CREATE TABLE IF NOT EXISTS shop_products (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        text NOT NULL,
  category    text,
  description text,
  spec        text,                      -- מינון / כמות / ריכוז
  price       numeric(10,2),             -- null = "לפרטים"
  was_price   numeric(10,2),             -- מחיר קודם; יוצג מחוק
  image_url   text,
  tag         text,                      -- 'חדש' / 'מבצע'
  in_stock    boolean NOT NULL DEFAULT true,
  visible     boolean NOT NULL DEFAULT true,   -- טיוטה שלא מוצגת בחנות
  sort_order  int NOT NULL DEFAULT 0,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shop_visible ON shop_products(visible, sort_order);

ALTER TABLE shop_products ENABLE ROW LEVEL SECURITY;

-- קריאה: הקטלוג הוא דף ציבורי (מוסתר, לא מוגן), ולכן גם anon קורא —
-- אבל אך ורק מוצרים שסומנו כגלויים. טיוטות נשארות פנימיות.
DROP POLICY IF EXISTS shop_pub_sel ON shop_products;
CREATE POLICY shop_pub_sel ON shop_products FOR SELECT TO anon, authenticated
  USING (visible = true);

-- כתיבה: אדמין בלבד.
DROP POLICY IF EXISTS shop_admin_all ON shop_products;
CREATE POLICY shop_admin_all ON shop_products FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com')
  WITH CHECK (auth.email() = 'halel1201@gmail.com');

-- האדמין רואה גם טיוטות
DROP POLICY IF EXISTS shop_admin_sel ON shop_products;
CREATE POLICY shop_admin_sel ON shop_products FOR SELECT TO authenticated
  USING (auth.email() = 'halel1201@gmail.com');

CREATE OR REPLACE FUNCTION fn_shop_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_shop_touch ON shop_products;
CREATE TRIGGER trg_shop_touch BEFORE UPDATE ON shop_products
  FOR EACH ROW EXECUTE FUNCTION fn_shop_touch();

SELECT 'shop_products ready' AS r;
