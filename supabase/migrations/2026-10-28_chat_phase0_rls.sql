-- צ'אט, שלב 0: סגירת חורים בהרשאות. מוחל יחד עם העלאת הקוד החדש של coach.html ו-dashboard.html
-- (ההתראות עוברות ל-push-send), כי הקוד הישן עדיין קורא טוקנים של אחרים מהדפדפן.

-- ── הודעות פרטיות ──
-- עד עכשיו נבדק רק שהשולח הוא מי שמחובר, ולכן כל משתמש יכול היה לכתוב לתוך כל שרשור.
-- מעכשיו השרשור (מתאמן + המאמן הרשום שלו) חייב להיות אמיתי, והשולח חייב להיות אחד מהשניים.
-- סגנים ממשיכים לעבור דרך dep_ins_messages הקיימת.
-- הפונקציה בודקת רק שרשורים של המחובר עצמו, כך שקריאה ישירה אליה לא חושפת קשרים של אחרים.
create or replace function public.is_my_thread(p_client text, p_coach text)
returns boolean language sql stable security definer set search_path = public as $$
  select (auth.jwt() ->> 'email') in (p_client, p_coach)
     and exists (select 1 from clients where email = p_client and coach_email = p_coach);
$$;
revoke all on function public.is_my_thread(text, text) from public, anon;
grant execute on function public.is_my_thread(text, text) to authenticated;

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
with check (
  sender_email = (auth.jwt() ->> 'email')
  -- תשובות AI נכתבות רק מהשרת (autopilot), לא מהדפדפן
  and coalesce(is_ai_reply, false) = false
  and (
    public.is_my_thread(client_email, coach_email)
    -- מצב עצמאי: שרשור של אדם עם עצמו
    or (coach_email = sender_email and client_email = sender_email)
  )
);

-- ── קבוצות ──
-- המדיניות הזאת אפשרה לכל משתמש לכתוב לקבוצה של כל מאמן. grp_insert ו-dep_ins_group_messages
-- כבר מכסות את מי שבאמת צריך: המאמן, המתאמנים שלו, וסגן פעיל.
drop policy if exists "clients can insert group messages" on public.group_messages;

-- ── טוקנים של התראות ──
-- כל מחובר יכול היה לקרוא את כל הטוקנים. ההתראות נשלחות עכשיו מהשרת (push-send),
-- ולכן כל משתמש רואה רק את הטוקן של עצמו (upsert_own).
drop policy if exists pt_sel on public.push_tokens;
drop policy if exists dep_sel_push_tokens on public.push_tokens;
