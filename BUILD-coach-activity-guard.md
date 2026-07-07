# תסריט בנייה: מעקב פעילות + הגנת מידע למאמנים (Coach Activity Guard)

מסמך handoff. בונים בשלבים, בדיקה + commit + push אחרי כל שלב, **בלי לשבור פיצ'ר קיים**.
מודל התחלה: Fable 5. אם עוברים מגבלת context/טוקנים — ממשיכים עם Opus 4.8 מהשלב הבא ברשימה.

## עיקרון-על (כנות טכנית)
ווב לא מונע העתקה מוחלטת. המטרה: **הרתעה + זיהוי + תיעוד + התראה לאדמין**. שכבות:
1. **Audit** — כל פעולה משמעותית של מאמן נרשמת (מי, מה, מתי).
2. **Detection** — דפוסי אקספילטרציה (פתיחת המון לקוחות/תוכניות מהר, ייצוא, DevTools, הדפסה) → אירוע חמור.
3. **Deterrence** — סימן-מים עם מייל המאמן על תצוגות רגישות, חסימת תפריט-ימני/בחירת-טקסט/העתק על מידע רגיש.
4. **Alerting** — אירוע חמור → coach_notifications לאדמין + OneSignal push.
5. **Admin view** — פיד פעילות + אירועים מסומנים ב-admin.html.

מגבלה מובנית: הטראקר רץ בדפדפן של המאמן — מאמן טכני יכול להשבית אותו. לכן **עצם ההשבתה נחשב אות** (heartbeat חסר), והמידע הרגיש ממילא כבר מוגן ב-RLS (מאמן רואה רק את הלקוחות שלו — הושלם ב-2026-07-07).

## מקורות/עובדות מאומתות
- `coaches.role` ∈ pending|regular|senior|admin. אדמין = halel1201@gmail.com.
- push: `push_tokens.onesignal_player_id`; שליחה כמו ב-autopilot (OneSignal REST).
- coach.html: `coachEmail`, `coachRole`, `sb` (publishable+RLS), `selectClient(email)`, `activeEmail`.
- admin.html: `sb`, `init()` עם watchdog, מבנה טאבים/סקשנים קיים.
- דפוס Edge Function קיים (verify_jwt:false, בדיקת bearer). פריסה: Management API multipart מתיקייה ASCII, טוקן sbp_ מקובץ.

## שלבי בנייה

### שלב 1 — DB (טבלה + RLS + התראת אדמין)
```sql
CREATE TABLE coach_activity (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email text NOT NULL,
  coach_role  text,
  event text NOT NULL,          -- 'view_client','open_plan','copy','print','devtools','export','rapid_access','tracker_start'...
  severity text NOT NULL DEFAULT 'info',  -- info | warn | alert
  meta jsonb DEFAULT '{}',
  session_id text,
  ua text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ca_coach_time ON coach_activity(coach_email, created_at DESC);
CREATE INDEX idx_ca_sev ON coach_activity(severity, created_at DESC) WHERE severity <> 'info';
ALTER TABLE coach_activity ENABLE ROW LEVEL SECURITY;
-- coach may INSERT own rows only; only admin may READ. no update/delete from browser.
CREATE POLICY caa_ins ON coach_activity FOR INSERT TO authenticated
  WITH CHECK (coach_email = (auth.jwt()->>'email'));
CREATE POLICY caa_admin_sel ON coach_activity FOR SELECT TO authenticated
  USING (auth.email() = 'halel1201@gmail.com');
```
בדיקה: anon → 401; מאמן יכול insert על עצמו, לא על אחר; רק אדמין קורא.

### שלב 2 — טראקר בצד לקוח (coach.html)
פונקציה גלובלית `caTrack(event, meta, severity)`:
- מוסיפה session_id (localStorage uuid), coach_email, coach_role, ua.
- **batching**: מצטבר במערך, flush כל 5ש או ב-`visibilitychange`/`pagehide` (navigator.sendBeacon → insert). מקטין רעש.
- אירוע `alert` נשלח **מיד** (בלי batch) + מפעיל את התראת האדמין (שלב 4).
- מפעילים על: טעינת פאנל (`tracker_start`), `selectClient` (`view_client` + client_email), פתיחת עורך תוכנית/תזונה (`open_plan`), ייצוא/הורדה/הדפסה, `copy` על אזור רגיש.
- **חשוב:** רק למאמנים (לא אדמין עצמו). לא לחסום/להאט כלום — fire-and-forget, try/catch שקט.

