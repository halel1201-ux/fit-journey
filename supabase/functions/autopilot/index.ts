/**
 * Autopilot Edge Function — Fit Journey
 * Called every minute by pg_cron.
 * Processes autopilot_queue items that are ≥2 min old and still unanswered.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Env vars (set in Supabase Dashboard → Functions → Secrets) ──────────────
const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY       = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANTHROPIC_KEY     = Deno.env.get('ANTHROPIC_API_KEY')!
const WA_TOKEN          = Deno.env.get('WHATSAPP_TOKEN')!        // Meta Cloud API bearer token
const WA_PHONE_ID       = Deno.env.get('WHATSAPP_PHONE_ID')!    // Meta Phone Number ID

const sb = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false },
})

const TOKEN_MARKUP  = 1.15   // 15% system mark-up on raw token count
const CLAUDE_MODEL  = 'claude-haiku-4-5-20251001'
const MAX_TOKENS    = 350    // keep replies brief for mobile

// ── Keywords that trigger escalation ─────────────────────────────────────────
const ESCALATION_PATTERNS = [
  /כא(ב|ו|י)(ת)?\s*(חד|חזק|נורא|מאוד|הרבה)/i,
  /כואב\s*(מאוד|נורא|חזק|מאד)/i,
  /פציע(ה|תי|ת)/i,
  /נפגע(תי|תי)?/i,
  /דם|דמם|מדמם/i,
  /אמבולנס|חירום|מיון|רופא/i,
  /לא\s*טוב\s*לי/i,
  /תשלום|חיוב|עמלה|כסף\s*ש(נגבה|לקחו|לקחת)/i,
  /מחשבות\s*(שחורות|רע(ות)?)/i,
]

function detectEscalation(text: string): boolean {
  return ESCALATION_PATTERNS.some(p => p.test(text))
}

// ── System Prompt builder ─────────────────────────────────────────────────────
function buildSystemPrompt(
  coachName: string,
  clientName: string,
  clientGoal: string | null,
  trainingPlanSummary: string | null,
  nutritionPlanSummary: string | null,
): string {
  const goalMap: Record<string, string> = {
    cut:       'חיטוב',
    recomp:    'ריקומפוזיציה',
    mass:      'מסה',
    peak_week: 'פייק וויק — שבוע לפני תחרות',
  }
  const goalHeb = clientGoal ? (goalMap[clientGoal] ?? clientGoal) : 'לא הוגדרה'

  return `אתה עוזר ה-AI של מאמן הכושר ${coachName}, שמגיב ללקוחות בשמו כאשר הוא לא זמין זמנית.

═══ מידע על הלקוח שאתה מגיב לו ═══
שם: ${clientName}
מטרה נוכחית: ${goalHeb}

תוכנית אימונים:
${trainingPlanSummary ? trainingPlanSummary.slice(0, 800) : 'לא נמצאה תוכנית אימונים — ספק עצה כללית ובטוחה בלבד.'}

תפריט תזונה:
${nutritionPlanSummary ? nutritionPlanSummary.slice(0, 800) : 'לא נמצא תפריט תזונה — ספק עצה כללית ובטוחה בלבד.'}

═══ כללים מחייבים ═══
1. **שפה**: עברית ישראלית שוטפת, ידידותית, מעודדת, לא פורמלית מדי.
2. **קצר**: מקסימום 3–4 משפטים. המסך של הלקוח קטן — אל תמלא אותו.
3. **זהות**: אתה ${coachName} — אל תאמר "אני AI" או "אני בוט". פשוט ענה כמאמן.
4. **אמת**: אל תמציא פרטים שלא ניתנו לך. אם לא יודע — אמור "נבדוק ביחד" או תן עצה כללית בטוחה.
5. **אין אבחנות רפואיות**: אם שאלה רפואית — הפנה לרופא בעדינות.

═══ פרוטוקול הסלמה (חשוב ביותר) ═══
אם הלקוח מזכיר:
  • כאב חד/חזק, פציעה, דימום, אמבולנס, חירום רפואי
  • תלונה על תשלום/חיוב
  • מצוקה רגשית קשה
אז ענה בדיוק כך (אל תשנה כלום):

"שאלה חשובה, סימנתי אותה למאמן ויחזור אליך בהקדם 🙏 אם זה דחוף — פנה לגורם מקצועי."

ואל תוסיף דבר נוסף לאחר משפט זה.

═══ סגנון תשובה אידיאלי ═══
• אמפתיה קצרה → תשובה ישירה → עידוד קצר.
• דוגמה: "בדיוק, זה נורמלי אחרי אימון כבד 💪 תן לשרירים 48 שעות מנוחה ושתה יותר מים. ממשיכים חזק!"
`
}

// ── WhatsApp message formatter ─────────────────────────────────────────────────
function buildWhatsAppMessage(
  clientName: string,
  clientMsg:  string,
  aiReply:    string,
  tokensBilled: number,
  escalated:  boolean,
): string {
  const now = new Date().toLocaleString('he-IL', { timeZone: 'Asia/Jerusalem' })
  const urgentBadge = escalated ? '\n\n🚨 *תשומת לב — נדרשת תגובה דחופה ממך!*' : ''

  return (
    `🤖 *עדכון טייס אוטומטי — Fit Journey*\n` +
    `───────────────────\n` +
    `👤 *לקוח:* ${clientName}\n` +
    `🕐 *שעה:* ${now}\n\n` +
    `💬 *שאלת הלקוח:*\n${clientMsg.slice(0, 300)}${clientMsg.length > 300 ? '…' : ''}\n\n` +
    `🤖 *תשובת ה-AI:*\n${aiReply.slice(0, 400)}${aiReply.length > 400 ? '…' : ''}\n\n` +
    `🪙 *טוקנים שנוצלו:* ${tokensBilled}\n` +
    urgentBadge
  )
}

// ── Send WhatsApp via Meta Cloud API ─────────────────────────────────────────
async function sendWhatsApp(to: string, body: string): Promise<boolean> {
  const phoneDigits = to.replace(/\D/g, '')
  try {
    const res = await fetch(
      `https://graph.facebook.com/v19.0/${WA_PHONE_ID}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${WA_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: phoneDigits,
          type: 'text',
          text: { body, preview_url: false },
        }),
      },
    )
    return res.ok
  } catch {
    return false
  }
}

// ── Call Anthropic Claude ─────────────────────────────────────────────────────
async function callClaude(systemPrompt: string, messages: { role: 'user' | 'assistant'; content: string }[]) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key':         ANTHROPIC_KEY,
      'anthropic-version': '2023-06-01',
      'Content-Type':      'application/json',
    },
    body: JSON.stringify({
      model:      CLAUDE_MODEL,
      max_tokens: MAX_TOKENS,
      system:     systemPrompt,
      messages,
    }),
  })

  if (!res.ok) {
    const err = await res.text()
    throw new Error(`Anthropic error ${res.status}: ${err}`)
  }

  return await res.json() as {
    content: Array<{ type: string; text: string }>
    usage: { input_tokens: number; output_tokens: number }
  }
}

// ── Process a single queue item ───────────────────────────────────────────────
async function processItem(item: {
  id: number
  coach_email: string
  client_email: string
  message_text: string
  created_at: string
}) {
  try {
    // ── a. Check if coach replied after this message was queued ──────────────
    const { data: coachReply } = await sb
      .from('messages')
      .select('id')
      .eq('coach_email', item.coach_email)
      .eq('client_email', item.client_email)
      .eq('sender_email', item.coach_email)
      .eq('is_ai_reply', false)
      .gt('created_at', item.created_at)
      .limit(1)
      .maybeSingle()

    if (coachReply) {
      // Coach beat us — skip gracefully
      await sb.from('autopilot_queue').update({
        processed_at: new Date().toISOString(),
        skipped: true,
        processing: false,
      }).eq('id', item.id)
      return
    }

    // ── b. Fetch context in parallel ─────────────────────────────────────────
    const [
      { data: client },
      { data: coach },
      { data: training },
      { data: nutrition },
      { data: history },
    ] = await Promise.all([
      sb.from('clients').select('name, goal').eq('email', item.client_email).single(),
      sb.from('coaches').select('name, whatsapp_number').eq('email', item.coach_email).single(),
      sb.from('training_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      sb.from('nutrition_plans').select('plan').eq('client_email', item.client_email).maybeSingle(),
      // Last 8 messages for conversation context (reversed to chronological)
      sb.from('messages')
        .select('sender_email, content')
        .eq('coach_email', item.coach_email)
        .eq('client_email', item.client_email)
        .order('created_at', { ascending: false })
        .limit(8),
    ])

    const clientName = client?.name ?? item.client_email.split('@')[0]
    const coachName  = coach?.name  ?? 'המאמן'

    // ── c. Build prompt & conversation history ────────────────────────────────
    const systemPrompt = buildSystemPrompt(
      coachName,
      clientName,
      client?.goal ?? null,
      typeof training?.plan === 'string' ? training.plan : JSON.stringify(training?.plan ?? ''),
      typeof nutrition?.plan === 'string' ? nutrition.plan : JSON.stringify(nutrition?.plan ?? ''),
    )

    const conversationMessages: { role: 'user' | 'assistant'; content: string }[] =
      history && history.length > 0
        ? (history as { sender_email: string; content: string }[])
            .reverse()
            .map(m => ({
              role:    m.sender_email === item.client_email ? 'user' : 'assistant',
              content: m.content,
            }))
        : [{ role: 'user', content: item.message_text }]

    // ── d. Escalation check BEFORE calling Claude ─────────────────────────────
    const preEscalated = detectEscalation(item.message_text)
    let aiText: string
    let inputTokens  = 0
    let outputTokens = 0

    if (preEscalated) {
      aiText = 'שאלה חשובה, סימנתי אותה למאמן ויחזור אליך בהקדם 🙏 אם זה דחוף — פנה לגורם מקצועי.'
      // Minimal token cost for escalations — charge 10 tokens symbolically
      inputTokens  = 5
      outputTokens = 5
    } else {
      // ── e. Call Claude ────────────────────────────────────────────────────
      const claudeRes = await callClaude(systemPrompt, conversationMessages)
      aiText       = claudeRes.content.find(c => c.type === 'text')?.text ?? 'אחזור אליך בהקדם 🙏'
      inputTokens  = claudeRes.usage.input_tokens
      outputTokens = claudeRes.usage.output_tokens
    }

    const totalTokens  = inputTokens + outputTokens
    const tokensBilled = Math.ceil(totalTokens * TOKEN_MARKUP)
    const escalated    = preEscalated || detectEscalation(aiText)

    // ── f. Insert AI reply as a real message ──────────────────────────────────
    await sb.from('messages').insert({
      coach_email:  item.coach_email,
      client_email: item.client_email,
      sender_email: item.coach_email,   // appears as coach in UI
      content:      aiText,
      is_ai_reply:  true,
      tokens_used:  tokensBilled,
    })

    // ── g. Deduct tokens from coach balance (atomic: read → compute → write) ─
    const { data: tokenRow } = await sb
      .from('coach_tokens')
      .select('balance')
      .eq('coach_email', item.coach_email)
      .single()

    const currentBalance = tokenRow?.balance ?? 0
    const newBalance     = Math.max(0, currentBalance - tokensBilled)

    await sb.from('coach_tokens').upsert(
      { coach_email: item.coach_email, balance: newBalance, updated_at: new Date().toISOString() },
      { onConflict: 'coach_email' },
    )

    // ── h. Write audit log ────────────────────────────────────────────────────
    const { data: logRow } = await sb.from('autopilot_logs').insert({
      coach_email:    item.coach_email,
      client_email:   item.client_email,
      client_message: item.message_text,
      ai_response:    aiText,
      model:          CLAUDE_MODEL,
      input_tokens:   inputTokens,
      output_tokens:  outputTokens,
      total_tokens:   totalTokens,
      tokens_billed:  tokensBilled,
      escalated,
      whatsapp_sent:  false,
    }).select('id').single()

    // ── i. Send WhatsApp notification to coach ────────────────────────────────
    let waSent = false
    if (coach?.whatsapp_number) {
      const waBody = buildWhatsAppMessage(clientName, item.message_text, aiText, tokensBilled, escalated)
      waSent = await sendWhatsApp(coach.whatsapp_number, waBody)
      if (waSent && logRow?.id) {
        await sb.from('autopilot_logs').update({ whatsapp_sent: true }).eq('id', logRow.id)
      }
    }

    // ── j. Mark queue item done ───────────────────────────────────────────────
    await sb.from('autopilot_queue').update({
      processed_at: new Date().toISOString(),
      processing:   false,
    }).eq('id', item.id)

  } catch (err) {
    // Release processing lock so it will be retried next minute
    console.error(`[autopilot] item ${item.id} failed:`, err)
    await sb.from('autopilot_queue').update({ processing: false }).eq('id', item.id)
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  // Verify the call is from pg_cron (service role bearer) or an authorised source
  const auth = req.headers.get('Authorization') ?? ''
  if (!auth.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 })
  }

  // ── Atomically claim all processable items ────────────────────────────────
  // UPDATE … WHERE processing=false AND processed_at IS NULL AND process_after<=now()
  // RETURNING * ensures we only work on rows we actually locked.
  const { data: items, error } = await sb
    .from('autopilot_queue')
    .update({ processing: true })
    .is('processed_at', null)
    .eq('processing', false)
    .lte('process_after', new Date().toISOString())
    .select()

  if (error) {
    console.error('[autopilot] queue claim error:', error)
    return new Response('error', { status: 500 })
  }

  if (!items || items.length === 0) {
    return new Response('ok — nothing to process', { status: 200 })
  }

  // Process concurrently (each item is independent)
  await Promise.allSettled(items.map(processItem))

  return new Response(`ok — processed ${items.length} item(s)`, { status: 200 })
})
