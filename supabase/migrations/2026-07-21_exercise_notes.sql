-- 📝 per-exercise personal training journal (client writes, coach reads)
create table if not exists public.exercise_notes (
  id            bigint generated always as identity primary key,
  client_email  text not null,
  exercise_key  text not null,            -- trimmed exercise name (matches across sessions)
  exercise_name text,                      -- display name as written in the plan
  note          text not null,
  created_at    timestamptz not null default now()
);
create index if not exists exercise_notes_client_ex_idx
  on public.exercise_notes (client_email, exercise_key, created_at desc);

alter table public.exercise_notes enable row level security;

drop policy if exists "client manages own ex-notes" on public.exercise_notes;
create policy "client manages own ex-notes" on public.exercise_notes
  for all
  using      ( client_email = (auth.jwt() ->> 'email') )
  with check ( client_email = (auth.jwt() ->> 'email') );

-- coach (or studio owner) can READ their own clients' notes
drop policy if exists "coach reads clients ex-notes" on public.exercise_notes;
create policy "coach reads clients ex-notes" on public.exercise_notes
  for select
  using ( exists (
    select 1 from public.clients c
    where c.email = exercise_notes.client_email
      and ( c.coach_email = (auth.jwt() ->> 'email')
         or c.studio_owner_email = (auth.jwt() ->> 'email') )
  ) );
