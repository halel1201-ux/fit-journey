-- ═══ 💰 מחיר מנוי, חידוש אוטומטי וסגן מטפל — 2026-08-23 ═══
--
-- עד עכשיו לא היה במערכת שום מקום שאומר כמה לקוח משלם. סוג המנוי
-- קבע תאריכים בלבד, והסכום הוקלד ידנית בכל חיוב מחדש. שלוש תוספות:
--
-- 1. מחירון לפי סוג מנוי, ברמת המאמן. זהו "המחיר הרגיל".
-- 2. מחיר פרטני ללקוח, שגובר על המחירון. NULL פירושו "לפי המחירון" —
--    ולכן 0 הוא מחיר אמיתי (ליווי חינם) ולא "לא הוגדר". ההבחנה הזאת
--    היא כל העניין: יש לקוחות עם הנחת חיילים, הנחת זוג או הנחת חבר.
-- 3. חידוש אוטומטי: כשהתקופה נגמרת המנוי מתארך והסכום נכנס לחוב.

ALTER TABLE coaches
  ADD COLUMN IF NOT EXISTS plan_prices jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN coaches.plan_prices IS
  'מחירון המאמן: {"ליווי חודשי": 400, ...} — המחיר הרגיל לכל סוג מנוי';

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS subscription_price  numeric(10,2),   -- NULL = לפי המחירון
  ADD COLUMN IF NOT EXISTS auto_renew          boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_auto_renew_at  date;            -- מונע חידוש כפול באותו יום

COMMENT ON COLUMN clients.subscription_price IS
  'מחיר פרטני ללקוח. NULL = לפי מחירון המאמן; 0 = ליווי ללא תשלום';

-- ── סגן מטפל ──
-- אין עמודה חדשה: השיוך כבר יושב ב-client_deputies, ומדיניות ה-RLS
-- של הסגן נשענת עליו. הוספת עמודה מקבילה הייתה יוצרת שני מקורות
-- אמת שאפשר להם לסתור זה את זה. הבחירה "סגן מטפל" בכרטיס הלקוח
-- כותבת לאותה טבלה בדיוק.

-- ═══ חידוש אוטומטי ═══
-- רץ במסד ולא בדפדפן: חידוש שתלוי בכך שמישהו פתח את הפאנל אינו
-- חידוש אוטומטי. הפונקציה בטוחה להרצה חוזרת — last_auto_renew_at
-- חוסם מחזור שני באותו יום, והתאריך החדש תמיד עתידי ולכן הלקוח
-- יוצא מתנאי הסינון.
CREATE OR REPLACE FUNCTION run_auto_renewals()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r          record;
  months     int;
  new_start  date;
  new_end    date;
  amt        numeric(10,2);
  n          int := 0;
BEGIN
  FOR r IN
    SELECT c.email, c.coach_email, c.plan_type, c.coaching_end,
           c.subscription_price, co.plan_prices
    FROM clients c
    LEFT JOIN coaches co ON co.email = c.coach_email
    WHERE c.auto_renew
      AND c.coaching_end IS NOT NULL
      AND c.coaching_end < CURRENT_DATE
      AND (c.last_auto_renew_at IS NULL OR c.last_auto_renew_at < CURRENT_DATE)
      AND (c.frozen_until IS NULL OR c.frozen_until < CURRENT_DATE)
  LOOP
    months := CASE r.plan_type
                WHEN 'ליווי חודשי'    THEN 1
                WHEN 'ליווי 3 חודשים' THEN 3
                WHEN 'ליווי חצי שנה'  THEN 6
                WHEN 'ליווי שנתי'     THEN 12
                ELSE NULL END;
    CONTINUE WHEN months IS NULL;          -- מנוי ידני אינו מתחדש מעצמו

    /* מנוי שפג לפני חודשים לא מקבל שרשרת חיובים רטרואקטיביים:
       תקופה אחת, מהמאוחר מבין סוף התקופה להיום. */
    new_start := GREATEST(r.coaching_end, CURRENT_DATE);
    new_end   := new_start + (months || ' months')::interval;

    amt := COALESCE(r.subscription_price,
                    NULLIF(r.plan_prices ->> r.plan_type, '')::numeric);

    UPDATE clients
       SET coaching_start     = new_start,
           coaching_end       = new_end,
           last_auto_renew_at = CURRENT_DATE
     WHERE email = r.email;

    /* חיוב נרשם רק כשידוע כמה. מחירון ריק ובלי מחיר פרטני — המנוי
       מוארך והמאמן יראה שאין סכום, במקום שייווצר חוב של אפס שנראה
       כאילו הלקוח לא חייב כלום. */
    IF amt IS NOT NULL AND amt > 0 THEN
      INSERT INTO client_debt_transactions
        (client_email, coach_email, type, status, category, amount,
         description, txn_date, created_by)
      VALUES
        (r.email, r.coach_email, 'charge', 'approved', 'מנוי', amt,
         'חידוש אוטומטי · ' || r.plan_type || ' · ' ||
           to_char(new_start, 'DD/MM/YYYY') || '–' || to_char(new_end, 'DD/MM/YYYY'),
         CURRENT_DATE, 'חידוש אוטומטי');
    END IF;

    n := n + 1;
  END LOOP;
  RETURN n;
END
$fn$;

REVOKE ALL ON FUNCTION run_auto_renewals() FROM public;

COMMENT ON FUNCTION run_auto_renewals() IS
  'מאריך מנויים שפגו עם חידוש אוטומטי ורושם את החיוב. בטוח להרצה חוזרת.';

-- ── הרצה יומית ──
-- 03:10 UTC, כלומר לפנות בוקר בישראל: השעה שבה אף אחד לא עובד על
-- הפאנל, כדי שחידוש לא ייפול באמצע עריכה של המאמן.
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('auto-renewals')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-renewals');
    PERFORM cron.schedule('auto-renewals', '10 3 * * *', 'SELECT run_auto_renewals()');
  END IF;
END
$cron$;

SELECT 'pricing + auto-renew ready' AS r;
