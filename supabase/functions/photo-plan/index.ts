/**
 * Photo-Based AI Coach (Agent 05) — Fit Journey
 * Coach uploads body photos + measurements. Server computes anthropometric ratios
 * (deterministic), Claude analyzes the photos, and returns a validated training plan
 * in the exact JSON the editor expects.
 *
 * Guardrails: exercise names must exist in the 137-exercise library; technique must be
 * one of the 9 known values; structure is validated. Invalid output -> error (no plan,
 * so the client does not deduct tokens).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY')!
const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!
const ADMIN_KEY     = Deno.env.get('ADMIN_DB_KEY')!
const PUBLISHABLE   = 'sb_publishable_k3M7SfBeiBGs3rTKewBzWQ_7RHRskB9'
const MODEL         = 'claude-sonnet-4-6'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } })

const TECH_ENUM = ['none','myo_reps','rest_pause','slow_fast','isomix','isomix_adv','isoburst','drop_set','negative']
const SET_TYPES = ['warm_up','working','failure','drop']

/* ── Deterministic anthropometric analysis ── */
function analyze(gender: string, m: Record<string, number>) {
  const weak = new Set<string>()
  const notes: string[] = []
  const legThreshold = gender === 'female' ? 12 : 20
  const highFat = m.leg > 0 && m.waist > m.leg + legThreshold
  if (highFat) notes.push('פרופורציית שומן גבוהה / מסת רגליים נמוכה יחסית — בנה תוכנית בסיס מאוזנת עם דגש רגליים עדין בלבד (הימנע מעומס לבבי/מפרקי מוגזם).')

  if (m.waist > 0) {
    const sh = m.shoulders / m.waist
    const shTarget = gender === 'female' ? 1.25 : 1.4
    if (m.shoulders > 0 && sh < shTarget) { weak.add('כתפיים'); if (gender !== 'female') weak.add('גב') }

    const arm = m.arm / m.waist
    if (m.arm > 0 && arm < 0.6) { weak.add('יד קדמית'); weak.add('יד אחורית') }

    if (gender !== 'female' && m.iliac > 0) {
      const il = m.iliac / m.waist
      if (il < 1.3) weak.add('ישבן')
    }
  }
  return { weak: [...weak], notes }
}

