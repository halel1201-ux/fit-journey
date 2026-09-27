-- ══ תזכורת עדכון שבועי: יום קבוע שהמאמן בוחר ══
--
-- מה היה: צ'ק-אין שבועי (אנרגיה, שינה, מוטיבציה, היצמדות, הערות),
-- בלי משקל, בלי תמונות, ובלי שום תזכורת — המתאמן היה צריך לזכור לבד.
-- בנוסף, בכל שישי המאמן מקבל דוח שקילות (send_weekly_weigh_ins).
--
-- מה נוסף:
--   checkin_day      יום בשבוע לעדכון (0 = ראשון … 6 = שבת).
--                    NULL = אין תזכורת אוטומטית; כפתור "שלח תזכורת
--                    עכשיו" אצל המאמן עובד תמיד.
--   checkin_push_at  היום שבו נשלחה תזכורת — מונע כפילות כשהמאמן
--                    לוחץ ידנית באותו יום שבו גם האוטומטית רצה.
--
-- אדיטיבי בלבד. NULL = ההתנהגות של היום בדיוק. הרצה חוזרת בטוחה.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS checkin_day     smallint,
  ADD COLUMN IF NOT EXISTS checkin_push_at date;

DO $c$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'clients_checkin_day_range') THEN
    ALTER TABLE clients ADD CONSTRAINT clients_checkin_day_range
      CHECK (checkin_day IS NULL OR checkin_day BETWEEN 0 AND 6);
  END IF;
END
$c$;

COMMENT ON COLUMN clients.checkin_day IS
  'יום העדכון השבועי שהמאמן קבע: 0=ראשון … 6=שבת. NULL = בלי תזכורת אוטומטית.';
COMMENT ON COLUMN clients.checkin_push_at IS
  'היום שבו נשלחה תזכורת עדכון. מונע תזכורת כפולה באותו יום.';

-- משקל שנשלח בעדכון השבועי — נשמר גם על הצ'ק-אין עצמו, כדי שהמאמן
-- יראה אותו באותו מקום עם הדירוגים וההערות.
ALTER TABLE checkins
  ADD COLUMN IF NOT EXISTS weight      numeric,
  ADD COLUMN IF NOT EXISTS photo_count smallint;
