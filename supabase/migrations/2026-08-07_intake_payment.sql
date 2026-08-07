-- 💳 שאלון קליטה — אימות תשלום ידני + חלון החזר כספי
-- מדיניות: ניתן לקבל החזר מלא עד הרגע שבו המאמן מתחיל לעבוד על התוכנית והתפריט.
alter table public.intake_forms
  add column if not exists payment_status    text not null default 'pending',  -- pending | verified | refunded
  add column if not exists payment_ref       text,          -- אסמכתא / 4 ספרות אחרונות
  add column if not exists payment_amount    numeric(10,2),
  add column if not exists payment_proof_url text,          -- צילום מסך של האישור
  add column if not exists plan_label        text,          -- המסלול שנבחר
  add column if not exists verified_at       timestamptz,   -- המאמן אימת שהתשלום התקבל
  add column if not exists work_started_at   timestamptz,   -- מרגע זה אין החזר
  add column if not exists refunded_at       timestamptz,
  add column if not exists refund_note       text;

-- הפאנל מעדכן סטטוס (אימות / תחילת עבודה / החזר)
drop policy if exists "admin updates intake" on public.intake_forms;
create policy "admin updates intake" on public.intake_forms
  for update
  using      ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role in ('admin','senior')) )
  with check ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role in ('admin','senior')) );
