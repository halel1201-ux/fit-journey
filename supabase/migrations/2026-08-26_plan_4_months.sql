-- ═══ 📅 מסלול 4 חודשים — 2026-08-26 ═══
--
-- האתר מוכר "ליווי 4 חודשים", והפונקציות במסד לא הכירו מסלול כזה:
-- CASE החזיר NULL, ולכן לוח התשלומים חזר ריק והחידוש האוטומטי דילג
-- על המתאמן בשקט. מסלול שנמכר ולא קיים במערכת הוא חוב שמצטבר.
--
-- המסלולים הישנים נשארים: יש מתאמנים פעילים עליהם, והסרתם הייתה
-- מאפסת להם את התאריכים ואת לוח התשלומים.

CREATE OR REPLACE FUNCTION plan_months(p_plan text)
RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_plan
           WHEN 'ליווי חודשי'    THEN 1
           WHEN 'ליווי 3 חודשים' THEN 3
           WHEN 'ליווי 4 חודשים' THEN 4
           WHEN 'ליווי חצי שנה'  THEN 6
           WHEN 'ליווי שנתי'     THEN 12
           ELSE NULL
         END;
$$;
GRANT EXECUTE ON FUNCTION plan_months(text) TO authenticated;

COMMENT ON FUNCTION plan_months(text) IS
  'אורך המסלול בחודשים. מקור אחד — טבלה שכתובה בשלושה מקומות מתפצלת.';

-- ── לוח התשלומים ──
CREATE OR REPLACE FUNCTION build_payment_schedule(p_client text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  cl record; months int; monthly numeric(10,2);
  i int; ps date; pe date; n int := 0;
BEGIN
  SELECT c.email, c.coach_email, c.plan_type, c.coaching_start,
         c.subscription_price, co.plan_prices
    INTO cl
    FROM clients c LEFT JOIN coaches co ON co.email = c.coach_email
   WHERE c.email = p_client;
  IF cl IS NULL THEN RETURN 0; END IF;

  IF  cl.coach_email <> (auth.jwt()->>'email')
  AND NOT is_deputy_client(p_client)
  AND (auth.jwt()->>'email') <> 'halel1201@gmail.com' THEN
    RETURN 0;
  END IF;

  months := plan_months(cl.plan_type);
  IF months IS NULL OR cl.coaching_start IS NULL THEN RETURN 0; END IF;

  monthly := COALESCE(cl.subscription_price,
                      round(NULLIF(cl.plan_prices ->> cl.plan_type, '')::numeric / months, 2));
  IF monthly IS NULL THEN RETURN 0; END IF;

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

-- ── חידוש אוטומטי ──
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
    months := plan_months(r.plan_type);
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

-- ── מי נמצא על מסלול שהמערכת לא מכירה ──
-- מוצג ולא מתוקן: שינוי אוטומטי של מסלול משנה תאריכים וחיובים,
-- וזו החלטה של המאמן ולא של מיגרציה.
SELECT c.email, c.name, c.plan_type, c.coaching_start, c.coaching_end
  FROM clients c
 WHERE c.plan_type IS NOT NULL AND c.plan_type <> ''
   AND plan_months(c.plan_type) IS NULL;
