/**
 * Autopilot Edge Function — Fit Journey
 * Called every minute by pg_cron.
 * Processes autopilot_queue items ≥2 min old and unanswered.
 * Sends push notification via OneSignal (no WhatsApp needed).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY      = Deno.env.get('ADMIN_DB_KEY')!  // new server-side key (old service_role retired)
const ANTHROPIC_KEY    = Deno.env.get('ANTHROPIC_API_KEY')!
const ONESIGNAL_APP_ID  = 'fe16a494-b8de-47e9-8a29-de052e048ec8'
const ONESIGNAL_REST    = 'os_v2_app_7ylkjffy3zd6tcrj3ycs4beozaggpy5dukfe45efqruamrlljsrgz4rncsssvzvsbpt2df3zts2vdwcl2qg6zowamqntfmprxzppmjq'

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const TOKEN_MARKUP = 1.15
const CLAUDE_MODEL = 'claude-haiku-4-5-20251001'
const MAX_TOKENS   = 500

const ESCALATION_PATTERNS = [
  /כא(ב|ו|י)(ת)?\s*(חד|חזק|נורא|מאוד|הרבה)/i,
  /כואב\s*(מאוד|נורא|חזק|מאד)/i,
  /פציע(ה|תי|ת)/i,
  /נפגע(תי)?/i,
  /דם|דמם|מדמם/i,
  /אמבולנס|חירום|מיון|רופא/i,
  /לא\s*טוב\s*לי/i,
  /תשלום|חיוב|עמלה/i,
  /מחשבות\s*(שחורות|רע(ות)?)/i,
]

function detectEscalation(text: string): boolean {
  return ESCALATION_PATTERNS.some(p => p.test(text))
}

function buildSystemPrompt(coachName: string, clientName: string, clientGoal: string | null, training: string | null, nutrition: string | null, foodToday: string, exLib: string): string {
  const goalMap: Record<string, string> = { cut: 'חיטוב', recomp: 'ריקומפוזיציה', mass: 'מסה', peak_week: 'פייק וויק' }
  const goalHeb = clientGoal ? (goalMap[clientGoal] ?? clientGoal) : 'לא הוגדרה'
  return `אתה עוזר ה-AI של מאמן הכושר ${coachName}, שמגיב ללקוחות בשמו כאשר הוא לא זמין.

מידע על הלקוח:
שם: ${clientName}
מטרה: ${goalHeb}
תוכנית אימונים: ${training ? training.slice(0, 1200) : 'לא נמצאה — תן עצה כללית בטוחה.'}
תפריט תזונה: ${nutrition ? nutrition.slice(0, 800) : 'לא נמצא — תן עצה כללית בטוחה.'}

מה הלקוח אכל היום:
${foodToday}

מאגר התרגילים (שם [שריר/תת-שריר] 🎥קישור-סרטון):
${exLib.slice(0, 6000)}

כללים מחייבים:
1. עברית ישראלית שוטפת, ידידותית, קצרה (3-4 משפטים מקסימום).
2. אתה ${coachName} — אל תאמר "אני AI" או "אני בוט".
3. אל תמציא פרטים שלא ניתנו לך.
4. אם שאלה רפואית — הפנה לרופא בעדינות.

הכשרת תזונה — חובה לפעול לפיה בכל שאלה על אוכל/קלוריות/מאקרו:
- אסור לזרוק מספר קלוריות "מהאוויר". כל הערכה חייבת להתבסס על פירוק המנה לרכיבים והערכת משקל בגרמים.
- שיטת חישוב: (א) פרק לרכיבים — פחמימה, חלבון, שומן, רטבים. (ב) הערך משקל בגרמים לכל רכיב. (ג) חשב לפי ערכים ל-100 גר'. (ד) תן טווח והסבר ממה נובע ההבדל.
- ערכי מאקרו: חלבון 4 קק"ל/גר', פחמימה 4, שומן 9, אלכוהול 7.
- ערכי ייחוס ל-100 גר' (מוכן): לאפה/פיתה ~275, אורז לבן מבושל ~130, פסטה מבושלת ~155, תפו"א ~85, פלאפל ~330, חומוס ~170, טחינה גולמית ~590, חזה עוף ~165, בשר בקר טחון ~230, שווארמה עוף/הודו ~200, שווארמה טלה/כבש ~290, גבינה צהובה ~350. כף שמן זית ~120, כף טחינה ~90.
- דוגמה מפורקת — לאפה שווארמה: לאפה 90-120 גר' (~300 קק"ל) + בשר 150-200 גר' (~350-500) + טחינה/חומוס 2-3 כפות (~180-270) + סלט (~40). סה"כ ריאלי ~850-1150 קק"ל. (הטעות הנפוצה היא לזלזל בכמות הבשר, הלאפה והטחינה — אל תיתן מספרים נמוכים מדי!)
- אם חסרים פרטים (גודל מנה, משקל) — שאל, או תן טווח עם הנחה מפורשת ("בהנחה של לאפה בינונית ו-150 גר' בשר...").
- אם קיים תפריט של המאמן — התאם אליו והפנה אליו.

שאלות על אוכל שאכל היום / מה נשאר לאכול:
- התבסס על "מה הלקוח אכל היום" (למעלה) ועל היעד היומי. חשב כמה קלוריות/חלבון נותרו ליעד, והמלץ בהתאם.
- אם שואל "מה עוד לאכול" — הצע אוכל שמשלים את החוסר (בעיקר חלבון אם חסר), רצוי מהתפריט של המאמן.

החלפת תרגיל:
- אם הלקוח רוצה להחליף תרגיל — המלץ על 1-2 תרגילים חלופיים **מאותה קבוצת שריר** (עדיף אותו תת-שריר) מתוך "מאגר התרגילים".
- אל תמליץ על תרגיל שכבר נמצא באימון הנוכחי שלו (בדוק בתוכנית האימונים) — בלי כפילויות.

איך לבצע תרגיל / טכניקה:
- תן 2-3 דגשים טכניים קצרים וברורים.
- אם לתרגיל יש 🎥 קישור-סרטון במאגר — צרף את הקישור המדויק ("הנה סרטון הדגמה: ...").

ידע בשיטת מיו-רפס (Myo-Reps) — הסבר/ייעץ אם שואלים עליה:
- מהי: שיטת היפרטרופיה מתקדמת (בורגה פאגרלי, 2006) שממקסמת "חזרות אפקטיביות" בזמן קצר, עם גיוס מרבי של סיבי שריר ועומס מטבולי.
- מבנה: (1) סט הפעלה — משקל ל-9-20 חזרות, עוצרים 1-2 חזרות לפני כשל. (2) מנוחה קצרה 10-15 שניות (3-5 נשימות, המשקל נשאר בידיים). (3) מיני-סטים של 3-5 חזרות עם אותו משקל, מנוחה 10-15ש בין כל אחד. (4) מסיימים אחרי 5 מיני-סטים או כשלא מגיעים למספר החזרות של המיני-סט.
- דוגמה לרישום: 15+3+3+3+3+2 (במיני-סט האחרון היה כשל → הסט הסתיים).
- למה יעיל: רק 3-5 החזרות האחרונות (קרוב לכשל) באמת מגרות צמיחה; המנוחה הקצרה שומרת על גיוס הסיבים הגדולים כך שכל חזרה במיני-סט אפקטיבית; חוסך זמן — סט מיו-רפס ≈ 3-4 סטים רגילים ב-~2 דקות.
- בטיחות (חשוב!): לא מתאים לתרגילים מורכבים עם משקל חופשי (סקוואט, דדליפט, לחיצת חזה במוט) — קשה לשמור טכניקה בעייפות. מומלץ במכונות, כבלים ותרגילי בידוד (לחיצת רגליים, פולי, כפיפות מרפק, הרחקות).

פרוטוקול הסלמה — אם הלקוח מזכיר כאב חד, פציעה, דימום, חירום, תשלום/חיוב או מצוקה רגשית:
ענה בדיוק: "שאלה חשובה, סימנתי אותה למאמן ויחזור אליך בהקדם 🙏 אם זה דחוף — פנה לגורם מקצועי."
ואל תוסיף כלום אחרי זה.`
}

// ── Send push notification to coach via OneSignal ─────────────────────────────
async function sendPushToCoach(coachEmail: string, clientName: string, preview: string, escalated: boolean): Promise<boolean> {
  try {
    // Get coach's OneSignal subscription ID from push_tokens table
    const { data: tokenRow } = await sb
      .from('push_tokens')
      .select('onesignal_player_id')
      .eq('user_email', coachEmail)
      .maybeSingle()

    if (!tokenRow?.onesignal_player_id) return false

    const title = escalated ? `🚨 דחוף — ${clientName}` : `✈️ טייס אוטומטי — ${clientName}`
    const body  = preview.slice(0, 100)

    const res = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Key ${ONESIGNAL_REST}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_subscription_ids: [tokenRow.onesignal_player_id],
        headings: { he: title, en: title },
        contents: { he: body,  en: body  },
      }),
    })
    return res.ok
  } catch { return false }
}

async function callClaude(systemPrompt: string, messages: { role: 'user' | 'assistant'; content: string }[]) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: CLAUDE_MODEL, max_tokens: MAX_TOKENS, system: systemPrompt, messages }),
  })
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${await res.text()}`)
  return await res.json() as {
    content: Array<{ type: string; text: string }>
    usage: { input_tokens: number; output_tokens: number }
  }
}

async function processItem(item: { id: number; coach_email: string; client_email: string; message_text: string; created_at: string }) {
  try {
    // a. Check if coach replied already
    const { data: coachReply } = await sb.from('messages').select('id')
      .eq('coach_email', item.coach_email).eq('client_email', item.client_email)
      .eq('sender_email', item.coach_email).eq('is_ai_reply', false)
      .gt('created_at', item.created_at).limit(1).maybeSingle()

    if (coachReply) {
      await sb.from('autopilot_queue').update({ processed_at: new Date().toISOString(), skipped: true, processing: false }).eq('id', item.id)
      return
    }

    // b. Fetch context
    const today = new Date().toISOString().split('T')[0]
    const [{ data: client }, { data: coach }, { data: training }, { data: nutrition }, { data: history }, { data: foodLogs }, { data: exLib }] = await Promise.all([
      sb.from('clients').select('name, goal, target_calories, target_protein, target_carbs, target_fat').eq('email', item.client_email).single(),
      sb.from('coaches').select('name').eq('email', item.coach_email).single(),
      sb.from('training_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      sb.from('nutrition_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      sb.from('messages').select('sender_email, content')
        .eq('coach_email', item.coach_email).eq('client_email', item.client_email)
        .order('created_at', { ascending: false }).limit(8),
      sb.from('food_logs').select('food_name, grams, calories, protein, carbs, fat, meal_type')
        .eq('client_email', item.client_email).eq('log_date', today),
      sb.from('exercises').select('name, muscle_group, sub_muscle_group, video_url'),
    ])

    const clientName = client?.name ?? item.client_email.split('@')[0]
    const coachName  = coach?.name  ?? 'המאמן'

    // מה הלקוח אכל היום + כמה נותר ליעד
    let foodToday = 'לא דיווח אוכל היום עדיין.'
    if (foodLogs && foodLogs.length) {
      const t = foodLogs.reduce((a: {cal:number;p:number;c:number;f:number}, x: {calories?:number;protein?:number;carbs?:number;fat?:number}) =>
        ({ cal: a.cal + (+(x.calories ?? 0)), p: a.p + (+(x.protein ?? 0)), c: a.c + (+(x.carbs ?? 0)), f: a.f + (+(x.fat ?? 0)) }), { cal: 0, p: 0, c: 0, f: 0 })
      const items = (foodLogs as {food_name?:string;grams?:number;calories?:number}[]).map(x => `${x.food_name} (${Math.round(+(x.grams ?? 0))}ג׳/${Math.round(+(x.calories ?? 0))} קק״ל)`).join(', ')
      const tgt = client?.target_calories ? ` | יעד יומי: ${client.target_calories} קק״ל, חלבון ${client.target_protein ?? '?'}ג׳` : ''
      foodToday = `סה״כ היום: ${Math.round(t.cal)} קק״ל · חלבון ${Math.round(t.p)}ג׳ · פחמ׳ ${Math.round(t.c)}ג׳ · שומן ${Math.round(t.f)}ג׳${tgt}\nפריטים: ${items}`
    }
    // מאגר תרגילים (לשם, שריר, וסרטון) — להחלפות והדגמות
    const exText = (exLib as {name?:string;muscle_group?:string;sub_muscle_group?:string;video_url?:string}[] ?? [])
      .map(e => `${e.name} [${e.muscle_group ?? ''}${e.sub_muscle_group ? '/' + e.sub_muscle_group : ''}]${e.video_url ? ' 🎥' + e.video_url : ''}`).join('\n')

    const systemPrompt = buildSystemPrompt(
      coachName, clientName, client?.goal ?? null,
      typeof training?.plan === 'string' ? training.plan : JSON.stringify(training?.plan ?? ''),
      typeof nutrition?.plan === 'string' ? nutrition.plan : JSON.stringify(nutrition?.plan ?? ''),
      foodToday, exText,
    )

    const msgs: { role: 'user' | 'assistant'; content: string }[] =
      history && history.length > 0
        ? (history as { sender_email: string; content: string }[]).reverse()
            .map(m => ({ role: m.sender_email === item.client_email ? 'user' : 'assistant', content: m.content }))
        : [{ role: 'user', content: item.message_text }]

    // c. Escalation check
    const preEscalated = detectEscalation(item.message_text)
    let aiText: string, inputTokens = 0, outputTokens = 0

    if (preEscalated) {
      aiText = 'שאלה חשובה, סימנתי אותה למאמן ויחזור אליך בהקדם 🙏 אם זה דחוף — פנה לגורם מקצועי.'
      inputTokens = 5; outputTokens = 5
    } else {
      const r = await callClaude(systemPrompt, msgs)
      aiText       = r.content.find(c => c.type === 'text')?.text ?? 'אחזור אליך בהקדם 🙏'
      inputTokens  = r.usage.input_tokens
      outputTokens = r.usage.output_tokens
    }

    const totalTokens  = inputTokens + outputTokens
    const tokensBilled = Math.ceil(totalTokens * TOKEN_MARKUP)
    const escalated    = preEscalated || detectEscalation(aiText)

    // d. Insert AI reply as message
    await sb.from('messages').insert({
      coach_email: item.coach_email, client_email: item.client_email,
      sender_email: item.coach_email, content: aiText,
      is_ai_reply: true, tokens_used: tokensBilled,
    })

    // e. Subscription model — no per-message deduction. Log for tracking only (amount 0).
    const { data: tokenRow } = await sb.from('coach_tokens').select('balance').eq('coach_email', item.coach_email).single()
    await sb.from('token_usage').insert({
      coach_email: item.coach_email, amount: 0, kind: 'autopilot',
      label: `תשובה ל-${clientName} (${tokensBilled} טוקני AI · כלול במנוי)`,
      balance_after: tokenRow?.balance ?? null,
    })

    // f. Audit log
    const { data: logRow } = await sb.from('autopilot_logs').insert({
      coach_email: item.coach_email, client_email: item.client_email,
      client_message: item.message_text, ai_response: aiText,
      model: CLAUDE_MODEL, input_tokens: inputTokens, output_tokens: outputTokens,
      total_tokens: totalTokens, tokens_billed: tokensBilled,
      escalated, whatsapp_sent: false,
    }).select('id').single()

    // g. Push notification to coach
    const pushPreview = `${clientName}: ${item.message_text.slice(0, 60)} → ${aiText.slice(0, 60)}`
    const pushed = await sendPushToCoach(item.coach_email, clientName, pushPreview, escalated)
    if (pushed && logRow?.id) {
      await sb.from('autopilot_logs').update({ whatsapp_sent: true }).eq('id', logRow.id)
    }

    // h. Done
    await sb.from('autopilot_queue').update({ processed_at: new Date().toISOString(), processing: false }).eq('id', item.id)

  } catch (err) {
    console.error(`[autopilot] item ${item.id}:`, err)
    await sb.from('autopilot_queue').update({ processing: false }).eq('id', item.id)
  }
}

Deno.serve(async (req) => {
  if (!req.headers.get('Authorization')?.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 })
  }

  const { data: items, error } = await sb
    .from('autopilot_queue')
    .update({ processing: true })
    .is('processed_at', null)
    .eq('processing', false)
    .lte('process_after', new Date().toISOString())
    .select()

  if (error) return new Response('error', { status: 500 })
  if (!items?.length) return new Response('ok — nothing to process', { status: 200 })

  await Promise.allSettled(items.map(processItem))
  return new Response(`ok — processed ${items.length}`, { status: 200 })
})
