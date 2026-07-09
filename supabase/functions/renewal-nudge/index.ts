/**
 * renewal-nudge — Fit Journey proactive retention
 * Runs daily via pg_cron. Nudges clients (and alerts their coach) BEFORE they
 * churn, in two cases:
 *   1. Coaching period ending within 7 days (coaching_end soon).
 *   2. Studio punch card running low (sessions_remaining <= 2).
 * Idempotent per window via clients.renewal_nudge_end / renewal_nudge_card so we
 * never spam the same client twice for the same expiry.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY')!
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const WINDOW_DAYS = 7   // "ending soon" horizon for the coaching period
const LOW_CARD    = 2   // punch card at/under this triggers a nudge

Deno.serve(async (req) => {
  if (req.headers.get('Authorization') !== `Bearer ${SERVICE_KEY}`) {
    return new Response('Unauthorized', { status: 401 })
  }
  try {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jerusalem' }) // YYYY-MM-DD
    const horizon = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Jerusalem' }))
    horizon.setDate(horizon.getDate() + WINDOW_DAYS)
    const horizonStr = horizon.toISOString().slice(0, 10)

    let periodNudges = 0, cardNudges = 0, cardResets = 0

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
      await sb.from('messages').insert({
        coach_email: c.coach_email, client_email: c.email, sender_email: c.coach_email,
        content: `⏳ הליווי שלך מסתיים בעוד ${daysLeft} ימים (${new Date(c.coaching_end + 'T12:00:00').toLocaleDateString('he-IL')}). בוא נשמור על המומנטום — דבר איתי לחידוש ונמשיך חזק 💪`,
      })
      await sb.from('coach_notifications').insert({
        coach_email: c.coach_email, client_email: c.email, client_name: c.name || c.email.split('@')[0], read: false,
        data: { kind: 'renewal_due', reason: 'period', days_left: daysLeft, coaching_end: c.coaching_end },
      }).select().maybeSingle().then(() => {}, () => {})
      await sb.from('clients').update({ renewal_nudge_end: c.coaching_end }).eq('email', c.email)
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
      cardNudges++
    }

    // ── 3. Reset the card marker for anyone who topped back up (renewed) ─────
    const { data: recovered } = await sb.from('clients')
      .select('email').eq('renewal_nudge_card', true).gt('sessions_remaining', LOW_CARD)
    for (const c of recovered || []) {
      await sb.from('clients').update({ renewal_nudge_card: false }).eq('email', c.email)
      cardResets++
    }

    return new Response(`ok — period ${periodNudges}, card ${cardNudges}, resets ${cardResets}`, { status: 200 })
  } catch (e) {
    return new Response('error: ' + (e as Error).message, { status: 500 })
  }
})
