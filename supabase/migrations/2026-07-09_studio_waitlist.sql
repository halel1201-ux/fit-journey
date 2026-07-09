-- ═══ 📋 STUDIO WAITLIST + AUTO-PROMOTE — 2026-07-09 ═══
-- Clients join a waitlist for a full class. When a spot frees up (a booking is
-- cancelled/deleted), the oldest eligible waitlisted client is auto-promoted into
-- a real booking and notified. Additive; regular coach flows untouched.

CREATE TABLE IF NOT EXISTS studio_waitlist (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email  text NOT NULL,
  slot_id      bigint NOT NULL REFERENCES studio_slots(id) ON DELETE CASCADE,
  client_email text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (slot_id, client_email)
);
CREATE INDEX IF NOT EXISTS idx_swl_slot ON studio_waitlist(slot_id, created_at);

-- ══ RLS ══ client manages own row; owner + studio coach read; admin all
ALTER TABLE studio_waitlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS swl_sel ON studio_waitlist;
CREATE POLICY swl_sel ON studio_waitlist FOR SELECT TO authenticated USING (
  client_email = (auth.jwt()->>'email')
  OR owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_waitlist.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS swl_ins ON studio_waitlist;
CREATE POLICY swl_ins ON studio_waitlist FOR INSERT TO authenticated
  WITH CHECK (client_email = (auth.jwt()->>'email') OR owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS swl_del ON studio_waitlist;
CREATE POLICY swl_del ON studio_waitlist FOR DELETE TO authenticated USING (
  client_email = (auth.jwt()->>'email') OR owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- ══ AUTO-PROMOTE ══ when a booking leaves the active set, fill freed spots
CREATE OR REPLACE FUNCTION fn_studio_promote_waitlist() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  sid  bigint;
  cap  int;
  slotstart timestamptz;
  active int;
  promoted boolean;
  cand studio_waitlist%ROWTYPE;
  cand_active int;
  cand_rem int;
  cand_frozen date;
BEGIN
  sid := COALESCE(NEW.slot_id, OLD.slot_id);
  SELECT max_trainees, slot_start INTO cap, slotstart FROM studio_slots WHERE id = sid;
  IF cap IS NULL THEN RETURN NULL; END IF;
  -- don't promote into a class that already started
  IF slotstart <= now() THEN RETURN NULL; END IF;

  LOOP
    SELECT count(*) INTO active FROM studio_bookings WHERE slot_id = sid AND status <> 'cancelled';
    EXIT WHEN active >= cap;  -- no free spot

    promoted := false;
    -- oldest waitlisted client who is eligible (not already booked here, not frozen, has balance)
    FOR cand IN
      SELECT * FROM studio_waitlist WHERE slot_id = sid ORDER BY created_at ASC
    LOOP
      -- already booked in this slot? clean up + skip
      IF EXISTS (SELECT 1 FROM studio_bookings b WHERE b.slot_id = sid AND b.client_email = cand.client_email AND b.status <> 'cancelled') THEN
        DELETE FROM studio_waitlist WHERE id = cand.id; CONTINUE;
      END IF;
      SELECT sessions_remaining, frozen_until INTO cand_rem, cand_frozen FROM clients WHERE email = cand.client_email;
      IF cand_frozen IS NOT NULL AND cand_frozen >= (now() AT TIME ZONE 'Asia/Jerusalem')::date THEN CONTINUE; END IF;
      SELECT count(*) INTO cand_active FROM studio_bookings WHERE owner_email = cand.owner_email AND client_email = cand.client_email AND status <> 'cancelled';
      IF cand_active >= COALESCE(cand_rem,0) THEN CONTINUE; END IF;  -- no balance for another booking
      -- promote!
      INSERT INTO studio_bookings (slot_id, owner_email, client_email, status, punched)
        VALUES (sid, cand.owner_email, cand.client_email, 'booked', false)
        ON CONFLICT DO NOTHING;
      DELETE FROM studio_waitlist WHERE id = cand.id;
      INSERT INTO messages (coach_email, client_email, sender_email, content)
        VALUES (cand.owner_email, cand.client_email, cand.owner_email,
          '🎉 התפנה מקום! שובצת אוטומטית לשיעור מרשימת ההמתנה — נתראה שם 💪');
      promoted := true;
      EXIT;  -- one spot filled, re-check capacity in outer LOOP
    END LOOP;
    -- nobody eligible was promoted this pass → stop (avoids infinite loop)
    EXIT WHEN NOT promoted;
  END LOOP;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_studio_promote ON studio_bookings;
CREATE TRIGGER trg_studio_promote
  AFTER UPDATE OF status OR DELETE ON studio_bookings
  FOR EACH ROW EXECUTE FUNCTION fn_studio_promote_waitlist();

SELECT 'studio waitlist + auto-promote ready' AS r;
