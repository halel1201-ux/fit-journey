/**
 * coach-alert — Fit Journey activity guard
 * A logged-in coach's browser calls this on a SEVERE activity event (scraping,
 * devtools, mass export...). We verify the JWT, take the coach identity from the
 * TOKEN (not client-supplied — unforgeable), then notify the admin: a
 * coach_notifications row (bell) + an OneSignal push. Also mirrors the event into
 * coach_activity server-side so an alert is recorded even if the client flush is
 * blocked/tampered.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY    = Deno.env.get('ADMIN_DB_KEY')!
const ANON_KEY       = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9'
const ONESIGNAL_APP_ID = 'fe16a494-b8de-47e9-8a29-de052e048ec8'
const ONESIGNAL_REST   = 'os_v2_app_7ylkjffy3zd6tcrj3ycs4beozaggpy5dukfe45efqruamrlljsrgz4rncsssvzvsbpt2df3zts2vdwcl2qg6zowamqntfmprxzppmjq'
const ADMIN_EMAIL    = 'halel1201@gmail.com'

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

const EVENT_HE: Record<string, string> = {
  rapid_access: 'גישה מהירה להרבה לקוחות (חשד לגרידה)',
  devtools: 'פתח כלי מפתחים (DevTools)',
  export: 'ייצוא/הורדת מידע',
  mass_copy: 'העתקה מרובה',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'no auth' }, 401)
    const { data: { user }, error } = await createClient(SUPABASE_URL, ANON_KEY).auth.getUser(token)
    if (error || !user?.email) return json({ error: 'unauthorized' }, 401)
    const coachEmail = user.email                 // authoritative identity from the token
    if (coachEmail === ADMIN_EMAIL) return json({ ok: true, skipped: 'admin' })

    const body = await req.json().catch(() => ({}))
    const event = String(body.event || 'alert').slice(0, 40)
    const meta = (body.meta && typeof body.meta === 'object') ? body.meta : {}
    const role = String(body.coach_role || '').slice(0, 20)

    // coach display name (best-effort)
    const { data: c } = await admin.from('coaches').select('name').eq('email', coachEmail).maybeSingle()
    const coachName = c?.name || coachEmail.split('@')[0]
    const label = EVENT_HE[event] || event

    // 1. authoritative activity row
    await admin.from('coach_activity').insert({
      coach_email: coachEmail, coach_role: role || null, event, severity: 'alert',
      meta, session_id: String(body.session_id || '').slice(0, 60), ua: (req.headers.get('user-agent') || '').slice(0, 200),
    })

    // 2. admin bell notification
    await admin.from('coach_notifications').insert({
      coach_email: ADMIN_EMAIL, client_email: coachEmail, client_name: coachName, read: false,
      data: { kind: 'coach_activity_alert', event, label, meta, coach_role: role },
    })

    // 3. push to admin
    try {
      const { data: tok } = await admin.from('push_tokens').select('onesignal_player_id').eq('user_email', ADMIN_EMAIL).maybeSingle()
      if (tok?.onesignal_player_id) {
        await fetch('https://onesignal.com/api/v1/notifications', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Key ${ONESIGNAL_REST}` },
          body: JSON.stringify({
            app_id: ONESIGNAL_APP_ID,
            include_subscription_ids: [tok.onesignal_player_id],
            headings: { he: `🛡️ התראת פעילות — ${coachName}`, en: 'Activity alert' },
            contents: { he: label, en: label },
          }),
        })
      }
    } catch (_) { /* push is best-effort */ }

    return json({ ok: true })
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500)
  }
})
