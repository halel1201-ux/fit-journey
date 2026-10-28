/**
 * push-send — שליחת התראות push מהשרת בלבד.
 *
 * עד עכשיו הדפדפן קרא ל-OneSignal ישירות עם מפתח ה-REST, ולכן המפתח
 * היה גלוי בקוד הדף וכל אחד יכול היה לשלוח התראה לכל משתמש באפליקציה.
 * כאן המפתח נשאר בשרת, והשרת בודק שמותר לשולח להגיע לכל נמען:
 *   • מאמן → המתאמנים שלו
 *   • סגן → המתאמנים שהוצמדו אליו, כל עוד הבכיר לא השבית אותו
 *   • מתאמן → המאמן שלו, והסגן שהוצמד אליו
 *   • קבוצה → כל המתאמנים של המאמן. שולחים רק המאמן עצמו, סגן פעיל שלו או הבעלים
 *   • הבעלים → כל אחד
 * הנמענים מגיעים כמיילים והטוקנים נשלפים כאן, כך שהדפדפן כבר לא צריך
 * לקרוא את push_tokens של אחרים.
 *
 * body: { to?: string[], group?: string, title: string, body: string }
 * הגבלת קצב: PER_MINUTE קריאות לדקה לכל שולח (push_send_log).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const ANON_KEY     = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9'   // מפתח ציבורי, לא סוד
const OWNER        = 'halel1201@gmail.com'
const ONESIGNAL_APP_ID = 'fe16a494-b8de-47e9-8a29-de052e048ec8'           // מזהה ציבורי, לא סוד
const ONESIGNAL_KEY    = Deno.env.get('ONESIGNAL_REST_KEY') || ''

const PER_MINUTE = 30    // קריאות לדקה לשולח. מאמן פעיל במיוחד שולח אולי 5-10
const MAX_TO     = 500   // נמענים מפורשים בקריאה אחת ("לכל המתאמנים" של מאמן גדול)
const CHUNK      = 100   // גודל רשימת .in() — רשימה ארוכה מדי מפילה את ה-URL

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

const clip = (s: unknown, n: number) => String(s ?? '').trim().slice(0, n)

function chunks<T>(a: T[], n = CHUNK): T[][] {
  const out: T[][] = []
  for (let i = 0; i < a.length; i += n) out.push(a.slice(i, i + n))
  return out
}

/* הבכירים שהשולח משמש אצלם כסגן פעיל */
async function seniorsOf(deputy: string): Promise<Set<string>> {
  const { data } = await sb.from('coach_deputies').select('senior_email')
    .eq('deputy_email', deputy).eq('active', true)
  return new Set((data || []).map(r => r.senior_email))
}

/* מי מהנמענים מותר לשולח. מחזיר רק את המותרים, בלי לחשוף למה האחרים נפלו.
   כל שאילתה כאן נשלפת לפי השולח ולא לפי רשימת הנמענים, כך שרשימה ארוכה
   לא מנפחת את ה-URL. */
async function allowedRecipients(me: string, to: string[]): Promise<string[]> {
  if (me === OWNER) return to
  const ok = new Set<string>()

  // אני המאמן שלהם
  const { data: mine } = await sb.from('clients').select('email').eq('coach_email', me)
  ;(mine || []).forEach(r => ok.add(r.email))

  // אני סגן שהם הוצמדו אליו
  const { data: dep } = await sb.from('client_deputies').select('client_email,senior_email')
    .eq('deputy_email', me)
  if (dep?.length) {
    const seniors = await seniorsOf(me)
    dep.forEach(r => { if (seniors.has(r.senior_email)) ok.add(r.client_email) })
  }

  // אני מתאמן: המאמן שלי, והסגן שהוצמד אליי
  const { data: meRow } = await sb.from('clients').select('coach_email').eq('email', me).maybeSingle()
  if (meRow?.coach_email) ok.add(meRow.coach_email)
  const { data: myDeps } = await sb.from('client_deputies').select('deputy_email,senior_email')
    .eq('client_email', me)
  for (const r of myDeps || []) {
    if (!to.includes(r.deputy_email)) continue
    const { data: act } = await sb.from('coach_deputies').select('id')
      .eq('deputy_email', r.deputy_email).eq('senior_email', r.senior_email).eq('active', true).limit(1)
    if (act?.length) ok.add(r.deputy_email)
  }

  return to.filter(e => ok.has(e))
}

