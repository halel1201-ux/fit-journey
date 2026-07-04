/**
 * Admin auth operations — Fit Journey
 * Handles the privileged auth.admin operations that cannot be done with a user JWT.
 * Keeps the service key server-side. Authorizes each action by caller role.
 * Actions: set_password, rename_email.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const ANON_KEY     = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9' // publishable (public) key — independent of legacy keys
const ADMIN_KEY    = Deno.env.get('ADMIN_DB_KEY')!
const ADMIN_EMAIL  = 'halel1201@gmail.com'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...cors, 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'no auth' }, 401)

    const authClient = createClient(SUPABASE_URL, ANON_KEY)
    const { data: { user }, error: uErr } = await authClient.auth.getUser(token)
    if (uErr || !user) return json({ error: 'unauthorized' }, 401)

    const admin = createClient(SUPABASE_URL, ADMIN_KEY, { auth: { persistSession: false } })

    // Caller role
    const isAdmin = user.email === ADMIN_EMAIL
    let role = 'regular'
    if (!isAdmin) {
      const { data: coach } = await admin.from('coaches').select('role').eq('email', user.email).maybeSingle()
      role = coach?.role || 'regular'
    }
    const canManage = isAdmin || role === 'senior'

    const body = await req.json()
    const action = body.action

    // Helper: find an auth user by email
    async function findUser(email: string) {
      const { data } = await admin.auth.admin.listUsers({ perPage: 1000 })
      return (data?.users || []).find((u: { email?: string }) => u.email === email) || null
    }

    if (action === 'set_password') {
      if (!canManage) return json({ error: 'forbidden' }, 403)
      const { email, password } = body
      if (!email || !password || String(password).length < 6) return json({ error: 'bad input' }, 400)
      const target = await findUser(email)
      if (target) {
        const { error } = await admin.auth.admin.updateUserById(target.id, { password })
        if (error) return json({ error: error.message }, 400)
      } else {
        const { error } = await admin.auth.admin.createUser({ email, password, email_confirm: true })
        if (error) return json({ error: error.message }, 400)
      }
      return json({ ok: true })
    }

    if (action === 'rename_email') {
      const { old_email, new_email } = body
      if (!old_email || !new_email) return json({ error: 'bad input' }, 400)
      // Allowed: admin, senior coach, or a user renaming their own email
      const self = old_email === user.email
      if (!canManage && !self) return json({ error: 'forbidden' }, 403)
      const target = await findUser(old_email)
      if (target) {
        const { error } = await admin.auth.admin.updateUserById(target.id, { email: new_email, email_confirm: true })
        if (error) return json({ error: error.message }, 400)
      }
      return json({ ok: true })
    }

    return json({ error: 'unknown action' }, 400)
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
