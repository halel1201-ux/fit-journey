-- ═══ 🚫 NO-SHOW TRACKING — 2026-07-09 ═══
-- The coach marks attendance per booked trainee after a class. A no-show (booked,
-- punched, but didn't attend) increments a per-client counter for a warning flag.
-- Additive; regular coach flows untouched.

ALTER TABLE studio_bookings ADD COLUMN IF NOT EXISTS attended boolean;   -- null=unknown, true=showed, false=no-show
ALTER TABLE clients ADD COLUMN IF NOT EXISTS no_show_count int NOT NULL DEFAULT 0;

-- keep clients.no_show_count in sync with attended transitions
CREATE OR REPLACE FUNCTION fn_no_show_count() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.attended IS FALSE AND OLD.attended IS DISTINCT FROM FALSE THEN
      UPDATE clients SET no_show_count = no_show_count + 1 WHERE email = NEW.client_email;
    ELSIF OLD.attended IS FALSE AND NEW.attended IS DISTINCT FROM FALSE THEN
      UPDATE clients SET no_show_count = GREATEST(0, no_show_count - 1) WHERE email = NEW.client_email;
    END IF;
  ELSIF TG_OP = 'INSERT' AND NEW.attended IS FALSE THEN
    UPDATE clients SET no_show_count = no_show_count + 1 WHERE email = NEW.client_email;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_no_show ON studio_bookings;
CREATE TRIGGER trg_no_show
  AFTER INSERT OR UPDATE OF attended ON studio_bookings
  FOR EACH ROW EXECUTE FUNCTION fn_no_show_count();

SELECT 'no-show tracking ready' AS r;
