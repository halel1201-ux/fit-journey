ALTER TABLE studio_slots ADD COLUMN IF NOT EXISTS booked_count int NOT NULL DEFAULT 0;

-- recompute a slot's active-booking count
CREATE OR REPLACE FUNCTION fn_studio_recount() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE sid bigint;
BEGIN
  sid := COALESCE(NEW.slot_id, OLD.slot_id);
  UPDATE studio_slots s
    SET booked_count = (SELECT count(*) FROM studio_bookings b WHERE b.slot_id = sid AND b.status <> 'cancelled')
    WHERE s.id = sid;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_studio_recount ON studio_bookings;
CREATE TRIGGER trg_studio_recount
  AFTER INSERT OR UPDATE OF status OR DELETE ON studio_bookings
  FOR EACH ROW EXECUTE FUNCTION fn_studio_recount();

-- backfill existing slots
UPDATE studio_slots s SET booked_count =
  (SELECT count(*) FROM studio_bookings b WHERE b.slot_id = s.id AND b.status <> 'cancelled');

SELECT 'booked_count ready' r;
