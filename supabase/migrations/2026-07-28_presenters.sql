-- 🎤 presenter (sponsor) rewards program
alter table public.coaches
  add column if not exists is_presenter            boolean not null default false,
  add column if not exists presenter_free_until     date,
  add column if not exists presenter_first_pct      numeric(6,2) not null default 0,
  add column if not exists presenter_recurring_pct  numeric(6,2) not null default 0,
  add column if not exists presenter_recurring_type text not null default 'cash';   -- 'cash' | 'tokens'

-- people a presenter brought (name + email)
create table if not exists public.presenter_referrals (
  id              bigint generated always as identity primary key,
  presenter_email text not null,
  referred_name   text,
  referred_email  text not null,
  created_at      timestamptz not null default now()
);
create index if not exists presenter_referrals_idx on public.presenter_referrals (presenter_email);

-- payments that came in from each brought person (first package / recurring month)
create table if not exists public.presenter_payments (
  id              bigint generated always as identity primary key,
  presenter_email text not null,
  referred_email  text not null,
  amount          numeric(12,2) not null,
  kind            text not null default 'recurring',   -- 'first' | 'recurring'
  pay_month       date not null default current_date,
  note            text,
  created_at      timestamptz not null default now()
);
create index if not exists presenter_payments_idx on public.presenter_payments (presenter_email, pay_month desc);

alter table public.presenter_referrals enable row level security;
alter table public.presenter_payments  enable row level security;

-- admin-only (both tables)
do $$ begin
  perform 1;
end $$;
drop policy if exists "admin presenter refs" on public.presenter_referrals;
create policy "admin presenter refs" on public.presenter_referrals for all
  using      ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role='admin') )
  with check ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role='admin') );
drop policy if exists "admin presenter pays" on public.presenter_payments;
create policy "admin presenter pays" on public.presenter_payments for all
  using      ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role='admin') )
  with check ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email=(auth.jwt() ->> 'email') and c.role='admin') );
