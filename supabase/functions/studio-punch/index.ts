/**
 * studio-punch — Fit Journey studio punch cards
 * Runs hourly via pg_cron. Deducts one session from a studio client's punch card
 * exactly when a booked slot enters the 24-hour window (spec: "מ-24 שעות לפני
 * האימון כבר ירד ניקוב"). Idempotent: only punches bookings that are still
 * status='booked' and punched=false.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

Deno.serve(async (req) => {
  if (req.headers.get('Authorization') !== `Bearer ${SERVICE_KEY}`) {
    return new Response('Unauthorized', { status: 401 })
  }
  try {
    const now = Date.now()
    const in24h = new Date(now + 24 * 3600 * 1000).toISOString()
    // slots starting within the next 24h (and not already past by >3h — grace)
    const from = new Date(now - 3 * 3600 * 1000).toISOString()

    const { data: slots } = await sb.from('studio_slots')
      .select('id, slot_start').gte('slot_start', from).lte('slot_start', in24h)
    if (!slots?.length) return new Response('ok — no slots in window', { status: 200 })
    const slotIds = slots.map(s => s.id)

    const { data: bookings } = await sb.from('studio_bookings')
      .select('id, owner_email, client_email').in('slot_id', slotIds).eq('status', 'booked').eq('punched', false)
    if (!bookings?.length) return new Response('ok — nothing to punch', { status: 200 })

    // today's date in Israel (freeze compares on calendar date)
    const todayIL = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' }) // YYYY-MM-DD

    let punched = 0, skippedFrozen = 0
    for (const b of bookings) {
      // ❄️ skip frozen clients — do NOT punch and leave punched=false so it re-evaluates after thaw
      const { data: cl } = await sb.from('clients').select('sessions_remaining, frozen_until').eq('email', b.client_email).maybeSingle()
      if (cl?.frozen_until && cl.frozen_until >= todayIL) { skippedFrozen++; continue }
      // mark punched first (idempotency guard against double-run)
      const { data: upd } = await sb.from('studio_bookings')
        .update({ punched: true }).eq('id', b.id).eq('punched', false).select('id').maybeSingle()
      if (!upd) continue // someone/another run already punched it
      // decrement the client's balance (floor at 0) + ledger
      const newRem = Math.max(0, (cl?.sessions_remaining || 0) - 1)
      await sb.from('clients').update({ sessions_remaining: newRem }).eq('email', b.client_email)
      await sb.from('studio_punch_log').insert({
        owner_email: b.owner_email, client_email: b.client_email, booking_id: b.id,
        delta: -1, reason: 'auto_punch_24h', by_email: 'system',
      })
      punched++
    }
    return new Response(`ok — punched ${punched}, skipped ${skippedFrozen} frozen`, { status: 200 })
  } catch (e) {
    return new Response('error: ' + (e as Error).message, { status: 500 })
  }
})