/* כל המתאמנים של הקבוצה, או null כשאסור לשולח לכתוב אליה */
async function groupRecipients(me: string, group: string): Promise<string[] | null> {
  let allowed = me === OWNER || me === group
  if (!allowed) allowed = (await seniorsOf(me)).has(group)
  if (!allowed) return null
  const { data } = await sb.from('clients').select('email').eq('coach_email', group)
  return (data || []).map(r => r.email).filter(e => e !== me)
}

async function overLimit(me: string): Promise<boolean> {
  const since = new Date(Date.now() - 60_000).toISOString()
  const { count } = await sb.from('push_send_log').select('id', { count: 'exact', head: true })
    .eq('sender_email', me).gte('created_at', since)
  return (count || 0) >= PER_MINUTE
}

async function deviceIds(emails: string[]): Promise<string[]> {
  const ids = new Set<string>()
  for (const part of chunks(emails)) {
    const { data } = await sb.from('push_tokens').select('onesignal_player_id').in('user_email', part)
    ;(data || []).forEach(t => { if (t.onesignal_player_id) ids.add(t.onesignal_player_id) })
  }
  return [...ids]
}

async function deliver(ids: string[], title: string, body: string): Promise<number> {
  let sent = 0
  for (const part of chunks(ids, 2000)) {
    try {
      const res = await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Key ${ONESIGNAL_KEY}` },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          include_subscription_ids: part,
          headings: { he: title, en: title },
          contents: { he: body, en: body },
        }),
      })
      if (res.ok) sent += part.length
      else console.warn('onesignal', res.status, (await res.text()).slice(0, 200))
    } catch (e) { console.warn('onesignal', (e as Error).message) }
  }
  return sent
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'POST בלבד' }, 405)

  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'לא מזוהה' }, 401)
    const { data: { user }, error } = await createClient(SUPABASE_URL, ANON_KEY).auth.getUser(token)
    if (error || !user?.email) return json({ error: 'לא מזוהה' }, 401)
    const me = user.email

    const b = await req.json().catch(() => ({}))
    const title = clip(b.title, 80)
    const body  = clip(b.body, 240)
    if (!title || !body) return json({ error: 'חסרים כותרת או תוכן' }, 400)

    const to = Array.isArray(b.to)
      ? [...new Set(b.to.map((e: unknown) => clip(e, 254)).filter((e: string) => e && e !== me))] as string[]
      : []
    const group = b.group ? clip(b.group, 254) : ''
    if (!to.length && !group) return json({ ok: true, sent: 0 })
    if (to.length > MAX_TO) return json({ error: 'יותר מדי נמענים' }, 400)

    if (await overLimit(me)) return json({ error: 'יותר מדי התראות בדקה' }, 429)

    let recipients: string[] = []
    if (group) {
      const g = await groupRecipients(me, group)
      if (!g) return json({ error: 'אין הרשאה לקבוצה הזאת' }, 403)
      recipients = g
    } else {
      recipients = await allowedRecipients(me, to)
      if (!recipients.length) return json({ error: 'אין הרשאה לנמענים האלה' }, 403)
    }

    const ids = ONESIGNAL_KEY ? await deviceIds(recipients) : []
    const sent = ids.length ? await deliver(ids, title, body) : 0

    await sb.from('push_send_log').insert({ sender_email: me, recipients: recipients.length, sent })
    if (Math.random() < 0.02)   // ניקוי מדי פעם, בלי cron נפרד
      await sb.from('push_send_log').delete().lt('created_at', new Date(Date.now() - 7 * 864e5).toISOString())

    return json({ ok: true, recipients: recipients.length, devices: ids.length, sent,
      ...(ONESIGNAL_KEY ? {} : { warn: 'NO ONESIGNAL KEY' }) })
  } catch (e) {
    return json({ error: (e as Error).message }, 500)
  }
})
