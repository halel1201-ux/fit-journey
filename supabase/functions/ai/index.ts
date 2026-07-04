/**
 * AI proxy — Fit Journey
 * Keeps the Anthropic key server-side. Verifies the caller is a logged-in user,
 * then forwards the request body to Anthropic unchanged and returns the response.
 * Drop-in replacement for direct browser calls to api.anthropic.com/v1/messages.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY')!
const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!
const ANON_KEY      = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9' // publishable (public) key — independent of legacy keys

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.replace(/^Bearer\s+/i, '')
    if (!token) return new Response(JSON.stringify({ error: 'no auth' }), { status: 401, headers: { ...cors, 'content-type': 'application/json' } })

    const sb = createClient(SUPABASE_URL, ANON_KEY)
    const { data: { user }, error } = await sb.auth.getUser(token)
    if (error || !user) return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: { ...cors, 'content-type': 'application/json' } })

    const body = await req.text()
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body,
    })
    const text = await res.text()
    return new Response(text, { status: res.status, headers: { ...cors, 'content-type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'content-type': 'application/json' } })
  }
})
