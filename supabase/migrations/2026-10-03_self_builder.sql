-- ══ עורך עצמי למתאמן עצמאי (coach.html?self=1) ══
-- אדיטיבי בלבד: טבלת יומן חדשה, שתי פעולות חדשות, ו-spend_tokens
-- באותה התנהגות בדיוק — רק עם שורת יומן נוספת בענף של העצמאי.

-- ── יומן ניכויים של מתאמן עצמאי ──
-- הסוכן נכשל לפעמים (תשובה לא תקינה, ניתוק). אצל מאמן הטוקנים חוזרים;
-- לעצמאי לא היה יומן, ולכן גם לא הייתה דרך בטוחה להחזיר — כל החזר
-- "לפי סכום" היה מאפשר לייצר טוקנים יש מאין. כאן כל ניכוי נרשם,
-- והחזר מותר רק לניכוי אמיתי, פעם אחת, ובחלון קצר.
CREATE TABLE IF NOT EXISTS client_token_spends (
  id           bigserial PRIMARY KEY,
  client_email text        NOT NULL,
  amount       int         NOT NULL CHECK (amount > 0),
  kind         text,
  label        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  refunded_at  timestamptz
);
CREATE INDEX IF NOT EXISTS idx_cts_client ON client_token_spends (client_email, created_at DESC);
ALTER TABLE client_token_spends ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cts_read ON client_token_spends;
CREATE POLICY cts_read ON client_token_spends FOR SELECT
  USING (client_email = (auth.jwt() ->> 'email') OR auth.email() = 'halel1201@gmail.com');
-- אין מדיניות כתיבה: כתיבה רק דרך הפעולות למטה (SECURITY DEFINER)
REVOKE ALL ON client_token_spends FROM anon, authenticated;
GRANT SELECT ON client_token_spends TO authenticated;
REVOKE ALL ON SEQUENCE client_token_spends_id_seq FROM anon, authenticated;


-- ── spend_tokens: זהה לקודם, ובענף העצמאי גם נרשם ביומן ──
CREATE OR REPLACE FUNCTION public.spend_tokens(p_amount integer, p_label text, p_kind text DEFAULT 'plan'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  caller text := auth.jwt()->>'email';
  v_bal  int;
  v_id   bigint;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'סכום לא תקין'; END IF;

  -- מאמן
  IF EXISTS (SELECT 1 FROM coaches WHERE email = caller) THEN
    UPDATE coach_tokens
       SET balance = balance - p_amount, updated_at = now()
     WHERE coach_email = caller AND balance >= p_amount
    RETURNING balance INTO v_bal;
    IF v_bal IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient',
        'balance', COALESCE((SELECT balance FROM coach_tokens WHERE coach_email = caller), 0));
    END IF;
    INSERT INTO token_usage (coach_email, amount, kind, label, balance_after)
    VALUES (caller, p_amount, p_kind, p_label, v_bal);
    RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'actor', 'coach');
  END IF;

  -- פרילנסר
  IF EXISTS (SELECT 1 FROM clients
              WHERE email = caller AND client_type = 'freelancer') THEN
    IF NOT freelancer_active(caller) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'expired',
        'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
    END IF;
    UPDATE clients
       SET tokens_balance = tokens_balance - p_amount
     WHERE email = caller AND COALESCE(tokens_balance, 0) >= p_amount
    RETURNING tokens_balance INTO v_bal;
    IF v_bal IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient',
        'balance', COALESCE((SELECT tokens_balance FROM clients WHERE email = caller), 0));
    END IF;
    INSERT INTO client_token_spends (client_email, amount, kind, label)
    VALUES (caller, p_amount, p_kind, p_label)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'actor', 'freelancer', 'spend_id', v_id);
  END IF;

  RAISE EXCEPTION 'אין ארנק לחשבון הזה';
END
$function$;
REVOKE ALL ON FUNCTION spend_tokens(integer, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION spend_tokens(integer, text, text) TO authenticated;


-- ── החזר על בנייה שנכשלה ──
-- רק ניכוי של הקורא עצמו, שטרם הוחזר, ובתוך 15 דקות.
CREATE OR REPLACE FUNCTION refund_own_tokens(p_spend_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  v_amt  int;
  v_bal  int;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  SELECT amount INTO v_amt FROM client_token_spends
   WHERE id = p_spend_id AND client_email = caller AND refunded_at IS NULL
     AND created_at > now() - interval '15 minutes'
   FOR UPDATE;
  IF v_amt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_refundable');
  END IF;
  UPDATE client_token_spends SET refunded_at = now() WHERE id = p_spend_id;
  UPDATE clients SET tokens_balance = COALESCE(tokens_balance, 0) + v_amt
   WHERE email = caller
  RETURNING tokens_balance INTO v_bal;
  RETURN jsonb_build_object('ok', true, 'balance', v_bal, 'refunded', v_amt);
END
$fn$;
REVOKE ALL ON FUNCTION refund_own_tokens(bigint) FROM public, anon;
GRANT EXECUTE ON FUNCTION refund_own_tokens(bigint) TO authenticated;


-- ── יעדי קלוריות לפי סוג יום, מהעורך העצמי ──
-- save_own_plan כותב רק את התפריט. היעדים יושבים בעמודה נפרדת,
-- ולכן פעולה נפרדת, עם אותם תנאים: רק השורה של הקורא, ורק בגישה בתוקף.
CREATE OR REPLACE FUNCTION save_own_day_targets(p_targets jsonb)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  caller text := auth.jwt()->>'email';
  k text; v jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'לא מזוהה'; END IF;
  IF NOT freelancer_active(caller) THEN RAISE EXCEPTION 'הגישה אינה בתוקף'; END IF;
  IF p_targets IS NOT NULL THEN
    IF jsonb_typeof(p_targets) <> 'object' THEN RAISE EXCEPTION 'יעדים לא תקינים'; END IF;
    FOR k, v IN SELECT * FROM jsonb_each(p_targets) LOOP
      IF k NOT IN ('training', 'rest', 'target') OR jsonb_typeof(v) <> 'number'
         OR (v #>> '{}')::numeric < 0 OR (v #>> '{}')::numeric > 20000 THEN
        RAISE EXCEPTION 'יעדים לא תקינים';
      END IF;
    END LOOP;
  END IF;
  UPDATE nutrition_plans SET day_targets = p_targets, updated_at = now()
   WHERE client_email = caller;
  RETURN true;
END
$fn$;
REVOKE ALL ON FUNCTION save_own_day_targets(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION save_own_day_targets(jsonb) TO authenticated;
