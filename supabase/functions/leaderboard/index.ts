/**
 * Leaderboard — Fit Journey gamification (ליגת הקבוצה)
 * Computes the coach-team monthly leaderboard from EXISTING data
 * (workout_logs, food_logs, checkins, coach_notifications PRs) — no new write paths.
 * Caller: any logged-in team member (client or the coach). RLS-safe: aggregation
 * runs server-side with the service key; the browser only receives the summary.
 *
 * Points: workout 10 · nutrition day 5 · weekly check-in 15 · PR 20 · streak day 5
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
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...cors, 'content-type': 'application/json' } })

// longest run of consecutive days in a set of YYYY-MM-DD dates
function longestStreak(dates: string[]): number {
  if (!dates.length) return 0
  const days = [...new Set(dates)].sort()
  let best = 1, cur = 1
  for (let i = 1; i < days.length; i++) {
    const prev = new Date(days[i - 1]).getTime()
    const curD = new Date(days[i]).getTime()
    if (curD - prev === 864e5) { cur++; best = Math.max(best, cur) } else cur = 1
  }
  return best
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    // 1. verify the caller is a logged-in user
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'no auth' }, 401)
    const authClient = createClient(SUPABASE_URL, ANON_KEY)
    const { data: { user }, error: authErr } = await authClient.auth.getUser(token)
    if (authErr || !user?.email) return json({ error: 'unauthorized' }, 401)
    const email = user.email

    // 2. resolve the caller's team (their coach, or themselves if they are a coach)
    const [{ data: meClient }, { data: meCoach }] = await Promise.all([
      admin.from('clients').select('coach_email').eq('email', email).maybeSingle(),
      admin.from('coaches').select('email').eq('email', email).maybeSingle(),
    ])
    const coachEmail = meClient?.coach_email || meCoach?.email
    if (!coachEmail) return json({ error: 'no team' }, 403)

    // 3. month window (current month, local-enough: month boundaries in UTC are fine for a league)
    const body = await req.json().catch(() => ({}))
    const now = new Date()
    const ym = typeof body.month === 'string' && /^\d{4}-\d{2}$/.test(body.month)
      ? body.month
      : `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
    const monthStart = `${ym}-01`
    const nextMonth = new Date(Date.UTC(+ym.slice(0, 4), +ym.slice(5, 7), 1)).toISOString().slice(0, 10)

    // 4. team members (active coaching)
    const { data: team } = await admin.from('clients')
      .select('email,name')
      .eq('coach_email', coachEmail)
      .gte('coaching_end', monthStart)
    if (!team?.length) return json({ month: ym, rows: [], me: email })
    const emails = team.map(t => t.email)

    // 5. batched month data
    const [{ data: workouts }, { data: foods }, { data: checkins }, { data: notifs }] = await Promise.all([
      admin.from('workout_logs').select('client_email,log_date,total_volume').gte('log_date', monthStart).lt('log_date', nextMonth).in('client_email', emails),
      admin.from('food_logs').select('client_email,log_date').gte('log_date', monthStart).lt('log_date', nextMonth).in('client_email', emails),
      admin.from('checkins').select('client_email,week_date').gte('week_date', monthStart).lt('week_date', nextMonth).in('client_email', emails),
      admin.from('coach_notifications').select('client_email,data,created_at').eq('coach_email', coachEmail).gte('created_at', monthStart).lt('created_at', nextMonth).in('client_email', emails),
    ])

    // 6. aggregate per member
    const agg: Record<string, { workouts: string[]; volume: number; nutriDays: Set<string>; checkins: number; prs: number }> = {}
    const A = (e: string) => (agg[e] ??= { workouts: [], volume: 0, nutriDays: new Set(), checkins: 0, prs: 0 })
    ;(workouts || []).forEach(w => { const a = A(w.client_email); a.workouts.push(w.log_date); a.volume += Number(w.total_volume) || 0 })
    ;(foods || []).forEach(f => A(f.client_email).nutriDays.add(f.log_date))
    ;(checkins || []).forEach(c => { A(c.client_email).checkins++ })
    ;(notifs || []).forEach(n => { const prs = n.data?.prs; if (Array.isArray(prs) && prs.length) A(n.client_email).prs += prs.length })

    const rows = team.map(t => {
      const a = agg[t.email] || { workouts: [], volume: 0, nutriDays: new Set(), checkins: 0, prs: 0 }
      const streak = longestStreak(a.workouts)
      const points = a.workouts.length * 10 + a.nutriDays.size * 5 + a.checkins * 15 + a.prs * 20 + streak * 5
      return {
        email: t.email, name: t.name || t.email.split('@')[0],
        points, workouts: a.workouts.length, nutriDays: a.nutriDays.size,
        checkins: a.checkins, prs: a.prs, streak, volume: Math.round(a.volume),
        titles: [] as string[],
        medal: points >= 500 ? 'gold' : points >= 250 ? 'silver' : points >= 100 ? 'bronze' : null,
      }
    }).sort((x, y) => y.points - x.points)

    // 7. monthly titles (only when there's actual activity)
    const withActivity = rows.filter(r => r.points > 0)
    if (withActivity.length) {
      withActivity[0].titles.push('🥇 אלוף/ת החודש')
      const byStreak = [...withActivity].sort((a, b) => b.streak - a.streak)[0]
      if (byStreak.streak >= 3) byStreak.titles.push('🔥 רצף ברזל')
      const byVolume = [...withActivity].sort((a, b) => b.volume - a.volume)[0]
      if (byVolume.volume > 0) byVolume.titles.push('🏋️ מפלצת נפח')
      const byNutri = [...withActivity].sort((a, b) => b.nutriDays - a.nutriDays)[0]
      if (byNutri.nutriDays >= 5) byNutri.titles.push('🥗 מלך/מלכת העקביות')
    }

    return json({ month: ym, rows, me: email, coach: coachEmail })
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500)
  }
})
