-- ═══ 🥗 מזון מותאם למאמן — 2026-08-17 ═══
-- מוצר שאינו במאגר הכללי נשמר כאן ומתמזג לרשימת המזון של אותו מאמן
-- בלבד. מאמן אחר לא רואה אותו, וגם לא מושפע מערכים שהוזנו ידנית.

CREATE TABLE IF NOT EXISTS coach_foods (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email text NOT NULL,
  name        text NOT NULL,
  calories    numeric(8,2) NOT NULL DEFAULT 0,   -- הכל ל-100 גרם
  protein     numeric(8,2) NOT NULL DEFAULT 0,
  carbs       numeric(8,2) NOT NULL DEFAULT 0,
  fat         numeric(8,2) NOT NULL DEFAULT 0,
  fiber       numeric(8,2),
  unit_g      numeric(8,2),                      -- משקל יחידה, אם רלוונטי
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (coach_email, name)
);
CREATE INDEX IF NOT EXISTS idx_coach_foods ON coach_foods(coach_email, name);

ALTER TABLE coach_foods ENABLE ROW LEVEL SECURITY;

-- המאמן מנהל את המזונות שלו בלבד.
DROP POLICY IF EXISTS cf_owner ON coach_foods;
CREATE POLICY cf_owner ON coach_foods FOR ALL TO authenticated
  USING      (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

/* המתאמן צריך לקרוא את המזונות של המאמן שלו — אחרת תפריט שמכיל
   מוצר מותאם יוצג אצלו בלי ערכים. קריאה בלבד. */
DROP POLICY IF EXISTS cf_client_sel ON coach_foods;
CREATE POLICY cf_client_sel ON coach_foods FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c
                 WHERE c.email = (auth.jwt()->>'email')
                   AND c.coach_email = coach_foods.coach_email));

CREATE OR REPLACE FUNCTION fn_coach_foods_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_coach_foods_touch ON coach_foods;
CREATE TRIGGER trg_coach_foods_touch BEFORE UPDATE ON coach_foods
  FOR EACH ROW EXECUTE FUNCTION fn_coach_foods_touch();

SELECT 'coach foods ready' AS r;
