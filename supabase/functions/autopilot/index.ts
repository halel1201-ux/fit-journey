/**
 * Autopilot Edge Function — Fit Journey
 * Called every minute by pg_cron.
 * Processes autopilot_queue items ≥2 min old and unanswered.
 * Sends push notification via OneSignal (no WhatsApp needed).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY      = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANTHROPIC_KEY    = Deno.env.get('ANTHROPIC_API_KEY')!
const ONESIGNAL_APP_ID  = 'fe16a494-b8de-47e9-8a29-de052e048ec8'
const ONESIGNAL_REST    = 'os_v2_app_7ylkjffy3zd6tcrj3ycs4beozaggpy5dukfe45efqruamrlljsrgz4rncsssvzvsbpt2df3zts2vdwcl2qg6zowamqntfmprxzppmjq'

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const TOKEN_MARKUP = 1.15
const CLAUDE_MODEL = 'claude-haiku-4-5-20251001'
const MAX_TOKENS   = 350

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

function buildSystemPrompt(coachName: string, clientName: string, clientGoal: string | null, training: string | null, nutrition: string | null): string {
  const goalMap: Record<string, string> = { cut: 'חיטוב', recomp: 'ריקומפוזיציה', mass: 'מסה', peak_week: 'פייק וויק' }
  const goalHeb = clientGoal ? (goalMap[clientGoal] ?? clientGoal) : 'לא הוגדרה'
  return `אתה עוזר ה-AI של מאמן הכושר ${coachName}, שמגיב ללקוחות בשמו כאשר הוא לא זמין.

מידע על הלקוח:
שם: ${clientName}
מטרה: ${goalHeb}
תוכנית אימונים: ${training ? training.slice(0, 800) : 'לא נמצאה — תן עצה כללית בטוחה.'}
תפריט תזונה: ${nutrition ? nutrition.slice(0, 800) : 'לא נמצא — תן עצה כללית בטוחה.'}

כללים מחייבים:
1. עברית ישראלית שוטפת, ידידותית, קצרה (3-4 משפטים מקסימום).
2. אתה ${coachName} — אל תאמר "אני AI" או "אני בוט".
3. אל תמציא פרטים שלא ניתנו לך.
4. אם שאלה רפואית — הפנה לרופא בעדינות.

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
    const [{ data: client }, { data: coach }, { data: training }, { data: nutrition }, { data: history }] = await Promise.all([
      sb.from('clients').select('name, goal').eq('email', item.client_email).single(),
      sb.from('coaches').select('name').eq('email', item.coach_email).single(),
      sb.from('training_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      sb.from('nutrition_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      sb.from('messages').select('sender_email, content')
        .eq('coach_email', item.coach_email).eq('client_email', item.client_email)
        .order('created_at', { ascending: false }).limit(8),
    ])

    const clientName = client?.name ?? item.client_email.split('@')[0]
    const coachName  = coach?.name  ?? 'המאמן'

    const systemPrompt = buildSystemPrompt(
      coachName, clientName, client?.goal ?? null,
      typeof training?.plan === 'string' ? training.plan : JSON.stringify(training?.plan ?? ''),
      typeof nutrition?.plan === 'string' ? nutrition.plan : JSON.stringify(nutrition?.plan ?? ''),
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

    // e. Deduct tokens
    const { data: tokenRow } = await sb.from('coach_tokens').select('balance').eq('coach_email', item.coach_email).single()
    await sb.from('coach_tokens').upsert(
      { coach_email: item.coach_email, balance: Math.max(0, (tokenRow?.balance ?? 0) - tokensBilled), updated_at: new Date().toISOString() },
      { onConflict: 'coach_email' },
    )

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
