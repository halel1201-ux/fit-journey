-- ═══ 💳 מחיר לחודש, סיכום חבילה ולוח תשלומים — 2026-08-24 ═══
--
-- עד עכשיו היה מספר אחד: "מחיר החבילה". בפועל המאמן חושב בחודשים —
-- 500 לחודש, שלושה חודשים, 1,500 סה"כ — וגובה בתשלומים.
--
-- subscription_price הופך למחיר *לחודש*. סכום החבילה נגזר ממנו כפול
-- מספר החודשים ואינו נשמר בנפרד: שני מספרים שאפשר להם לסתור זה את זה
-- הם באג שמחכה לקרות.
--
-- לוח התשלומים הוא שורה לכל חודש, עם טווח תאריכים משלו. סימון "שולם"
-- מנפיק קבלה — פעולה אחת, לא שתיים שאפשר לשכוח את השנייה.

COMMENT ON COLUMN clients.subscription_price IS
  'מחיר לחודש. NULL = לפי המחירון; 0 = ליווי ללא תשלום. סכום החבילה = מחיר × חודשי המסלול';

CREATE TABLE IF NOT EXISTS client_payments (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  client_email  text NOT NULL,
  coach_email   text NOT NULL,
  seq           int  NOT NULL CHECK (seq >= 1),      -- תשלום מספר N
  total         int  NOT NULL CHECK (total >= 1),    -- מתוך כמה
  period_start  date NOT NULL,
  period_end    date NOT NULL,
  amount        numeric(10,2) NOT NULL CHECK (amount >= 0),
  paid          boolean NOT NULL DEFAULT false,
  paid_at       date,
  paid_by       text,
  receipt_id    bigint,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_email, coach_email, period_start)
);
CREATE INDEX IF NOT EXISTS idx_cpay_client ON client_payments(client_email, seq);

