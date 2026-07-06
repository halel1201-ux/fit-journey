/**
 * Churn-Check Edge Function — Fit Journey
 * Runs daily via pg_cron. Deterministic risk scoring in code (no AI math);
 * Claude Haiku only writes the personalized win-back message.
 * Creates churn_alerts rows + coach_notifications (bell) for coaches.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY   = Deno.env.get('ADMIN_DB_KEY')!
const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY')!

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const CLAUDE_MODEL = 'claude-haiku-4-5-20251001'

// ── tunable scoring constants ──────────────────────────────────────────────
const MIN_TENURE_DAYS   = 7    // brand-new clients are never flagged
const COOLDOWN_DAYS     = 5    // one alert per client per N days (any status)
const ALERT_THRESHOLD   = 60
const W_SEEN_4D  = 30, W_SEEN_7D  = 50   // didn't open the app
const W_WORK_5D  = 25, W_WORK_10D = 40   // no workout logged
const W_TRACK_7D = 15                    // no weight/food update
const W_MSG_3D   = 15                    // coach's last message unanswered

const goalMap: Record<string, string> = { cut: 'חיטוב', recomp: 'ריקומפוזיציה', mass: 'מסה', peak_week: 'פייק וויק' }

const daysSince = (d: string | null): number => {
  if (!d) return 9999
  const t = new Date(d).getTime()
  if (isNaN(t)) return 9999
  return Math.floor((Date.now() - t) / 864e5)
}

interface ClientRow { email: string; name: string; coach_email: string; goal: string | null; last_seen: string | null; created_at: string; phone: string | null }

export function scoreClient(c: {
  tenureDays: number; seenDays: number; workoutDays: number; trackDays: number; unansweredDays: number;
}): { score: number; reasons: string[] } {
  if (c.tenureDays < MIN_TENURE_DAYS) return { score: 0, reasons: [] }
  let score = 0
  const reasons: string[] = []
  if (c.seenDays >= 7)      { score += W_SEEN_7D; reasons.push(`לא נכנס לאפליקציה ${c.seenDays >= 9000 ? 'מעולם' : c.seenDays + ' ימים'}`) }
  else if (c.seenDays >= 4) { score += W_SEEN_4D; reasons.push(`לא נכנס לאפליקציה ${c.seenDays} ימים`) }
  if (c.workoutDays >= 10)     { score += W_WORK_10D; reasons.push(`לא רשם אימון ${c.workoutDays >= 9000 ? 'מעולם' : c.workoutDays + ' ימים'}`) }
  else if (c.workoutDays >= 5) { score += W_WORK_5D;  reasons.push(`לא רשם אימון ${c.workoutDays} ימים`) }
  if (c.trackDays >= 7) { score += W_TRACK_7D; reasons.push(`לא עדכן משקל/אוכל ${c.trackDays >= 9000 ? 'מעולם' : c.trackDays + ' ימים'}`) }
  if (c.unansweredDays >= 3 && c.unansweredDays < 9000) { score += W_MSG_3D; reasons.push(`לא ענה להודעת המאמן ${c.unansweredDays} ימים`) }
  return { score: Math.min(score, 100), reasons }
}

async function composeMessage(coachName: string, clientName: string, goal: string | null, reasons: string[]): Promise<string> {
  const goalHeb = goal ? (goalMap[goal] ?? goal) : ''
  const fallback = `היי ${clientName}, שמתי לב שקצת נעלמת 🙂 בוא נחזור למסלול — מה מתאים לך השבוע?`
  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: CLAUDE_MODEL, max_tokens: 200,
        system: 'אתה מנסח הודעות וואטסאפ קצרות בשם מאמן כושר ללקוח שנעלם. עברית תקינה וטבעית בלבד — "בוא נ..." (לא "בואנו"), "שמתי לב" (לא "שמנתי"). 2-3 משפטים, חם ובגובה העיניים, בלי אשמה ובלי לחץ, עם הצעה קונקרטית אחת לחזרה. בלי פתיחות גנריות כמו "אני מקווה שהכל בסדר". החזר רק את ההודעה עצמה.',
        messages: [{ role: 'user', content: `המאמן: ${coachName}. הלקוח: ${clientName}${goalHeb ? ` (מטרה: ${goalHeb})` : ''}. מה שקרה: ${reasons.join('; ')}. נסח את ההודעה.` }],
      }),
    })
    if (!res.ok) return fallback
    const j = await res.json()
    const text = (j.content?.[0]?.text || '').trim()
    return text || fallback
  } catch { return fallback }
}

async function run(): Promise<string> {
  const today = new Date()
  const winStart = new Date(today.getTime() - 30 * 864e5).toISOString().slice(0, 10)
  const msgWinStart = new Date(today.getTime() - 14 * 864e5).toISOString()
  const todayStr = today.toISOString().slice(0, 10)

  // 1. active clients + their coaches (batched — no per-client queries)
  const [{ data: clients }, { data: coaches }] = await Promise.all([
    sb.from('clients').select('email,name,coach_email,goal,last_seen,created_at,phone').gte('coaching_end', todayStr),
    sb.from('coaches').select('email,name'),
  ])
  if (!clients?.length) return 'no active clients'
  const coachName: Record<string, string> = {}
  ;(coaches || []).forEach(c => { coachName[c.email] = c.name })

  const emails = clients.map(c => c.email)

  // 2. batched activity lookups (last 30d / 14d windows)
  const [{ data: workouts }, { data: foods }, { data: progress }, { data: msgs }, { data: recentAlerts }] = await Promise.all([
    sb.from('workout_logs').select('client_email,log_date').gte('log_date', winStart).in('client_email', emails),
    sb.from('food_logs').select('client_email,log_date').gte('log_date', winStart).in('client_email', emails),
    sb.from('progress_entries').select('client_email,date').gte('date', winStart).in('client_email', emails),
    sb.from('messages').select('client_email,sender_email,created_at').gte('created_at', msgWinStart).in('client_email', emails).order('created_at', { ascending: true }),
    sb.from('churn_alerts').select('client_email,created_at').gte('created_at', new Date(today.getTime() - COOLDOWN_DAYS * 864e5).toISOString()),
  ])

  const lastOf: Record<string, Record<string, string>> = { w: {}, f: {}, p: {} }
  ;(workouts || []).forEach(r => { if (!lastOf.w[r.client_email] || r.log_date > lastOf.w[r.client_email]) lastOf.w[r.client_email] = r.log_date })
  ;(foods || []).forEach(r => { if (!lastOf.f[r.client_email] || r.log_date > lastOf.f[r.client_email]) lastOf.f[r.client_email] = r.log_date })
  ;(progress || []).forEach(r => { if (!lastOf.p[r.client_email] || r.date > lastOf.p[r.client_email]) lastOf.p[r.client_email] = r.date })

  // last message per client thread + whether coach is awaiting reply
  const lastMsg: Record<string, { sender: string; at: string }> = {}
  ;(msgs || []).forEach(m => { lastMsg[m.client_email] = { sender: m.sender_email, at: m.created_at } })

  const onCooldown = new Set((recentAlerts || []).map(a => a.client_email))

  let created = 0
  const flagged: string[] = []

  const validEmail = /^[^@\s]+@[^@\s]+\.[^@\s]+$/
  for (const c of clients as ClientRow[]) {
    if (!c.email || !validEmail.test(c.email)) continue // junk rows (e.g. '@')
    if (onCooldown.has(c.email)) continue
    if (c.email === c.coach_email) continue // self-coached — skip

    const tenureDays = daysSince(c.created_at)
    const seenDays = c.last_seen ? daysSince(c.last_seen) : tenureDays
    const workoutDays = daysSince(lastOf.w[c.email] ?? null)
    const trackDays = Math.min(daysSince(lastOf.f[c.email] ?? null), daysSince(lastOf.p[c.email] ?? null))
    const lm = lastMsg[c.email]
    const unansweredDays = lm && lm.sender === c.coach_email ? daysSince(lm.at) : 9999
    // never-logged clients: cap "never" per-signal at tenure so a quiet-but-new client isn't over-penalized
    const cap = (v: number) => Math.min(v, tenureDays)

    const { score, reasons } = scoreClient({
      tenureDays,
      seenDays: cap(seenDays),
      workoutDays: cap(workoutDays),
      trackDays: cap(trackDays),
      unansweredDays: unansweredDays >= 9000 ? unansweredDays : unansweredDays,
    })
    if (score < ALERT_THRESHOLD) continue

    const cName = c.name || c.email.split('@')[0]
    const msg = await composeMessage(coachName[c.coach_email] || 'המאמן', cName, c.goal, reasons)

    const { data: alertRow, error: insErr } = await sb.from('churn_alerts').insert({
      coach_email: c.coach_email, client_email: c.email, client_name: cName,
      risk_score: score, reasons, suggested_message: msg, status: 'new',
    }).select('id').single()
    if (insErr) continue

    await sb.from('coach_notifications').insert({
      coach_email: c.coach_email, client_email: c.email, client_name: cName,
      read: false,
      data: { kind: 'churn_risk', score, reasons, alert_id: alertRow?.id ?? null },
    })

    // tracking only — free for the coach (competitive differentiator)
    const { data: tokenRow } = await sb.from('coach_tokens').select('balance').eq('coach_email', c.coach_email).maybeSingle()
    await sb.from('token_usage').insert({
      coach_email: c.coach_email, amount: 0, kind: 'churn',
      label: `התראת נטישה — ${cName} (${score}%) · כלול במנוי`,
      balance_after: tokenRow?.balance ?? null,
    })

    created++
    flagged.push(`${c.email}:${score}`)
  }

  return `ok — scanned ${clients.length}, alerts created ${created}${flagged.length ? ' [' + flagged.join(', ') + ']' : ''}`
}

Deno.serve(async (req) => {
  // real auth: the bearer must BE the server key (not just any bearer)
  const auth = req.headers.get('Authorization') || ''
  if (auth !== `Bearer ${SERVICE_KEY}`) {
    return new Response('Unauthorized', { status: 401 })
  }
  try {
    const result = await run()
    return new Response(result, { status: 200 })
  } catch (e) {
    return new Response('error: ' + (e as Error).message, { status: 500 })
  }
})
