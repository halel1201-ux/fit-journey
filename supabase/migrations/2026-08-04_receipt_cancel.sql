-- 🧾 ביטול קבלה — מסמנים כמבוטלת ולא מוחקים (חובה לשמור תיעוד לצרכי מס),
-- והיא מפסיקה להיספר בהכנסות ובמאזן הרווח/הפסד.
alter table public.receipts
  add column if not exists cancelled_at     timestamptz,
  add column if not exists cancelled_reason text;