ALTER TABLE client_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cpay_coach_all ON client_payments;
CREATE POLICY cpay_coach_all ON client_payments FOR ALL TO authenticated
  USING      (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- הסגן רואה את לוח התשלומים של מי שהוצמד לו. הוא אינו מעדכן אותו
-- ישירות — הסימון עובר דרך פונקציה, כדי שלא יוכל לשנות סכומים.
DROP POLICY IF EXISTS cpay_deputy_sel ON client_payments;
CREATE POLICY cpay_deputy_sel ON client_payments FOR SELECT TO authenticated
  USING (is_deputy_client(client_email));

-- ── בניית הלוח ──
-- נבנה מחדש בכל שינוי מחיר או תאריכים, אבל *שומר* את מה שכבר סומן
-- כשולם: מחיקה עיוורת הייתה מוחקת קבלות שכבר הונפקו.
CREATE OR REPLACE FUNCTION build_payment_schedule(p_client text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  cl      record;
  months  int;
  monthly numeric(10,2);
  i       int;
  ps      date;
  pe      date;
  n       int := 0;
BEGIN
  SELECT c.email, c.coach_email, c.plan_type, c.coaching_start,
         c.subscription_price, co.plan_prices
    INTO cl
    FROM clients c LEFT JOIN coaches co ON co.email = c.coach_email
   WHERE c.email = p_client;
  IF cl IS NULL THEN RETURN 0; END IF;

  -- רק המאמן של הלקוח, או סגן שהוצמד לו, או האדמין
  IF  cl.coach_email <> (auth.jwt()->>'email')
  AND NOT is_deputy_client(p_client)
  AND (auth.jwt()->>'email') <> 'halel1201@gmail.com' THEN
    RETURN 0;
  END IF;

  months := CASE cl.plan_type
              WHEN 'ליווי חודשי'    THEN 1
              WHEN 'ליווי 3 חודשים' THEN 3
              WHEN 'ליווי חצי שנה'  THEN 6
              WHEN 'ליווי שנתי'     THEN 12
              ELSE NULL END;
  IF months IS NULL OR cl.coaching_start IS NULL THEN RETURN 0; END IF;

  /* מחיר לחודש: פרטני אם הוגדר, אחרת המחירון חלקי מספר החודשים —
     המחירון נקוב לחבילה שלמה. */
  monthly := COALESCE(cl.subscription_price,
                      round(NULLIF(cl.plan_prices ->> cl.plan_type, '')::numeric / months, 2));
  IF monthly IS NULL THEN RETURN 0; END IF;

  -- שורות שטרם שולמו נמחקות ונבנות מחדש; ששולמו נשארות כפי שהן
  DELETE FROM client_payments
   WHERE client_email = p_client AND coach_email = cl.coach_email AND NOT paid;

  FOR i IN 1..months LOOP
    ps := cl.coaching_start + ((i - 1) || ' months')::interval;
    pe := cl.coaching_start + (i || ' months')::interval;
    INSERT INTO client_payments
      (client_email, coach_email, seq, total, period_start, period_end, amount)
    VALUES (p_client, cl.coach_email, i, months, ps, pe, monthly)
    ON CONFLICT (client_email, coach_email, period_start) DO UPDATE
      SET seq = EXCLUDED.seq, total = EXCLUDED.total, period_end = EXCLUDED.period_end,
          amount = CASE WHEN client_payments.paid THEN client_payments.amount
                        ELSE EXCLUDED.amount END;
    n := n + 1;
  END LOOP;
  RETURN n;
END
$fn$;
REVOKE ALL ON FUNCTION build_payment_schedule(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION build_payment_schedule(text) TO authenticated;

-- ── סימון תשלום + הנפקת קבלה ──
-- פעולה אחת. סימון בלי קבלה היה משאיר את הספרים חסרים, וקבלה בלי
-- סימון הייתה מאפשרת לגבות פעמיים על אותו חודש.
-- רץ במסד גם כדי שהסגן יוכל לסמן כשהוא זה שגבה — אין לו הרשאת
-- כתיבה על קבלות, וכאן הוא לא צריך אותה.
CREATE OR REPLACE FUNCTION mark_payment_paid(p_id bigint, p_method text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  pay   record;
  cl    record;
  co    record;
  me    text := (auth.jwt()->>'email');
  num   text;
  nxt   int;
  sp    record;
  HEB   text[] := ARRAY['ינואר','פברואר','מרץ','אפריל','מאי','יוני',
                        'יולי','אוגוסט','ספטמבר','אוקטובר','נובמבר','דצמבר'];
  mnum  int;
  rid   bigint;
BEGIN
  SELECT * INTO pay FROM client_payments WHERE id = p_id;
  IF pay IS NULL THEN RETURN 'not-found'; END IF;
  IF pay.paid THEN RETURN 'already-paid'; END IF;

  IF  pay.coach_email <> me
  AND NOT is_deputy_client(pay.client_email)
  AND me <> 'halel1201@gmail.com' THEN
    RETURN 'forbidden';
  END IF;

  SELECT * INTO cl FROM clients  WHERE email = pay.client_email;
  SELECT * INTO co FROM coaches  WHERE email = pay.coach_email;

  SELECT COALESCE(max(id), 0) + 1 INTO nxt FROM receipts WHERE coach_email = pay.coach_email;
  num  := 'R-' || to_char(CURRENT_DATE, 'YYYY') || '-' || lpad(nxt::text, 4, '0');
  mnum := EXTRACT(MONTH FROM pay.period_start)::int;

  -- צילום החלוקה, בדיוק כמו בהנפקה ידנית
  SELECT * INTO sp FROM coaching_splits
   WHERE client_email = pay.client_email AND active LIMIT 1;

  INSERT INTO receipts (
    receipt_number, coach_email, client_email, client_name, amount, description,
    payment_method, receipt_date, coach_name, business_name,
    biz_number, biz_type, biz_address, biz_phone, vat_rate,
    split_deputy_email, split_pct, split_collector
  ) VALUES (
    num, pay.coach_email, pay.client_email,
    COALESCE(cl.name, split_part(pay.client_email, '@', 1)),
    pay.amount,
    'ליווי עבור ' || COALESCE(cl.name, split_part(pay.client_email, '@', 1)) ||
      ' · חודש ' || mnum || ' ' || HEB[mnum] ||
      ' · תשלום ' || pay.seq || ' מתוך ' || pay.total,
    COALESCE(p_method, 'תשלום חודשי'), CURRENT_DATE,
    COALESCE(co.name, pay.coach_email), COALESCE(co.name, pay.coach_email),
    co.biz_number, COALESCE(co.biz_type, 'exempt'), co.biz_address, co.biz_phone,
    CASE WHEN co.biz_type = 'licensed' THEN COALESCE(co.vat_rate, 18) ELSE NULL END,
    sp.deputy_email, sp.deputy_pct, sp.collector
  ) RETURNING id INTO rid;

  UPDATE client_payments
     SET paid = true, paid_at = CURRENT_DATE, paid_by = me, receipt_id = rid
   WHERE id = p_id;

  -- קיזוז מהחוב, כמו בהנפקה ידנית
  INSERT INTO client_debt_transactions
    (client_email, coach_email, type, status, category, amount, note, txn_date, created_by)
  VALUES (pay.client_email, pay.coach_email, 'payment', 'approved',
          COALESCE(p_method, 'תשלום חודשי'), pay.amount,
          'תשלום ע״פ קבלה ' || num, CURRENT_DATE, me);

  RETURN num;
END
$fn$;
REVOKE ALL ON FUNCTION mark_payment_paid(bigint, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION mark_payment_paid(bigint, text) TO authenticated;

-- ── ביטול סימון ──
-- מבטל את הקבלה (לא מוחק — חובה לשמור תיעוד) ומחזיר את השורה.
CREATE OR REPLACE FUNCTION unmark_payment_paid(p_id bigint)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE pay record; me text := (auth.jwt()->>'email');
BEGIN
  SELECT * INTO pay FROM client_payments WHERE id = p_id;
  IF pay IS NULL THEN RETURN 'not-found'; END IF;
  IF pay.coach_email <> me AND me <> 'halel1201@gmail.com' THEN RETURN 'forbidden'; END IF;

  IF pay.receipt_id IS NOT NULL THEN
    UPDATE receipts SET cancelled_at = now(), cancelled_reason = 'בוטל סימון התשלום'
     WHERE id = pay.receipt_id AND cancelled_at IS NULL;
  END IF;
  UPDATE client_payments
     SET paid = false, paid_at = NULL, paid_by = NULL, receipt_id = NULL
   WHERE id = p_id;
  RETURN 'ok';
END
$fn$;
REVOKE ALL ON FUNCTION unmark_payment_paid(bigint) FROM public, anon;
GRANT EXECUTE ON FUNCTION unmark_payment_paid(bigint) TO authenticated;

-- ── חידוש אוטומטי: המחיר הוא לחודש, החיוב הוא לחבילה ──
CREATE OR REPLACE FUNCTION run_auto_renewals()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r record; months int; new_start date; new_end date; monthly numeric(10,2); n int := 0;
BEGIN
  FOR r IN
    SELECT c.email, c.coach_email, c.plan_type, c.coaching_end,
           c.subscription_price, co.plan_prices
    FROM clients c LEFT JOIN coaches co ON co.email = c.coach_email
    WHERE c.auto_renew AND c.coaching_end IS NOT NULL
      AND c.coaching_end < CURRENT_DATE
      AND (c.last_auto_renew_at IS NULL OR c.last_auto_renew_at < CURRENT_DATE)
      AND (c.frozen_until IS NULL OR c.frozen_until < CURRENT_DATE)
  LOOP
    months := CASE r.plan_type
                WHEN 'ליווי חודשי' THEN 1 WHEN 'ליווי 3 חודשים' THEN 3
                WHEN 'ליווי חצי שנה' THEN 6 WHEN 'ליווי שנתי' THEN 12 ELSE NULL END;
    CONTINUE WHEN months IS NULL;

    new_start := GREATEST(r.coaching_end, CURRENT_DATE);
    new_end   := new_start + (months || ' months')::interval;
    monthly   := COALESCE(r.subscription_price,
                          round(NULLIF(r.plan_prices ->> r.plan_type, '')::numeric / months, 2));

    UPDATE clients
       SET coaching_start = new_start, coaching_end = new_end, last_auto_renew_at = CURRENT_DATE
     WHERE email = r.email;

    IF monthly IS NOT NULL AND monthly > 0 THEN
      INSERT INTO client_debt_transactions
        (client_email, coach_email, type, status, category, amount,
         description, txn_date, created_by)
      VALUES (r.email, r.coach_email, 'charge', 'approved', 'מנוי', monthly * months,
              'חידוש אוטומטי · ' || r.plan_type || ' · ' ||
                to_char(new_start,'DD/MM/YYYY') || '–' || to_char(new_end,'DD/MM/YYYY'),
              CURRENT_DATE, 'חידוש אוטומטי');
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END
$fn$;
REVOKE ALL ON FUNCTION run_auto_renewals() FROM public, anon, authenticated;

SELECT 'payment schedule ready' AS r;
