-- 📋 שאלון קליטה מדף הנחיתה — הלקוח ממלא, נשמר, ונשלח למאמן כ-PDF
create table if not exists public.intake_forms (
  id          bigint generated always as identity primary key,
  full_name   text not null,
  phone       text,
  email       text,
  answers     jsonb not null default '{}'::jsonb,   -- כל 22 התשובות
  pdf_url     text,
  created_at  timestamptz not null default now()
);
create index if not exists intake_forms_created_idx on public.intake_forms (created_at desc);

alter table public.intake_forms enable row level security;

-- הכתיבה נעשית רק דרך ה-Edge Function (service_role) — לא ישירות מהדפדפן
drop policy if exists "admin reads intake" on public.intake_forms;
create policy "admin reads intake" on public.intake_forms
  for select using (
    (auth.jwt() ->> 'email') = 'halel1201@gmail.com'
    or exists (select 1 from public.coaches c where c.email = (auth.jwt() ->> 'email') and c.role in ('admin','senior'))
  );
