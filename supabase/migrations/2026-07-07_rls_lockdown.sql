-- ═══ RLS LOCKDOWN — 2026-07-07 ═══
-- Replaces every world-open (qual=true) policy with scoped access.
-- Verified before writing: anon could READ coaches/receipts/debts/workout_logs/
-- food_logs/progress_entries/push_tokens and WRITE most of them.
-- Preserved flows: coach reads/writes HIS clients' data, client owns own data,
-- admin (halel1201@gmail.com) everything, client payment-claims, coach-signup
-- pending row, autopilot trigger (SECURITY DEFINER — unaffected), Edge Functions
-- (service key bypasses RLS entirely).
-- Helper predicates used inline:
--   own:      (auth.jwt()->>'email') = client_email
--   coach-of: EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email
--                     AND c.coach_email = (auth.jwt()->>'email'))
--   admin:    auth.email() = 'halel1201@gmail.com'

-- ── coaches ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS coaches_all ON coaches;
CREATE POLICY co_sel ON coaches FOR SELECT TO authenticated USING (true);
CREATE POLICY co_upd ON coaches FOR UPDATE TO authenticated
  USING (email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY co_ins ON coaches FOR INSERT TO authenticated
  WITH CHECK (email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY co_del ON coaches FOR DELETE TO authenticated
  USING (auth.email() = 'halel1201@gmail.com');

-- ── clients (SELECT policies already scoped — only fix INSERT/UPDATE) ────
DROP POLICY IF EXISTS coaches_can_insert_clients ON clients;
DROP POLICY IF EXISTS coaches_can_update_clients ON clients;
CREATE POLICY cl_ins ON clients FOR INSERT TO authenticated
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY cl_upd ON clients FOR UPDATE TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- ── workout_logs (client own-ALL policy already exists) ──────────────────
DROP POLICY IF EXISTS workout_logs_read_all ON workout_logs;
CREATE POLICY wl_coach_sel ON workout_logs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');

-- ── food_logs ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS fl_read ON food_logs;
DROP POLICY IF EXISTS fl_insert ON food_logs;
DROP POLICY IF EXISTS fl_delete ON food_logs;
CREATE POLICY fl_own ON food_logs FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = client_email) WITH CHECK ((auth.jwt()->>'email') = client_email);
CREATE POLICY fl_coach_sel ON food_logs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');

-- ── progress_entries (coach edits his clients' measurements → coach ALL) ──
DROP POLICY IF EXISTS service_all_progress ON progress_entries;
CREATE POLICY pe_own ON progress_entries FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = client_email) WITH CHECK ((auth.jwt()->>'email') = client_email);
CREATE POLICY pe_coach ON progress_entries FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');

-- ── receipts ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "service role full access" ON receipts;
CREATE POLICY rc_coach ON receipts FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY rc_client_sel ON receipts FOR SELECT TO authenticated
  USING (client_email = (auth.jwt()->>'email'));

-- ── client_debt_transactions (client may VIEW own + file payment claims) ──
DROP POLICY IF EXISTS "service role full access" ON client_debt_transactions;
CREATE POLICY dt_coach ON client_debt_transactions FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY dt_client_sel ON client_debt_transactions FOR SELECT TO authenticated
  USING (client_email = (auth.jwt()->>'email'));
CREATE POLICY dt_client_ins ON client_debt_transactions FOR INSERT TO authenticated
  WITH CHECK (client_email = (auth.jwt()->>'email'));

-- ── push_tokens (reads stay open to logged-in users: client pushes coach & teammates; writes own-only) ──
DROP POLICY IF EXISTS allow_all ON push_tokens;
DROP POLICY IF EXISTS read_all ON push_tokens;
CREATE POLICY pt_sel ON push_tokens FOR SELECT TO authenticated USING (true);
CREATE POLICY pt_own_ins ON push_tokens FOR INSERT TO authenticated WITH CHECK (user_email = (auth.jwt()->>'email'));
CREATE POLICY pt_own_upd ON push_tokens FOR UPDATE TO authenticated
  USING (user_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (user_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY pt_own_del ON push_tokens FOR DELETE TO authenticated
  USING (user_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- ── scheduled_messages ────────────────────────────────────────────────────
DROP POLICY IF EXISTS allow_all ON scheduled_messages;
DROP POLICY IF EXISTS read_all ON scheduled_messages;
CREATE POLICY sm_coach ON scheduled_messages FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- ── autopilot queue/logs (queue: server-only via trigger+service; logs: coach viewer) ──
DROP POLICY IF EXISTS "service role full access" ON autopilot_queue;
CREATE POLICY aq_admin ON autopilot_queue FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com') WITH CHECK (auth.email() = 'halel1201@gmail.com');
DROP POLICY IF EXISTS "service role full access" ON autopilot_logs;
CREATE POLICY al_coach_sel ON autopilot_logs FOR SELECT TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY al_admin ON autopilot_logs FOR ALL TO authenticated
  USING (auth.email() = 'halel1201@gmail.com') WITH CHECK (auth.email() = 'halel1201@gmail.com');

-- ── cycles / cycle_history / peak_week_plans ─────────────────────────────
DROP POLICY IF EXISTS service_all_cycles ON cycles;
CREATE POLICY cy_own_sel ON cycles FOR SELECT TO authenticated USING ((auth.jwt()->>'email') = client_email);
CREATE POLICY cy_coach ON cycles FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');
DROP POLICY IF EXISTS service_all_cycle_history ON cycle_history;
CREATE POLICY ch_own_sel ON cycle_history FOR SELECT TO authenticated USING ((auth.jwt()->>'email') = client_email);
CREATE POLICY ch_coach ON cycle_history FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');
DROP POLICY IF EXISTS "service role full access" ON peak_week_plans;
CREATE POLICY pw_own_sel ON peak_week_plans FOR SELECT TO authenticated USING ((auth.jwt()->>'email') = client_email);
CREATE POLICY pw_coach ON peak_week_plans FOR ALL TO authenticated
  USING (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email')
         OR EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');

-- ── steps ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS steps_read ON steps_logs;
DROP POLICY IF EXISTS steps_insert ON steps_logs;
DROP POLICY IF EXISTS steps_update ON steps_logs;
DROP POLICY IF EXISTS steps_delete ON steps_logs;
CREATE POLICY sl_own ON steps_logs FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = client_email OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK ((auth.jwt()->>'email') = client_email OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY sl_coach_sel ON steps_logs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email')));
DROP POLICY IF EXISTS ds_read_team ON daily_steps;
CREATE POLICY ds_coach_sel ON daily_steps FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clients c WHERE c.email = client_email AND c.coach_email = (auth.jwt()->>'email'))
         OR auth.email() = 'halel1201@gmail.com');

-- ── coach_sales (checkout inserts; coach/admin read+update own) ──────────
DROP POLICY IF EXISTS read_all ON coach_sales;
DROP POLICY IF EXISTS insert_all ON coach_sales;
DROP POLICY IF EXISTS update_all ON coach_sales;
CREATE POLICY cs_ins ON coach_sales FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY cs_sel ON coach_sales FOR SELECT TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR client_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');
CREATE POLICY cs_upd ON coach_sales FOR UPDATE TO authenticated
  USING (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com')
  WITH CHECK (coach_email = (auth.jwt()->>'email') OR auth.email() = 'halel1201@gmail.com');

-- ── shared content: reads stay public-in-app, writes now require login ────
DROP POLICY IF EXISTS fi_insert ON food_items;  DROP POLICY IF EXISTS fi_update ON food_items;  DROP POLICY IF EXISTS fi_delete ON food_items;
CREATE POLICY fi_write ON food_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS recipes_all ON recipes; DROP POLICY IF EXISTS recipes_insert ON recipes; DROP POLICY IF EXISTS recipes_update ON recipes; DROP POLICY IF EXISTS recipes_delete ON recipes;
CREATE POLICY rec_write ON recipes FOR ALL TO authenticated USING (true) WITH CHECK (true);
