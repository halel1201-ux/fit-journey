-- 🧾 פרטי העסק של המאמן — נדפסים על הקבלה לפי דרישות ניהול ספרים בישראל
alter table public.coaches
  add column if not exists biz_number  text,                      -- מספר עוסק / ח.פ. / ת.ז.
  add column if not exists biz_type    text default 'exempt',     -- 'exempt' = עוסק פטור · 'licensed' = עוסק מורשה
  add column if not exists biz_address text,
  add column if not exists biz_phone   text,
  add column if not exists vat_rate    numeric(5,2) default 18;   -- % מע"מ לעוסק מורשה

-- צילום מצב של פרטי העסק על כל קבלה — קבלה שהונפקה חייבת לשמר את מה שהודפס
-- עליה גם אם המאמן ישנה את פרטי העסק בהמשך.
alter table public.receipts
  add column if not exists biz_number  text,
  add column if not exists biz_type    text,
  add column if not exists biz_address text,
  add column if not exists biz_phone   text,
  add column if not exists vat_rate    numeric(5,2);