### שלב 3 — זיהוי + הרתעה (coach.html)
- **Rapid-access (גרידה):** חלון מתגלגל — אם `view_client`/`open_plan` > 12 ב-60ש → אירוע `rapid_access` severity=alert עם הספירה.
- **DevTools:** היוריסטיקת הפרש outerWidth-innerWidth / debugger-timing; פתיחה ראשונה → `devtools` warn (לא spam — פעם לכל session).
- **Copy/Print:** מאזין `copy` על אזורי מידע רגיש (תוכניות/פרטי לקוח) → `copy` warn עם אורך הטקסט; `beforeprint` → `print` warn.
- **Watermark:** overlay CSS קבוע (pointer-events:none, position:fixed, אלכסוני, opacity ~0.05) עם `${coachEmail} · ${timestamp}` על תצוגת מידע רגיש — צילום מסך יהיה מזוהה. ניתן לכיבוי לאדמין.
- **הרתעה קלה:** על אזורי מידע רגיש — `user-select:none` + חסימת `contextmenu` (עם רישום `context_menu` info). לא על שדות עריכה.

### שלב 4 — התראת אדמין (Edge Function `coach-alert` או ישירות)
- אופציה פשוטה (מומלץ): על אירוע `alert`, הטראקר גם כותב `coach_notifications` (coach_email=admin, data:{kind:'coach_activity_alert', event, sev, ...}) → הפעמון של האדמין כבר עובד. + קריאה ל-Edge Function דקה שתשלח OneSignal push לאדמין (שלא ניתן לזייף מהדפדפן — הפונקציה שולחת רק לאדמין).
- אלטרנטיבה: Edge Function `coach-alert` מקבל את האירוע, מאמת JWT, כותב coach_activity+notification בצד שרת (אמין יותר, לא ניתן לדילוג). אם הזמן מרשה — עדיף.

### שלב 5 — תצוגת אדמין (admin.html)
- טאב/סקשן "🛡️ פעילות מאמנים": 
  - פיד אחרון (severity color: alert אדום, warn כתום, info אפור), סינון לפי מאמן/חומרה.
  - "אירועים מסומנים" למעלה (alert/warn מ-24ש).
  - סיכום פר-מאמן: כמה צפיות, כמה אירועים חמורים, heartbeat אחרון.
- טעינה עם `.eq` server-side, RLS כבר מגביל לאדמין.

### שלב 6 — בדיקות מקצה לקצה
- unit: rapid-access window logic, batching flush.
- חי: סימולציית מאמן (JWT) שמכניס coach_activity לעצמו ✓, לא לאחר ✗, אדמין קורא ✓, anon ✗.
- אירוע alert → notification לאדמין נוצר + (אם Edge) push נשלח.
- syntax check coach.html + admin.html; רינדור ויזואלי של סקשן האדמין + הסימן-מים.
- ניקוי נתוני בדיקה.

## מלכודות ידועות (לא לחזור)
- todayStr() מקומי, לא toISOString. נתיבים יחסיים. file:// guard קיים.
- אל תריץ טראקר על אדמין (רעש). אל תחסום UI (fire-and-forget).
- sendBeacon לא נושא Authorization header → לשימוש ב-flush רגיל עם fetch+key, ו-sendBeacon רק כ-fallback ב-pagehide (או Edge Function עם bearer).
- בדיקות עברית דרך node/קבצים, לא inline shell.
- לא לשבור: selectClient, עורכים, שמירה. הטראקר נקרא בנוסף, לא במקום.

## סדר עדיפות אם נגמרים טוקנים
1→2→5 (הליבה: תיעוד + תצוגת אדמין) הם ה-MVP. 3 (זיהוי/הרתעה) ו-4 (push) הם ה-value המלא. 6 תמיד.
