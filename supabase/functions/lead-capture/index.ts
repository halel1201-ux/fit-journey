/**
 * lead-capture — public endpoint for the landing-page chat.
 * A visitor leaves name + phone (+ goal); we create a lead in coach_sales for the
 * brand coach and drop a bell notification. No auth (public), input-validated,
 * lightly rate-limited by requiring a plausible name + phone.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const BRAND_COACH  = 'halelsheli@gmail.com'   // leads from the marketing site
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const body = await req.json().catch(() => ({}))
    const name = String(body.name || '').trim().slice(0, 80)
    const phone = String(body.phone || '').replace(/[^\d+\-\s]/g, '').trim().slice(0, 25)
    const note = String(body.note || '').trim().slice(0, 200)
    const digits = phone.replace(/\D/g, '')
    if (name.length < 2) return json({ error: 'שם קצר מדי' }, 400)
    if (digits.length < 9 || digits.length > 15) return json({ error: 'מספר טלפון לא תקין' }, 400)

    // de-dupe: same phone as an open lead in the last 24h → don't create again
    const dayAgo = new Date(Date.now() - 864e5).toISOString()
    const { data: existing } = await sb.from('coach_sales')
      .select('id').eq('coach_email', BRAND_COACH).eq('lead_phone', phone).eq('status', 'lead').gte('created_at', dayAgo).maybeSingle()
    if (existing) return json({ ok: true, deduped: true })

    const { error } = await sb.from('coach_sales').insert({
      coach_email: BRAND_COACH, client_email: '', client_name: name, lead_phone: phone, lead_note: note || null,
      status: 'lead', source: 'chat', plan_price: 0, plan_months: 0,
    })
    if (error) return json({ error: error.message }, 400)

    // bell for the coach
    await sb.from('coach_notifications').insert({
      coach_email: BRAND_COACH, client_email: '', client_name: name, read: false,
      data: { kind: 'new_lead', source: 'chat', phone, note },
    }).then(() => {}, () => {})

    return json({ ok: true })
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500)
  }
})
