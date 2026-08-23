-- ═══ 🤝 חלוקת הכנסה בין בכיר לסגן — 2026-08-23 ═══
--
-- בכיר וסגן מלווים מתאמן ביחד, והכסף צריך להתחלק. ארבע החלטות
-- שהמבנה כאן נגזר מהן:
--
-- 1. הסגן מקבל ממה ש*שולם* בפועל — לא מהחבילה שנמכרה. לכן הבסיס
--    הוא הקבלות, ולא client_packages או חוב פתוח.
-- 2. האחוז הוא פר עסקה. לכן הוא מצולם על הקבלה בזמן ההנפקה ולא
--    נקרא מההגדרה בזמן החישוב — שינוי אחוז היום אינו כותב מחדש
--    את ההיסטוריה.
-- 3. ביטול קבלה מוריד את חלקו, קבלה חדשה מעלה אותו שוב. זה נובע
--    מעצמו מכך שהבסיס הוא הקבלות: קבלה מבוטלת יוצאת מהסכום.
-- 4. לפעמים הסגן הוא זה שגובה. אז הוא מחזיק את כל הסכום וחייב
--    לבכיר את ההפרש — ולכן צריך מאזן דו-כיווני ולא רק "כמה מגיע לו".

-- ── מי מתחלק, כמה, ומי גובה ──
CREATE TABLE IF NOT EXISTS coaching_splits (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  client_email  text NOT NULL,
  senior_email  text NOT NULL,
  deputy_email  text NOT NULL,
  deputy_pct    numeric(5,2) NOT NULL DEFAULT 0
                  CHECK (deputy_pct >= 0 AND deputy_pct <= 100),
  collector     text NOT NULL DEFAULT 'senior'
                  CHECK (collector IN ('senior','deputy')),
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_email, deputy_email)
);
CREATE INDEX IF NOT EXISTS idx_splits_senior ON coaching_splits(senior_email, active);
CREATE INDEX IF NOT EXISTS idx_splits_deputy ON coaching_splits(deputy_email, active);

COMMENT ON TABLE coaching_splits IS
  'ההגדרה הנוכחית של החלוקה. ההיסטוריה מצולמת על הקבלות.';
COMMENT ON COLUMN coaching_splits.collector IS
  'מי גובה מהלקוח: senior = הבכיר, deputy = הסגן (ואז הוא חייב לבכיר)';

-- ── צילום החלוקה על הקבלה ──
-- העמודות האלה הן ההיסטוריה. בלעדיהן שינוי אחוז היה משנה רטרואקטיבית
-- כל התחשבנות שכבר נסגרה.
ALTER TABLE receipts
  ADD COLUMN IF NOT EXISTS split_deputy_email text,
  ADD COLUMN IF NOT EXISTS split_pct          numeric(5,2),
  ADD COLUMN IF NOT EXISTS split_collector    text;

CREATE INDEX IF NOT EXISTS idx_receipts_split ON receipts(split_deputy_email)
  WHERE split_deputy_email IS NOT NULL;

