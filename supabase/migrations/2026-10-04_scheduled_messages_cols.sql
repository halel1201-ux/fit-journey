-- ══ הודעות מתוזמנות: העמודות שהקוד משתמש בהן לא היו קיימות ══
-- coach.html כותב וקורא scheduled_time ו-sent, וממיין לפי scheduled_time.
-- בטבלה הן לא היו, ולכן הטעינה החזירה 400 (כל 5 דקות, כל עוד הפאנל פתוח)
-- והשמירה נכשלה — התזמון מעולם לא עבד. הטבלה ריקה, ושום פונקציה בשרת
-- אינה קוראת ממנה. אדיטיבי בלבד.
ALTER TABLE scheduled_messages
  ADD COLUMN IF NOT EXISTS scheduled_time timestamptz,
  ADD COLUMN IF NOT EXISTS sent boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_sched_msgs_coach_time ON scheduled_messages (coach_email, scheduled_time);

-- send_time ו-days_of_week הן שאריות של עיצוב קודם: חובה וללא ברירת מחדל,
-- והקוד לא שולח אותן — ולכן גם כל שמירה נכשלה (23502). אף אחד לא קורא
-- אותן; הופכות לרשות. הטבלה ריקה, כך ששום נתון לא משתנה.
ALTER TABLE scheduled_messages ALTER COLUMN send_time DROP NOT NULL;
ALTER TABLE scheduled_messages ALTER COLUMN days_of_week DROP NOT NULL;
