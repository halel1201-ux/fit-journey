/**
 * checkin-reminder — תזכורת עדכון שבועי (שקילה + תמונות + עדכון למאמן)
 *
 * שני מצבים:
 *   • cron  (Authorization: Bearer <ADMIN_DB_KEY>) — כל יום ב-06:00 UTC.
 *     שולח לכל מתאמן שיום העדכון שלו (clients.checkin_day) הוא היום,
 *     שעוד לא שלח עדכון השבוע ולא קיבל תזכורת היום.
 *   • coach (Authorization: Bearer <JWT של מאמן>, body {client_email})
 *     — כפתור "שלח תזכורת עכשיו" בכרטיס המתאמן. הבעלות נבדקת בשרת:
 *     המאמן הרשום, סגן שהמתאמן הוצמד אליו, או הבעלים.
 *
 * מי שאין לו מנוי push מקבל את אותה תזכורת כהודעת צ'אט.
 * ?dry=1 (במצב cron) — מחשב ומחזיר את התוכנית בלי לשלוח ובלי לכתוב.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const ANON_KEY     = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9'   // מפתח ציבורי, לא סוד
const OWNER        = 'halel1201@gmail.com'
const ONESIGNAL_APP_ID = 'fe16a494-b8de-47e9-8a29-de052e048ec8'           // מזהה ציבורי, לא סוד
const ONESIGNAL_KEY    = Deno.env.get('ONESIGNAL_REST_KEY') || ''

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o, null, 2), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

const TITLE = '⚖️ הגיע הזמן לעדכון השבועי'
const BODY  = 'שקילה, תמונות ועדכון קצר למאמן — לוקח דקה.'

/* היום לפי שעון ישראל, ויום שני של אותו שבוע — אותו מפתח שבוע
   שהצ'ק-אין בדשבורד משתמש בו (getMonday), כדי ש"כבר שלח השבוע"
   יתאים בדיוק למה שהמתאמן רואה */
function israelToday(): { ymd: string; dow: number; monday: string } {
  const ymd = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' })
  const d = new Date(ymd + 'T12:00:00Z')
  const dow = d.getUTCDay()
  const m = new Date(d); m.setUTCDate(d.getUTCDate() - ((dow + 6) % 7))
  return { ymd, dow, monday: m.toISOString().slice(0, 10) }
}

async function sendPush(email: string): Promise<boolean> {
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
        headings: { he: TITLE, en: TITLE },
        contents: { he: BODY, en: BODY },
        web_url: 'https://fitjourney-net.com/dashboard.html?go=checkin',
      }),
    })
    return res.ok
  } catch { return false }
}

/* push, ואם אין — הודעת צ'אט מהמאמן. מחזיר איך נשלח. */
async function remind(c: { email: string; coach_email: string }, today: string): Promise<'push' | 'chat'> {
  const pushed = await sendPush(c.email)
  if (!pushed) {
    await sb.from('messages').insert({
      coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email,
      content: `${TITLE} — ${BODY} אפשר לשלוח מתוך האפליקציה: קהילה ← צ'ק-אין שבועי.`,
    })
  }
  await sb.from('clients').update({ checkin_push_at: today }).eq('email', c.email)
  return pushed ? 'push' : 'chat'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const auth = req.headers.get('Authorization') || ''
  const t = israelToday()

  try {
    // ── מצב cron ──────────────────────────────────────────────────────────
    if (auth === `Bearer ${SERVICE_KEY}`) {
      const dry = new URL(req.url).searchParams.get('dry') === '1'
      const { data: due } = await sb.from('clients')
        .select('email,coach_email,client_type,coaching_end,frozen_until,checkin_push_at')
        .eq('checkin_day', t.dow)
        .gte('coaching_end', t.ymd)
      const plan: Record<string, unknown>[] = []
      let sent = 0
      for (const c of due || []) {
        if (c.client_type === 'freelancer') continue                 // אין מאמן שיקבל את העדכון
        if (c.frozen_until && c.frozen_until >= t.ymd) continue      // מוקפא — לא מציקים
        if (c.checkin_push_at === t.ymd) continue                    // כבר קיבל היום
        const { data: done } = await sb.from('checkins').select('id')
          .eq('client_email', c.email).eq('week_date', t.monday).maybeSingle()
        if (done) { plan.push({ email: c.email, skip: 'already sent this week' }); continue }
        if (dry) { plan.push({ email: c.email, would: 'remind' }); continue }
        plan.push({ email: c.email, via: await remind(c, t.ymd) })
        sent++
      }
      const summary = `ok — dow ${t.dow}, due ${(due || []).length}, sent ${sent}` +
        (ONESIGNAL_KEY ? '' : ' · NO ONESIGNAL KEY')
      return dry ? json({ dry: true, today: t.ymd, summary, plan }) : new Response(summary)
    }

    // ── מצב מאמן: "שלח תזכורת עכשיו" ─────────────────────────────────────
    const token = auth.replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'לא מזוהה' }, 401)
    const { data: { user }, error } = await createClient(SUPABASE_URL, ANON_KEY).auth.getUser(token)
    if (error || !user?.email) return json({ error: 'לא מזוהה' }, 401)
    const caller = user.email

    const body = await req.json().catch(() => ({}))
    const clientEmail = String(body.client_email || '').trim().toLowerCase()
    if (!clientEmail) return json({ error: 'חסר מתאמן' }, 400)

    const { data: c } = await sb.from('clients')
      .select('email,coach_email,checkin_push_at').eq('email', clientEmail).maybeSingle()
    if (!c) return json({ error: 'המתאמן לא נמצא' }, 404)

    let allowed = caller === OWNER || caller === c.coach_email
    if (!allowed) {
      const { data: dep } = await sb.from('client_deputies').select('deputy_email')
        .eq('client_email', clientEmail).eq('deputy_email', caller).maybeSingle()
      allowed = !!dep
    }
    if (!allowed) return json({ error: 'אין הרשאה למתאמן הזה' }, 403)

    if (c.checkin_push_at === t.ymd) return json({ ok: false, reason: 'already_today' })
    const via = await remind(c, t.ymd)
    return json({ ok: true, via })
  } catch (e) {
    return json({ error: (e as Error).message }, 500)
  }
})
