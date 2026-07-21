-- exercise notes v2: note kinds (note/target/pr/pain), target completion, coach reply
alter table public.exercise_notes
  add column if not exists kind           text not null default 'note',
  add column if not exists done           boolean not null default false,
  add column if not exists coach_reply    text,
  add column if not exists coach_reply_at timestamptz;

-- coach/studio-owner may UPDATE their clients' notes (used only to add a reply)
drop policy if exists "coach replies clients ex-notes" on public.exercise_notes;
create policy "coach replies clients ex-notes" on public.exercise_notes
  for update
  using      ( exists (select 1 from public.clients c where c.email = exercise_notes.client_email and ( c.coach_email = (auth.jwt() ->> 'email') or c.studio_owner_email = (auth.jwt() ->> 'email') )) )
  with check ( exists (select 1 from public.clients c where c.email = exercise_notes.client_email and ( c.coach_email = (auth.jwt() ->> 'email') or c.studio_owner_email = (auth.jwt() ->> 'email') )) );