/* ── Split skeleton by gender + day count ── */
function splitSkeleton(gender: string, days: number): string[] {
  const d = Math.max(2, Math.min(6, days || 4))
  if (gender === 'female') {
    const map: Record<number, string[]> = {
      2: ['פלג גוף עליון', 'רגליים'],
      3: ['פלג גוף עליון', 'פלג גוף עליון', 'רגליים'],
      4: ['פלג גוף עליון', 'פלג גוף עליון', 'רגליים', 'רגליים'],
      5: ['פלג גוף עליון', 'פלג גוף עליון', 'רגליים', 'רגליים', 'פלג גוף עליון'],
      6: ['פלג גוף עליון', 'רגליים', 'פלג גוף עליון', 'רגליים', 'פלג גוף עליון', 'רגליים'],
    }
    return map[d]
  }
  const map: Record<number, string[]> = {
    2: ['Push (דחיפה)', 'Pull (משיכה)'],
    3: ['Push (דחיפה)', 'Pull (משיכה)', 'Legs (רגליים)'],
    4: ['Push (דחיפה)', 'Pull (משיכה)', 'Legs (רגליים)', 'Upper (פלג עליון)'],
    5: ['Push (דחיפה)', 'Pull (משיכה)', 'Legs (רגליים)', 'Upper (פלג עליון)', 'Legs (רגליים)'],
    6: ['Push (דחיפה)', 'Pull (משיכה)', 'Legs (רגליים)', 'Push (דחיפה)', 'Pull (משיכה)', 'Legs (רגליים)'],
  }
  return map[d]
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'no auth' }, 401)
    const authClient = createClient(SUPABASE_URL, PUBLISHABLE)
    const { data: { user } } = await authClient.auth.getUser(token)
    if (!user) return json({ error: 'unauthorized' }, 401)

    const body = await req.json()
    const { client_email, gender = 'male', goal = 'recomp', days = 4, measurements = {}, images = [] } = body
    if (!Array.isArray(images) || images.length === 0) return json({ error: 'no images' }, 400)

    const admin = createClient(SUPABASE_URL, ADMIN_KEY, { auth: { persistSession: false } })

    // exercise library (names + muscle) for the prompt + validation
    const { data: exRows } = await admin.from('exercises').select('name, muscle_group, sub_muscle_group')
    const exNames = new Set((exRows ?? []).map((e: { name: string }) => (e.name || '').trim()))
    const exList = (exRows ?? []).map((e: { name: string; muscle_group?: string; sub_muscle_group?: string }) =>
      `${e.name} [${e.muscle_group ?? ''}${e.sub_muscle_group ? '/' + e.sub_muscle_group : ''}]`).join('\n')

    const { weak, notes } = analyze(gender, measurements)
    const skeleton = splitSkeleton(gender, days)
    const reps = goal === 'cut' ? '6-12' : '6-15'

    const sys = `אתה בונה תוכנית אימון מקצועית ל-HF Coaching על סמך תמונות גוף + ניתוח אנתרופומטרי.

פרטי המתאמן: מין=${gender === 'female' ? 'אישה' : 'גבר'} · מטרה=${goal} · ${skeleton.length} ימי אימון.

ניתוח שכבר חושב עבורך (מהמדדים):
נקודות חלשות שיש לתת להן יותר נפח שבועי: ${weak.length ? weak.join(', ') : 'אין חריגות מובהקות — תוכנית מאוזנת.'}
${notes.length ? 'הערות: ' + notes.join(' ') : ''}

נתח את התמונות ויזואלית (פרופורציות, נקודות חלשות/חזקות) ושלב עם הניתוח למעלה.

חוקי בניית התוכנית (מחייבים):
- מבנה הימים (בדיוק, לפי הסדר): ${skeleton.map((s, i) => `יום ${i + 1}=${s}`).join(' · ')}
- לכל יום "פלג גוף עליון"/"Upper" — בדיוק 6 תרגילים: 2 גב, 1 חזה, 1 כתפיים, 1 יד קדמית, 1 יד אחורית.
- תן יותר נפח (סטים/תרגילים) לנקודות החלשות שצוינו.
- טווח חזרות לכל הסטים: reps_min=${reps.split('-')[0]}, reps_max=${reps.split('-')[1]}.
- 3-4 סטים לתרגיל. set_type: השתמש ב-warm_up לסט ראשון, working/failure לשאר.

מאגר התרגילים — חובה לבחור שמות תרגילים אך ורק מהרשימה הזו (העתק מדויק, מילה במילה):
${exList}

טכניקות מותרות בשדה technique: ${TECH_ENUM.join(', ')} בלבד (ברירת מחדל none).

החזר JSON תקין בלבד (בלי טקסט לפני/אחרי) במבנה:
[{"day":"שם היום","muscles":["שריר"],"exercises":[{"name":"שם מהמאגר","sets":[{"reps_min":8,"reps_max":12,"recommended_kg":0,"set_type":"working"}],"technique":"none","rest_time":90,"video_url":"","description":"","linked_next":false}]}]`

    const content: unknown[] = images.slice(0, 4).map((im: { media_type?: string; data: string }) => ({
      type: 'image',
      source: { type: 'base64', media_type: im.media_type || 'image/jpeg', data: im.data },
    }))
    content.push({ type: 'text', text: 'בנה את התוכנית לפי החוקים. החזר אך ורק מערך JSON תקין (מתחיל ב-[ ונגמר ב-]) — בלי טקסט לפני או אחרי, בלי code fences.' })

    const aiRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: MODEL, max_tokens: 8000, system: sys,
        messages: [{ role: 'user', content }],
      }),
    })
    if (!aiRes.ok) return json({ error: 'AI error: ' + (await aiRes.text()).slice(0, 300) }, 502)
    const aiJson = await aiRes.json() as { content: Array<{ type: string; text: string }>; usage: { input_tokens: number; output_tokens: number } }
    let raw = (aiJson.content.find(c => c.type === 'text')?.text ?? '').trim()
    // extract the JSON array (strip code fences / prose around it)
    const firstB = raw.indexOf('[')
    const lastB = raw.lastIndexOf(']')
    if (firstB > -1 && lastB > firstB) raw = raw.slice(firstB, lastB + 1)

    // ── Validation (Red Flags) ──
    let plan: unknown
    try { plan = JSON.parse(raw) } catch { return json({ error: 'המבנה שהתקבל אינו תקין (JSON שבור). נסה שוב.' }, 422) }
    if (!Array.isArray(plan)) return json({ error: 'הפלט אינו רשימת ימים.' }, 422)

    const badNames: string[] = []
    const badTech: string[] = []
    for (const day of plan as Array<Record<string, unknown>>) {
      if (!day || typeof day !== 'object' || !Array.isArray(day.exercises)) return json({ error: 'מבנה יום שגוי.' }, 422)
      for (const ex of day.exercises as Array<Record<string, unknown>>) {
        const nm = String((ex as { name?: string }).name ?? '').trim()
        if (!exNames.has(nm)) badNames.push(nm)
        const tech = (ex as { technique?: string }).technique ?? 'none'
        if (!TECH_ENUM.includes(tech)) badTech.push(tech)
        // normalize required fields
        ex.name = nm
        ex.technique = TECH_ENUM.includes(tech) ? tech : 'none'
        if (typeof ex.rest_time !== 'number') ex.rest_time = 90
        if (typeof ex.linked_next !== 'boolean') ex.linked_next = false
        if (typeof ex.video_url !== 'string') ex.video_url = ''
        if (typeof ex.description !== 'string') ex.description = ''
        if (!Array.isArray(ex.sets)) return json({ error: 'תרגיל ללא סטים.' }, 422)
        for (const st of ex.sets as Array<Record<string, unknown>>) {
          if (!SET_TYPES.includes(String(st.set_type))) st.set_type = 'working'
          st.reps_min = Number(st.reps_min) || 8
          st.reps_max = Number(st.reps_max) || 12
          st.recommended_kg = Number(st.recommended_kg) || 0
        }
      }
    }
    if (badNames.length) return json({ error: 'ה-AI השתמש בשמות תרגילים שלא במאגר: ' + [...new Set(badNames)].slice(0, 5).join(', ') + '. נסה שוב.' }, 422)
    if (badTech.length) return json({ error: 'טכניקה לא חוקית: ' + [...new Set(badTech)].join(', ') }, 422)

    return json({ plan, weak_points: weak, notes, tokens: (aiJson.usage.input_tokens + aiJson.usage.output_tokens) })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
