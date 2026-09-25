/**
 * renewal-nudge — Fit Journey proactive retention
 * Runs daily via pg_cron (05:00 UTC — after run_auto_renewals at 03:10).
 *
 *   1. Coaching period ending within 7 days → chat message + coach bell.
 *   2. Studio punch card running low → chat message + coach bell.
 *   3. Reset the card marker for anyone who topped back up.
 *   4. Auto-renew charged a new month today and there is a balance to pay
 *      → push "חודש חדש בליווי — יתרה לתשלום X ₪".
 *   5. Period ended (no auto-renew) in the last 2 days → push
 *      "תקופת הליווי הסתיימה — כדי להמשיך, הסדר תשלום".
 *
 * Every step is idempotent via a marker column on clients, so a re-run on the
 * same day never notifies twice.
 *
 * ?dry=1 → computes everything, sends and writes nothing, returns the plan.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

/* המפתח ב-Secrets בלבד. עד 09/2026 הוא ישב קשיח בקוד של שתי פונקציות
   אחרות, בריפו ציבורי — כל אחד יכול היה לשלוח push לכל המכשירים. */
const ONESIGNAL_APP_ID = 'fe16a494-b8de-47e9-8a29-de052e048ec8'   // מזהה ציבורי, לא סוד
const ONESIGNAL_KEY    = Deno.env.get('ONESIGNAL_REST_KEY') || ''

const WINDOW_DAYS = 7   // "ending soon" horizon for the coaching period
const LOW_CARD    = 2   // punch card at/under this triggers a nudge
const ENDED_DAYS  = 2   // "just ended" window — never blast long-expired clients

