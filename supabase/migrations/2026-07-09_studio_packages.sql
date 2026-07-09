-- studio package catalog (owner-defined) + orders (renew/start history & requests)
CREATE TABLE IF NOT EXISTS studio_packages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('sessions','period')),  -- sessions=punch card, period=coaching
  sessions int NOT NULL DEFAULT 0,     -- for kind=sessions
  months int NOT NULL DEFAULT 0,       -- for kind=period
  price int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spk_owner ON studio_packages(owner_email);

CREATE TABLE IF NOT EXISTS studio_package_orders (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_email text NOT NULL,
  client_email text NOT NULL,
  package_id bigint,
  name text, kind text, sessions int DEFAULT 0, months int DEFAULT 0, price int DEFAULT 0,
  status text NOT NULL DEFAULT 'requested',   -- requested | active | rejected
  applied boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  approved_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_spo_owner ON studio_package_orders(owner_email, status);
CREATE INDEX IF NOT EXISTS idx_spo_client ON studio_package_orders(client_email);

ALTER TABLE studio_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE studio_package_orders ENABLE ROW LEVEL SECURITY;

-- catalog: owner writes; studio clients + coaches read (to pick/renew); admin
DROP POLICY IF EXISTS spk_sel ON studio_packages;
CREATE POLICY spk_sel ON studio_packages FOR SELECT TO authenticated USING (
  owner_email = (auth.jwt()->>'email')
  OR EXISTS (SELECT 1 FROM clients c WHERE c.email=(auth.jwt()->>'email') AND c.studio_owner_email=studio_packages.owner_email)
  OR EXISTS (SELECT 1 FROM studio_coaches sc WHERE sc.studio_owner_email=studio_packages.owner_email AND sc.coach_email=(auth.jwt()->>'email') AND sc.status='active')
  OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS spk_all ON studio_packages;
CREATE POLICY spk_all ON studio_packages FOR ALL TO authenticated
  USING (owner_email=(auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email=(auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');

-- orders: owner full; client inserts own request + reads own; admin
DROP POLICY IF EXISTS spo_owner ON studio_package_orders;
CREATE POLICY spo_owner ON studio_package_orders FOR ALL TO authenticated
  USING (owner_email=(auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com')
  WITH CHECK (owner_email=(auth.jwt()->>'email') OR auth.email()='halel1201@gmail.com');
DROP POLICY IF EXISTS spo_client_ins ON studio_package_orders;
CREATE POLICY spo_client_ins ON studio_package_orders FOR INSERT TO authenticated
  WITH CHECK (client_email=(auth.jwt()->>'email') AND status='requested'
    AND EXISTS (SELECT 1 FROM clients c WHERE c.email=(auth.jwt()->>'email') AND c.studio_owner_email=studio_package_orders.owner_email));
DROP POLICY IF EXISTS spo_client_sel ON studio_package_orders;
CREATE POLICY spo_client_sel ON studio_package_orders FOR SELECT TO authenticated USING (client_email=(auth.jwt()->>'email'));

SELECT 'studio packages ready' AS r;
