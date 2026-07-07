-- ═══ STUDIO OWNER MODULE — schema + RLS (additive, 2026-07-07) ═══
-- Roles: coaches.role may now be 'studio_owner'. Coaches under a studio are linked
-- in studio_coaches. Studio clients live in clients with client_type/studio fields.
-- Helper predicates used inline:
--   admin:   auth.email() = 'halel1201@gmail.com'
--   me:      (auth.jwt()->>'email')
--   scoach:  EXISTS(studio_coaches sc WHERE sc.studio_owner_email=<owner> AND sc.coach_email=me AND sc.status='active')

-- ── clients: studio fields ──────────────────────────────────────────────
ALTER TABLE clients ADD COLUMN IF NOT EXISTS client_type text DEFAULT 'coaching';   -- coaching | studio | both
ALTER TABLE clients ADD COLUMN IF NOT EXISTS studio_owner_email text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS sessions_remaining int DEFAULT 0;       -- punch-card balance
ALTER TABLE clients ADD COLUMN IF NOT EXISTS injuries jsonb DEFAULT '[]'::jsonb;      -- [{note,by,at}]

-- ── studios (one row per owner) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS studios (
  owner_email text PRIMARY KEY,
  name text,
  client_capacity int NOT NULL DEFAULT 50,
  coach_capacity  int NOT NULL DEFAULT 1,     -- extra coaches beyond the owner
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ── package / DLC purchases (each = a monthly contract/quote) ───────────
CREATE TABLE IF NOT EXISTS studio_dlc (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  kind text NOT NULL,                          -- base | clients_50 | coach
  qty int NOT NULL DEFAULT 1,
  monthly_price int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'quote',        -- quote | active | cancelled
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sdlc_owner ON studio_dlc(owner_email);

-- ── coaches under a studio ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS studio_coaches (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  studio_owner_email text NOT NULL,
  coach_email text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  UNIQUE(studio_owner_email, coach_email)
);
CREATE INDEX IF NOT EXISTS idx_scoach_owner ON studio_coaches(studio_owner_email);
CREATE INDEX IF NOT EXISTS idx_scoach_coach ON studio_coaches(coach_email);

-- ── activity slots (owner defines) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS studio_slots (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  slot_start timestamptz NOT NULL,
  slot_end   timestamptz,
  max_trainees int NOT NULL DEFAULT 1,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sslot_owner ON studio_slots(owner_email, slot_start);

-- ── coach self-booking to a slot (owner approves) ──────────────────────
CREATE TABLE IF NOT EXISTS studio_coach_bookings (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slot_id bigint NOT NULL REFERENCES studio_slots(id) ON DELETE CASCADE,
  owner_email text NOT NULL,
  coach_email text NOT NULL,
  status text NOT NULL DEFAULT 'pending',      -- pending | approved | rejected
  created_at timestamptz DEFAULT now(),
  UNIQUE(slot_id, coach_email)
);

-- ── client booking to a slot (punch card) ──────────────────────────────
CREATE TABLE IF NOT EXISTS studio_bookings (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slot_id bigint NOT NULL REFERENCES studio_slots(id) ON DELETE CASCADE,
  owner_email text NOT NULL,
  client_email text NOT NULL,
  coach_email text,                            -- coach the client trains with
  workout text,                                -- assigned workout (owner sets, up to 15h before)
  status text NOT NULL DEFAULT 'booked',       -- booked | cancelled | completed
  punched boolean NOT NULL DEFAULT false,
  credited boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  cancelled_at timestamptz,
  UNIQUE(slot_id, client_email)
);
CREATE INDEX IF NOT EXISTS idx_sbook_owner ON studio_bookings(owner_email, slot_id);
CREATE INDEX IF NOT EXISTS idx_sbook_client ON studio_bookings(client_email);

-- ── punch ledger (audit for deduct/credit/manual) ──────────────────────
CREATE TABLE IF NOT EXISTS studio_punch_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  client_email text NOT NULL,
  booking_id bigint,
  delta int NOT NULL,                          -- -1 punch, +1 credit, or manual
  reason text,
  by_email text,
  created_at timestamptz DEFAULT now()
);

-- ══ RLS ══
ALTER TABLE studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_dlc ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_coaches ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_coach_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_punch_log ENABLE ROW LEVEL SECURITY;

-- studios: owner + its coaches read; owner + admin write
DROP POLICY IF EXISTS st_sel ON studios;
CREATE POLICY st_sel ON studios FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studios.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS st_all ON studios;
CREATE POLICY st_all ON studios FOR ALL TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_dlc: owner + admin
DROP POLICY IF EXISTS sdlc_all ON studio_dlc;
CREATE POLICY sdlc_all ON studio_dlc FOR ALL TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_coaches: owner manages; the coach reads own membership; admin
DROP POLICY IF EXISTS scoach_sel ON studio_coaches;
CREATE POLICY scoach_sel ON studio_coaches FOR SELECT TO authenticated USING (
  studio_owner_email = (auth.jwt()->>'email') OR coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS scoach_all ON studio_coaches;
CREATE POLICY scoach_all ON studio_coaches FOR ALL TO authenticated
  USING (studio_owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (studio_owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_slots: owner writes; owner + studio coaches + studio clients read; admin
DROP POLICY IF EXISTS sslot_sel ON studio_slots;
CREATE POLICY sslot_sel ON studio_slots FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_slots.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR EXISTS (SELECT 1 FROM clients c WHERE c.email = (auth.jwt()->>'email') AND c.studio_owner_email = studio_slots.owner_email)
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS sslot_all ON studio_slots;
CREATE POLICY sslot_all ON studio_slots FOR ALL TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_coach_bookings: coach inserts/cancels own; owner approves/reads; admin
DROP POLICY IF EXISTS scb_sel ON studio_coach_bookings;
CREATE POLICY scb_sel ON studio_coach_bookings FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email') OR coach_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS scb_coach_ins ON studio_coach_bookings;
CREATE POLICY scb_coach_ins ON studio_coach_bookings FOR INSERT TO authenticated
  WITH CHECK (coach_email = (auth.jwt()->>'email')
    AND EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_coach_bookings.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active'));
DROP POLICY IF EXISTS scb_coach_del ON studio_coach_bookings;
CREATE POLICY scb_coach_del ON studio_coach_bookings FOR DELETE TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS scb_owner_upd ON studio_coach_bookings;
CREATE POLICY scb_owner_upd ON studio_coach_bookings FOR UPDATE TO authenticated
  USING (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_bookings: client books/cancels own; owner full; assigned/studio coach reads; admin
DROP POLICY IF EXISTS sbook_sel ON studio_bookings;
CREATE POLICY sbook_sel ON studio_bookings FOR SELECT TO authenticated USING (
  client_email = (auth.jwt()->>'email')
  OR owner_email = (auth.jwt()->>'email')
  OR coach_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = studio_bookings.owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS sbook_client_ins ON studio_bookings;
CREATE POLICY sbook_client_ins ON studio_bookings FOR INSERT TO authenticated
  WITH CHECK (client_email = (auth.jwt()->>'email')
    AND EXISTS (SELECT 1 FROM clients c WHERE c.email = (auth.jwt()->>'email') AND c.studio_owner_email = studio_bookings.owner_email));
DROP POLICY IF EXISTS sbook_upd ON studio_bookings;
CREATE POLICY sbook_upd ON studio_bookings FOR UPDATE TO authenticated
  USING (client_email = (auth.jwt()->>'email') OR owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (client_email = (auth.jwt()->>'email') OR owner_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio_punch_log: owner writes; owner + client read; admin
DROP POLICY IF EXISTS spl_sel ON studio_punch_log;
CREATE POLICY spl_sel ON studio_punch_log FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email') OR client_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS spl_ins ON studio_punch_log;
CREATE POLICY spl_ins ON studio_punch_log FOR INSERT TO authenticated
  WITH CHECK (owner_email = (auth.jwt()->>'email') OR client_email = (auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- studio coach may READ his studio's client cards
DROP POLICY IF EXISTS cl_studio_coach_sel ON clients;
CREATE POLICY cl_studio_coach_sel ON clients FOR SELECT TO authenticated USING (
  studio_owner_email IS NOT NULL AND EXISTS (
    SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email = clients.studio_owner_email AND sc.coach_email = (auth.jwt()->>'email') AND sc.status='active'));

SELECT 'studio module ready' AS r;