function addDays(ymd: string, n: number): string {
  const d = new Date(ymd + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}
const heDate = (ymd: string) => new Date(ymd + 'T12:00:00').toLocaleDateString('he-IL')

/* push לפי מייל. מחזיר false כשאין למתאמן מנוי push או כשאין מפתח —
   ואז הקורא נופל להודעת צ'אט, כדי שאף אחד לא יפספס את העדכון. */
async function sendPush(email: string, title: string, body: string): Promise<boolean> {
  if (!ONESIGNAL_KEY) return false
  try {
    const { data: tok } = await sb.from('push_tokens')
      .select('onesignal_player_id').eq('user_email', email).maybeSingle()
    if (!tok?.onesignal_player_id) return false
    const res = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Key ${ONESIGNAL_KEY}` },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_subscription_ids: [tok.onesignal_player_id],
        headings: { he: title, en: title },
        contents: { he: body,  en: body },
        web_url: 'https://fitjourney-net.com/dashboard.html',
      }),
    })
    return res.ok
  } catch { return false }
}

async function balanceOf(email: string): Promise<number> {
  const { data } = await sb.from('client_debt_transactions')
    .select('type,amount,status').eq('client_email', email).eq('status', 'approved')
  let b = 0
  for (const t of data || []) b += t.type === 'charge' ? (+t.amount || 0) : -(+t.amount || 0)
  return Math.round(b * 100) / 100
}

Deno.serve(async (req) => {
  if (req.headers.get('Authorization') !== `Bearer ${SERVICE_KEY}`) {
    return new Response('Unauthorized', { status: 401 })
  }
  const dry = new URL(req.url).searchParams.get('dry') === '1'
  const plan: Record<string, unknown>[] = []
  try {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' }) // YYYY-MM-DD
    const horizonStr = addDays(today, WINDOW_DAYS)

    let periodNudges = 0, cardNudges = 0, cardResets = 0, chargePushes = 0, endedPushes = 0, fallbacks = 0

    // ── 1. Coaching period ending soon ──────────────────────────────────────
    const { data: ending } = await sb.from('clients')
      .select('email,name,coach_email,coaching_end,frozen_until,renewal_nudge_end,client_type')
      .not('coaching_end', 'is', null)
      .gte('coaching_end', today).lte('coaching_end', horizonStr)
    for (const c of ending || []) {
      if (c.client_type === 'studio') continue                       // studio-only clients renew via card, not period
      if (c.frozen_until && c.frozen_until >= today) continue        // frozen → paused, don't nag
      if (c.renewal_nudge_end === c.coaching_end) continue           // already nudged for this exact end date
      const daysLeft = Math.max(0, Math.round((new Date(c.coaching_end + 'T12:00:00').getTime() - new Date(today + 'T12:00:00').getTime()) / 86400000))
      /* לפרילנסר אין מאמן לדבר איתו — "דבר איתי לחידוש" היה מגיע אליו
         בשם בעל הפלטפורמה ומבטיח ליווי שאין לו */
      const content = c.client_type === 'freelancer'
        ? `⏳ הגישה למסלול העצמאי מסתיימת בעוד ${daysLeft} ימים (${heDate(c.coaching_end)}). הטוקנים שלך נשמרים גם אחרי הסיום.`
        : `⏳ הליווי שלך מסתיים בעוד ${daysLeft} ימים (${heDate(c.coaching_end)}). בוא נשמור על המומנטום — דבר איתי לחידוש ונמשיך חזק 💪`
      plan.push({ step: 'ending-soon', email: c.email, daysLeft, content })
      if (!dry) {
        await sb.from('messages').insert({
          coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email, content,
        })
        if (c.client_type !== 'freelancer') {
          await sb.from('coach_notifications').insert({
            coach_email: c.coach_email, client_email: c.email, client_name: c.name || c.email.split('@')[0], read: false,
            data: { kind: 'renewal_due', reason: 'period', days_left: daysLeft, coaching_end: c.coaching_end },
          }).select().maybeSingle().then(() => {}, () => {})
        }
        await sb.from('clients').update({ renewal_nudge_end: c.coaching_end }).eq('email', c.email)
      }
      periodNudges++
    }

    // ── 2. Punch card running low ───────────────────────────────────────────
    const { data: lowCard } = await sb.from('clients')
      .select('email,name,coach_email,sessions_remaining,frozen_until,renewal_nudge_card,client_type,studio_owner_email')
      .in('client_type', ['studio', 'both'])
      .lte('sessions_remaining', LOW_CARD)
    for (const c of lowCard || []) {
      if (c.frozen_until && c.frozen_until >= today) continue
      if (c.renewal_nudge_card) continue                             // already nudged this depletion cycle
      const rem = c.sessions_remaining || 0
      plan.push({ step: 'low-card', email: c.email, rem })
      if (!dry) {
        await sb.from('messages').insert({
          coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email,
          content: rem <= 0
            ? '🎫 נגמרה הכרטיסייה שלך. רוצה להמשיך להתאמן? אפשר לבקש חידוש חבילה מהאפליקציה ואאשר לך 🙌'
            : `🎫 נשארו לך רק ${rem} אימונים בכרטיסייה. כדאי לחדש כדי לא לעצור את הרצף — אפשר לבקש חידוש מהאפליקציה 🙌`,
        })
        await sb.from('coach_notifications').insert({
          coach_email: c.coach_email, client_email: c.email, client_name: c.name || c.email.split('@')[0], read: false,
          data: { kind: 'renewal_due', reason: 'low_card', sessions_remaining: rem },
        }).select().maybeSingle().then(() => {}, () => {})
        await sb.from('clients').update({ renewal_nudge_card: true }).eq('email', c.email)
      }
      cardNudges++
    }

    // ── 3. Reset the card marker for anyone who topped back up (renewed) ─────
    const { data: recovered } = await sb.from('clients')
      .select('email').eq('renewal_nudge_card', true).gt('sessions_remaining', LOW_CARD)
    for (const c of recovered || []) {
      if (!dry) await sb.from('clients').update({ renewal_nudge_card: false }).eq('email', c.email)
      cardResets++
    }

    // ── 4. Auto-renew charged a new month today ─────────────────────────────
    /* run_auto_renewals רץ ב-03:10 ורושם חיוב "חידוש אוטומטי" עם
       txn_date של היום. התראה נשלחת רק כשיש באמת מה לשלם — למי
       שיש לו זיכוי אין סיבה להקפיץ הודעת תשלום. */
    const { data: charges } = await sb.from('client_debt_transactions')
      .select('client_email,amount,description')
      .eq('type', 'charge').eq('status', 'approved')
      .eq('created_by', 'חידוש אוטומטי').eq('txn_date', today)
    for (const ch of charges || []) {
      const { data: c } = await sb.from('clients')
        .select('email,coach_email,charge_push_at,frozen_until').eq('email', ch.client_email).maybeSingle()
      if (!c || c.charge_push_at === today) continue
      const bal = await balanceOf(c.email)
      if (bal <= 0) { plan.push({ step: 'charge', email: c.email, skip: 'no balance', bal }); continue }
      const title = '📅 חודש חדש בליווי התחיל'
      const body  = `יתרה לתשלום: ${bal.toLocaleString('he-IL')} ₪. אפשר להסדיר מול המאמן.`
      plan.push({ step: 'charge', email: c.email, bal, title, body })
      if (!dry) {
        const pushed = await sendPush(c.email, title, body)
        if (!pushed) {
          await sb.from('messages').insert({
            coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email,
            content: `${title} 💪 ${body}`,
          })
          fallbacks++
        }
        await sb.from('clients').update({ charge_push_at: today }).eq('email', c.email)
      }
      chargePushes++
    }

    // ── 5. Period ended, not renewed ────────────────────────────────────────
    /* חלון של יומיים בלבד: בפריסה הראשונה, בלי הגבול הזה, כל מי שהליווי
       שלו נגמר לפני חודשים היה מקבל עכשיו "הליווי הסתיים". */
    const { data: ended } = await sb.from('clients')
      .select('email,name,coach_email,coaching_end,frozen_until,period_end_push,client_type,auto_renew')
      .not('coaching_end', 'is', null)
      .lt('coaching_end', today).gte('coaching_end', addDays(today, -ENDED_DAYS))
    for (const c of ended || []) {
      if (c.client_type === 'studio') continue
      if (c.frozen_until && c.frozen_until >= today) continue
      if (c.period_end_push === c.coaching_end) continue
      const fl = c.client_type === 'freelancer'
      /* לפרילנסר ההודעה אינפורמטיבית בלבד: באפליקציית iOS אסור להפנות
         לתשלום חיצוני על תוכן דיגיטלי. ליווי אישי אצל מאמן הוא שירות
         בין אנשים, ושם זה מותר. */
      const title = fl ? '🔒 הגישה למסלול העצמאי הסתיימה' : '⏳ תקופת הליווי הסתיימה'
      const body  = fl
        ? 'הטוקנים שלך נשמרים. אפשר לחדש את המסלול בכל עת.'
        : 'כדי להמשיך בליווי, הסדר את התשלום לחודש הנוכחי מול המאמן.'
      plan.push({ step: 'ended', email: c.email, coaching_end: c.coaching_end, title, body })
      if (!dry) {
        const pushed = await sendPush(c.email, title, body)
        if (!pushed && !fl) {
          await sb.from('messages').insert({
            coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email,
            content: `${title}. ${body}`,
          })
          fallbacks++
        }
        if (!fl) {
          await sb.from('coach_notifications').insert({
            coach_email: c.coach_email, client_email: c.email, client_name: c.name || c.email.split('@')[0], read: false,
            data: { kind: 'renewal_due', reason: 'period_ended', coaching_end: c.coaching_end },
          }).select().maybeSingle().then(() => {}, () => {})
        }
        await sb.from('clients').update({ period_end_push: c.coaching_end }).eq('email', c.email)
      }
      endedPushes++
    }

    const summary = `ok — period ${periodNudges}, card ${cardNudges}, resets ${cardResets}, charge ${chargePushes}, ended ${endedPushes}, chat-fallback ${fallbacks}` +
      (ONESIGNAL_KEY ? '' : ' · NO ONESIGNAL KEY')
    if (dry) return new Response(JSON.stringify({ dry: true, today, summary, plan }, null, 2),
      { status: 200, headers: { 'Content-Type': 'application/json' } })
    return new Response(summary, { status: 200 })
  } catch (e) {
    return new Response('error: ' + (e as Error).message, { status: 500 })
  }
})
