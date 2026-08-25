-- ═══ ⚖️ דוח שקילות שבועי אוטומטי — 2026-08-25 ═══
--
-- המתאמן נשקל כל בוקר, והמאמן היה צריך להיכנס לכל כרטיס בנפרד כדי
-- לראות. הדוח נשלח מעצמו לצ'אט של אותו מתאמן בסוף השבוע.
--
-- רץ במסד ולא בדפדפן: דוח שתלוי בכך שמישהו פתח את האפליקציה אינו
-- דוח אוטומטי, ובדיוק בסוף השבוע אף אחד לא פותח.
--
-- שבוע העבודה כאן הוא ראשון–חמישי. שישי ושבת אינם נספרים בממוצע
-- במכוון: הם ימי אכילה שונים, ומשקל שנמדד בהם מטה את המגמה ומקשה
-- להשוות שבוע לשבוע.

-- מונע שליחה כפולה של אותו שבוע — הפונקציה רצה כל יום.
CREATE TABLE IF NOT EXISTS weigh_in_reports (
  client_email text NOT NULL,
  week_start   date NOT NULL,
  sent_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (client_email, week_start)
);
ALTER TABLE weigh_in_reports ENABLE ROW LEVEL SECURITY;
-- אין מדיניות: רק הפונקציה (SECURITY DEFINER) נוגעת בטבלה.

CREATE OR REPLACE FUNCTION send_weekly_weigh_ins(p_force boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r        record;
  e        record;
  wk_start date;
  wk_end   date;
  body     text;
  cnt      int;
  total    numeric;
  avg_w    numeric;
  n        int := 0;
  HEB_DAY  text[] := ARRAY['ראשון','שני','שלישי','רביעי','חמישי','שישי','שבת'];
BEGIN
  /* השבוע שהסתיים. הפונקציה רצה בשישי בבוקר, ולכן "השבוע שלה" הוא
     ראשון האחרון עד חמישי. date_trunc בפוסטגרס פותח שבוע ביום שני,
     ולכן היום מחושב ידנית: EXTRACT(DOW) מחזיר 0 לראשון. */
  wk_start := CURRENT_DATE - EXTRACT(DOW FROM CURRENT_DATE)::int;
  IF EXTRACT(DOW FROM CURRENT_DATE)::int = 6 THEN      -- שבת שייכת לשבוע שנפתח אתמול
    wk_start := CURRENT_DATE - 6;
  END IF;
  wk_end := wk_start + 4;                              -- חמישי

  FOR r IN
    SELECT c.email, c.name, c.coach_email
      FROM clients c
     WHERE c.coach_email IS NOT NULL AND c.coach_email <> ''
       AND (c.coaching_end IS NULL OR c.coaching_end >= wk_start)
  LOOP
    CONTINUE WHEN NOT p_force AND EXISTS (
      SELECT 1 FROM weigh_in_reports w
       WHERE w.client_email = r.email AND w.week_start = wk_start);

    body  := '';
    cnt   := 0;
    total := 0;

    /* רק ימים שבהם באמת הוזנה שקילה. יום ריק אינו מוצג כאפס —
       אפס הוא מדידה, והיעדר מדידה הוא לא. */
    FOR e IN
      SELECT p.date, p.weight
        FROM progress_entries p
       WHERE p.client_email = r.email
         AND p.date BETWEEN wk_start AND wk_end
         AND p.weight IS NOT NULL AND p.weight > 0
       ORDER BY p.date
    LOOP
      body := body || to_char(e.date, 'FMDD/FMMM') || ' יום ' ||
              HEB_DAY[EXTRACT(DOW FROM e.date)::int + 1] || ' — ' ||
              trim(to_char(e.weight, 'FM999990.9')) || ' ק״ג' || E'\n';
      cnt   := cnt + 1;
      total := total + e.weight;
    END LOOP;

    CONTINUE WHEN cnt = 0;                             -- לא נשקל השבוע — אין מה לשלוח

    avg_w := round(total / cnt, 1);
    body  := '⚖️ שקילות השבוע — ' || COALESCE(r.name, split_part(r.email, '@', 1)) || E'\n' ||
             to_char(wk_start, 'FMDD/FMMM') || '–' || to_char(wk_end, 'FMDD/FMMM') || E'\n\n' ||
             body ||
             '━━━━━━━━━━' || E'\n' ||
             'ממוצע שבועי: ' || trim(to_char(avg_w, 'FM999990.9')) || ' ק״ג' ||
             ' (' || cnt || ' שקילות)';

    /* ההודעה נשלחת בשם המתאמן, לשרשור של המאמן שלו — כך היא מופיעה
       בצ'אט הרגיל ונספרת כהודעה שממתינה לו. */
    INSERT INTO messages (coach_email, client_email, sender_email, content)
    VALUES (r.coach_email, r.email, r.email, body);

    INSERT INTO weigh_in_reports (client_email, week_start)
    VALUES (r.email, wk_start)
    ON CONFLICT (client_email, week_start) DO NOTHING;

    n := n + 1;
  END LOOP;
  RETURN n;
END
$fn$;

REVOKE ALL ON FUNCTION send_weekly_weigh_ins(boolean) FROM public, anon, authenticated;

COMMENT ON FUNCTION send_weekly_weigh_ins(boolean) IS
  'שולח לכל מאמן דוח שקילות ראשון–חמישי של כל מתאמן. בטוח להרצה חוזרת.';

-- ── הרצה שבועית ──
-- שישי 05:00 UTC — בוקר ישראל, אחרי שקילת חמישי ולפני שהמאמן פותח.
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('weekly-weigh-ins')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-weigh-ins');
    PERFORM cron.schedule('weekly-weigh-ins', '0 5 * * 5', 'SELECT send_weekly_weigh_ins()');
  END IF;
END
$cron$;

SELECT 'weekly weigh-in report ready' AS r;