-- ── התחשבנויות שכבר בוצעו ──
CREATE TABLE IF NOT EXISTS split_settlements (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  senior_email  text NOT NULL,
  deputy_email  text NOT NULL,
  amount        numeric(10,2) NOT NULL CHECK (amount > 0),
  direction     text NOT NULL CHECK (direction IN ('to_deputy','to_senior')),
  settled_at    date NOT NULL DEFAULT CURRENT_DATE,
  note          text,
  created_by    text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_settle_pair ON split_settlements(senior_email, deputy_email);

COMMENT ON COLUMN split_settlements.direction IS
  'to_deputy = הבכיר שילם לסגן · to_senior = הסגן העביר לבכיר';

ALTER TABLE coaching_splits   ENABLE ROW LEVEL SECURITY;
ALTER TABLE split_settlements ENABLE ROW LEVEL SECURITY;

-- ── הרשאות ──
-- הבכיר קובע את החלוקה; הסגן רואה אותה ואינו משנה אותה. אחוז
-- שהצד המקבל יכול לערוך אינו הסכם.
DROP POLICY IF EXISTS spl_senior_all ON coaching_splits;
CREATE POLICY spl_senior_all ON coaching_splits FOR ALL TO authenticated
  USING      (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS spl_deputy_sel ON coaching_splits;
CREATE POLICY spl_deputy_sel ON coaching_splits FOR SELECT TO authenticated
  USING (deputy_email = (auth.jwt()->>'email'));

-- התחשבנות רושם רק הבכיר. הסגן רואה — כדי שהמאזן יהיה זהה בשני
-- הצדדים ולא יהיה ויכוח על מה כבר שולם.
DROP POLICY IF EXISTS set_senior_all ON split_settlements;
CREATE POLICY set_senior_all ON split_settlements FOR ALL TO authenticated
  USING      (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (senior_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

DROP POLICY IF EXISTS set_deputy_sel ON split_settlements;
CREATE POLICY set_deputy_sel ON split_settlements FOR SELECT TO authenticated
  USING (deputy_email = (auth.jwt()->>'email'));

-- ── הספר: שורה לכל קבלה שיש בה חלוקה ──
-- תצוגה ולא הרשאת קריאה על receipts: קבלה מכילה את כל התמונה הכספית
-- של הלקוח, והסגן צריך לראות ממנה סכום ואחוז בלבד. התצוגה מסננת
-- בעצמה לפי מי ששואל, ולכן היא אינה חושפת זוגות אחרים.
DROP VIEW IF EXISTS v_split_ledger;
CREATE VIEW v_split_ledger
WITH (security_invoker = off) AS
SELECT r.id                                             AS receipt_id,
       r.receipt_number,
       r.client_email,
       r.client_name,
       r.coach_email                                    AS senior_email,
       r.split_deputy_email                             AS deputy_email,
       r.amount,
       r.split_pct                                      AS pct,
       r.split_collector                                AS collector,
       r.receipt_date,
       (r.cancelled_at IS NOT NULL)                     AS cancelled,
       round(r.amount * COALESCE(r.split_pct, 0) / 100.0, 2) AS deputy_share
FROM receipts r
WHERE r.split_deputy_email IS NOT NULL
  AND (   r.coach_email        = (auth.jwt()->>'email')
       OR r.split_deputy_email = (auth.jwt()->>'email')
       OR auth.email() = 'halel1201@gmail.com');

REVOKE ALL ON v_split_ledger FROM anon;
GRANT SELECT ON v_split_ledger TO authenticated;

-- ── המאזן הדו-כיווני ──
-- הכיוון נקבע לפי מי גבה:
--   הבכיר גבה  → הוא מחזיק את הכסף וחייב לסגן את חלקו.
--   הסגן גבה   → הוא מחזיק את הכל וחייב לבכיר את ההפרש.
-- שני הצדדים נצברים בנפרד ורק בסוף מקוזזים, כדי שהחלון יוכל להראות
-- "לשלם X · לקבל Y" ולא רק את התוצאה — מי ששילם חצי רוצה לראות את
-- שני הסכומים ולא מספר אחד שלא ברור ממה הורכב.
DROP VIEW IF EXISTS v_split_balance;
CREATE VIEW v_split_balance
WITH (security_invoker = off) AS
WITH led AS (
  SELECT senior_email, deputy_email,
         SUM(deputy_share)          FILTER (WHERE NOT cancelled AND collector = 'senior') AS owed_to_deputy,
         SUM(amount - deputy_share) FILTER (WHERE NOT cancelled AND collector = 'deputy') AS owed_to_senior,
         SUM(amount)                FILTER (WHERE NOT cancelled)                          AS gross,
         COUNT(*)                   FILTER (WHERE NOT cancelled)                          AS receipts_count,
         COUNT(*)                   FILTER (WHERE cancelled)                              AS cancelled_count
  FROM v_split_ledger
  GROUP BY senior_email, deputy_email
),
paid AS (
  SELECT senior_email, deputy_email,
         SUM(amount) FILTER (WHERE direction = 'to_deputy') AS paid_to_deputy,
         SUM(amount) FILTER (WHERE direction = 'to_senior') AS paid_to_senior
  FROM split_settlements
  WHERE senior_email = (auth.jwt()->>'email')
     OR deputy_email = (auth.jwt()->>'email')
     OR auth.email() = 'halel1201@gmail.com'
  GROUP BY senior_email, deputy_email
)
SELECT COALESCE(l.senior_email, p.senior_email) AS senior_email,
       COALESCE(l.deputy_email, p.deputy_email) AS deputy_email,
       COALESCE(l.gross, 0)            AS gross,
       COALESCE(l.receipts_count, 0)   AS receipts_count,
       COALESCE(l.cancelled_count, 0)  AS cancelled_count,
       COALESCE(l.owed_to_deputy, 0)   AS owed_to_deputy,
       COALESCE(l.owed_to_senior, 0)   AS owed_to_senior,
       COALESCE(p.paid_to_deputy, 0)   AS paid_to_deputy,
       COALESCE(p.paid_to_senior, 0)   AS paid_to_senior,
       -- חיובי = הבכיר חייב לסגן · שלילי = הסגן חייב לבכיר
       (COALESCE(l.owed_to_deputy, 0) - COALESCE(p.paid_to_deputy, 0))
     - (COALESCE(l.owed_to_senior, 0) - COALESCE(p.paid_to_senior, 0)) AS net
FROM led l
FULL OUTER JOIN paid p
  ON p.senior_email = l.senior_email AND p.deputy_email = l.deputy_email;

REVOKE ALL ON v_split_balance FROM anon;
GRANT SELECT ON v_split_balance TO authenticated;

SELECT 'revenue split ready' AS r;
