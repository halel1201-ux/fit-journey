-- סוג רשומת מדידה: שקילה ביתית (משקל, ואחוז שומן משוער מתמונות אם המאמן הכניס) או פגישה (משקל + היקפים)
-- רשומות ישנות נשארות NULL: הדוח מסיק "פגישה" אם יש היקפים באותו תאריך, אחרת "שקילה ביתית".
ALTER TABLE progress_entries ADD COLUMN IF NOT EXISTS entry_type text;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'progress_entries_entry_type_chk') THEN
    ALTER TABLE progress_entries ADD CONSTRAINT progress_entries_entry_type_chk CHECK (entry_type IS NULL OR entry_type IN ('home', 'meeting'));
  END IF;
END $$;
COMMENT ON COLUMN progress_entries.entry_type IS 'home = שקילה ביתית · meeting = פגישה (משקל + היקפים, ההיקפים ב-body_measurements באותו תאריך) · NULL = רשומה ישנה';
