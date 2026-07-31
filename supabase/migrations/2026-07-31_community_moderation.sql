-- 🛡 מודרציה לקהילה — נדרש ע"י App Store guideline 1.2 (User-Generated Content):
-- אפליקציה עם תוכן גולשים חייבת לאפשר דיווח על תוכן פוגעני, חסימת משתמשים,
-- ותנאי שימוש שאוסרים תוכן פוגעני (terms.html).

-- דיווחים על פוסטים
create table if not exists public.feed_reports (
  id              bigserial primary key,
  post_id         bigint      not null,
  reporter_email  text        not null,
  post_author     text,
  coach_email     text,
  reason          text        not null,
  status          text        not null default 'open',   -- open | reviewed | removed
  created_at      timestamptz not null default now(),
  unique (post_id, reporter_email)
);
create index if not exists idx_feed_reports_status on public.feed_reports(status, created_at desc);

alter table public.feed_reports enable row level security;

drop policy if exists "report_insert_own" on public.feed_reports;
create policy "report_insert_own" on public.feed_reports
  for insert to authenticated
  with check (auth.jwt() ->> 'email' = reporter_email);

drop policy if exists "report_read_own_or_coach" on public.feed_reports;
create policy "report_read_own_or_coach" on public.feed_reports
  for select to authenticated
  using (auth.jwt() ->> 'email' in (reporter_email, coach_email));

-- חסימת משתמשים: מי שנחסם, הפוסטים שלו לא מוצגים לחוסם
create table if not exists public.user_blocks (
  id             bigserial primary key,
  user_email     text        not null,   -- מי שחוסם
  blocked_email  text        not null,   -- מי שנחסם
  created_at     timestamptz not null default now(),
  unique (user_email, blocked_email)
);
create index if not exists idx_user_blocks_user on public.user_blocks(user_email);

alter table public.user_blocks enable row level security;

drop policy if exists "blocks_manage_own" on public.user_blocks;
create policy "blocks_manage_own" on public.user_blocks
  for all to authenticated
  using      (auth.jwt() ->> 'email' = user_email)
  with check (auth.jwt() ->> 'email' = user_email);
