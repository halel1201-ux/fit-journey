-- 🔁 rename_client_email — גרסה דינמית.
-- הגרסה הקודמת החזיקה רשימה קשיחה של 15 טבלאות, ולכן כל טבלה שנוספה מאז
-- (exercise_notes, daily_steps, daily_habits, signed_documents, body_photos,
--  client_notes, studio_*, ועוד) נשארה מאחור עם המייל הישן — הנתונים התייתמו.
-- הגרסה הזו סורקת את הסכימה ומעדכנת כל טבלה שיש בה client_email/user_email,
-- כך שהיא לא תתיישן שוב כשנוסיף טבלאות.
--
-- סדר: קודם clients.email (שלושה FK עם ON UPDATE CASCADE נגררים איתו),
-- ואז שאר הטבלאות.
create or replace function public.rename_client_email(p_old text, p_new text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  if p_old is null or p_new is null or p_old = p_new then
    return;
  end if;

  -- הזהות עצמה (גורר CASCADE ל-training_plans / nutrition_plans / client_debt_transactions)
  update public.clients set email = p_new where email = p_old;

  -- כל שאר הטבלאות שמפתחות לפי המייל של המתאמן
  for r in
    select c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_name = c.table_name
       and t.table_schema = c.table_schema
     where c.table_schema = 'public'
       and t.table_type   = 'BASE TABLE'
       and c.column_name in ('client_email', 'user_email')
  loop
    execute format('update public.%I set %I = $1 where %I = $2',
                   r.table_name, r.column_name, r.column_name)
      using p_new, p_old;
  end loop;
end
$function$;

grant execute on function public.rename_client_email(text, text) to authenticated, service_role;
