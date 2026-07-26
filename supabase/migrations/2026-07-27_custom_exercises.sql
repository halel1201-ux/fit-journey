-- 🎬 admin-managed exercise library additions (video + cues), merged into the app library
create table if not exists public.custom_exercises (
  id           bigint generated always as identity primary key,
  name         text not null,
  muscle_group text,
  video_url    text,
  cues         text,
  created_at   timestamptz not null default now()
);
alter table public.custom_exercises enable row level security;

-- everyone signed-in can read (coach + client load the library)
drop policy if exists "anyone reads custom exercises" on public.custom_exercises;
create policy "anyone reads custom exercises" on public.custom_exercises
  for select using (true);

-- only admin can add/edit/remove
drop policy if exists "admin writes custom exercises" on public.custom_exercises;
create policy "admin writes custom exercises" on public.custom_exercises
  for all
  using      ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email = (auth.jwt() ->> 'email') and c.role = 'admin') )
  with check ( (auth.jwt() ->> 'email') = 'halel1201@gmail.com' or exists (select 1 from public.coaches c where c.email = (auth.jwt() ->> 'email') and c.role = 'admin') );
