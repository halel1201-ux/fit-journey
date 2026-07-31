-- 🗑 מחיקת חשבון מתאמן — נדרש ע"י App Store guideline 5.1.1(v):
-- אפליקציה שמאפשרת יצירת חשבון חייבת לאפשר גם למחוק אותו מתוך האפליקציה.
--
-- הפונקציה סורקת את הסכימה בזמן ריצה ומוחקת מכל טבלה שיש בה עמודה שמזהה
-- מתאמן (client_email / user_email), ולבסוף את השורה ב-clients. כך טבלה
-- חדשה שתתווסף בעתיד תיכלל אוטומטית בלי לעדכן את הקוד כאן.
--
-- security definer — רצה בהרשאות הבעלים כדי לעקוף RLS. ההרשאה מוענקת
-- ל-service_role בלבד, כלומר רק דרך Edge Function שמאמתת מי הקורא.

create or replace function public.delete_client_data(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r        record;
  n        bigint;
  deleted  jsonb := '{}'::jsonb;
begin
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'p_email is required';
  end if;

  for r in
    select c.table_name, c.column_name
    from   information_schema.columns c
    join   information_schema.tables  t
           on t.table_schema = c.table_schema
          and t.table_name   = c.table_name
    where  c.table_schema = 'public'
      and  c.column_name in ('client_email', 'user_email')
      and  t.table_type   = 'BASE TABLE'
      and  c.table_name <> 'clients'
  loop
    execute format('delete from public.%I where %I = $1', r.table_name, r.column_name)
      using p_email;
    get diagnostics n = row_count;
    if n > 0 then
      deleted := deleted || jsonb_build_object(r.table_name, n);
    end if;
  end loop;

  -- the account row itself, last
  delete from public.clients where email = p_email;
  get diagnostics n = row_count;
  deleted := deleted || jsonb_build_object('clients', n);

  return deleted;
end;
$$;

-- לא חשוף למשתמשים מחוברים או אנונימיים — רק ה-Edge Function (service_role)
-- רשאית לקרוא לה, והיא זו שמוודאת שמוחקים את החשבון של הקורא עצמו.
revoke all on function public.delete_client_data(text) from public, anon, authenticated;
grant execute on function public.delete_client_data(text) to service_role;
