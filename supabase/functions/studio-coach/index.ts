/**
 * studio-coach — a studio owner creates/manages his own coaches (name + password).
 * The owner cannot exceed his package coach_capacity. Identity + ownership are
 * verified from the JWT server-side; the service key does the user creation.
 * Actions: create | set_password | remove
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const ANON_KEY     = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9'
const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

async function findUser(email: string) {
  const { data } = await admin.auth.admin.listUsers({ perPage: 1000 })
  return (data?.users || []).find((u: { email?: string }) => u.email === email) || null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'no auth' }, 401)
    const { data: { user }, error } = await createClient(SUPABASE_URL, ANON_KEY).auth.getUser(token)
    if (error || !user?.email) return json({ error: 'unauthorized' }, 401)
    const owner = user.email

    // caller must be a studio owner (or admin)
    const { data: me } = await admin.from('coaches').select('role').eq('email', owner).maybeSingle()
    const isAdmin = owner === 'halel1201@gmail.com'
    if (!isAdmin && me?.role !== 'studio_owner') return json({ error: 'forbidden — studio owners only' }, 403)

    const body = await req.json().catch(() => ({}))
    const action = body.action
    const email = String(body.email || '').trim().toLowerCase()

    // ownership guard for set_password/remove: the coach must belong to THIS owner's studio
    async function ownsCoach(): Promise<boolean> {
      const { data } = await admin.from('studio_coaches').select('id').eq('studio_owner_email', owner).eq('coach_email', email).maybeSingle()
      return !!data
    }

    if (action === 'create') {
      const name = String(body.name || '').trim()
      const password = String(body.password || '')
      if (!email || !email.includes('@')) return json({ error: 'מייל לא תקין' }, 400)
      if (password.length < 6) return json({ error: 'סיסמה חייבת 6 תווים לפחות' }, 400)
      if (email === owner) return json({ error: 'אתה כבר בעל הסטודיו' }, 400)

      // capacity check (server-authoritative)
      const [{ data: studio }, { count }] = await Promise.all([
        admin.from('studios').select('coach_capacity').eq('owner_email', owner).maybeSingle(),
        admin.from('studio_coaches').select('id', { count: 'exact', head: true }).eq('studio_owner_email', owner),
      ])
      const cap = studio?.coach_capacity ?? 1
      if (!isAdmin && (count ?? 0) >= cap) return json({ error: `הגעת לתקרת המאמנים (${cap}) — הוסף חבילת מאמן` }, 403)

      // create or reuse the auth user
      let target = await findUser(email)
      if (!target) {
        const { data: created, error: cErr } = await admin.auth.admin.createUser({ email, password, email_confirm: true })
        if (cErr) return json({ error: cErr.message }, 400)
        target = created.user
      } else {
        await admin.auth.admin.updateUserById(target.id, { password })
      }
      // coaches row (regular coach) + studio link
      await admin.from('coaches').upsert({ email, name: name || email.split('@')[0], role: 'regular' }, { onConflict: 'email' })
      const { error: linkErr } = await admin.from('studio_coaches').upsert({ studio_owner_email: owner, coach_email: email, status: 'active' }, { onConflict: 'studio_owner_email,coach_email' })
      if (linkErr) return json({ error: linkErr.message }, 400)
      return json({ ok: true })
    }

    if (action === 'set_password') {
      const password = String(body.password || '')
      if (password.length < 6) return json({ error: 'סיסמה חייבת 6 תווים לפחות' }, 400)
      if (!isAdmin && !(await ownsCoach())) return json({ error: 'forbidden' }, 403)
      const target = await findUser(email)
      if (!target) return json({ error: 'המאמן לא נמצא' }, 404)
      const { error: uErr } = await admin.auth.admin.updateUserById(target.id, { password })
      if (uErr) return json({ error: uErr.message }, 400)
      return json({ ok: true })
    }

    if (action === 'remove') {
      if (!isAdmin && !(await ownsCoach())) return json({ error: 'forbidden' }, 403)
      await admin.from('studio_coaches').delete().eq('studio_owner_email', owner).eq('coach_email', email)
      return json({ ok: true })   // keeps the auth user + coaches row (coach may exist elsewhere)
    }

    return json({ error: 'unknown action' }, 400)
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500)
  }
})
