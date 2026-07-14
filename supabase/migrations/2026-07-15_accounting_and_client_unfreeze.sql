-- ═══════════════════════════════════════════════════════════════
--  2026-07-15  Coach bookkeeping (expenses / P&L) + client self-unfreeze
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Coach business expenses (for the built-in profit/loss ledger) ──
create table if not exists public.coach_expenses (
  id           bigint generated always as identity primary key,
  coach_email  text not null,
  expense_date date not null default current_date,
  category     text,
  description  text,
  amount       numeric(12,2) not null check (amount >= 0),
  created_at   timestamptz not null default now()
);

create index if not exists coach_expenses_coach_date_idx
  on public.coach_expenses (coach_email, expense_date desc);

alter table public.coach_expenses enable row level security;

drop policy if exists "coach manages own expenses" on public.coach_expenses;
create policy "coach manages own expenses" on public.coach_expenses
  for all
  using      ( coach_email = (auth.jwt() ->> 'email') )
  with check ( coach_email = (auth.jwt() ->> 'email') );

-- ── 2. Client self-unfreeze cool-down ──
--  When a client thaws their own subscription they forfeit the option to
--  freeze again for the next 30 days. This column records until when a new
--  freeze is blocked (null = freezing allowed).
alter table public.clients
  add column if not exists freeze_blocked_until date;
