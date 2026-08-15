/**
 * telegram-shop — webhook של בוט ההזמנות של החנות.
 *
 * למה בוט בכלל: טלגרם לא מאפשר להכניס טקסט מראש לשיחה בין שני אנשים,
 * ולכן שם המוצר לא יכול "להגיע מעצמו" לצ'אט הישיר. בוט כן מקבל מטען
 * (payload) בקישור, ולכן הוא הדרך היחידה לדעת על איזה מוצר מדובר.
 *
 * הזרימה:
 *   הלקוח לוחץ "להזמנה"  →  t.me/<bot>?start=p12
 *   לוחץ Start           →  טלגרם שולח לכאן /start p12
 *   כאן                  →  שולפים את המוצר, מודיעים לבעלים, ומאשרים ללקוח
 *
 * פקודת עזר: /id מחזירה את מזהה הצ'אט — כך משיגים את TG_OWNER_ID
 * בהתקנה הראשונית, בלי לנחש.
 *
 * פריסה: verify_jwt=false — טלגרם אינו שולח JWT. במקומו האימות נעשה
 * דרך הכותרת הסודית שטלגרם מצרף לכל קריאה (secret_token), אחרת כל אחד
 * שיודע את הכתובת יוכל לזייף הזמנות.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const BOT_TOKEN  = Deno.env.get('TG_BOT_TOKEN') ?? ''
const OWNER_ID   = Deno.env.get('TG_OWNER_ID') ?? ''
const HOOK_SECRET= Deno.env.get('TG_WEBHOOK_SECRET') ?? ''
const SB_URL     = Deno.env.get('SB_URL') ?? Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY= Deno.env.get('ADMIN_DB_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const api = (method: string, body: unknown) =>
  fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => null)

const send = (chat_id: number | string, text: string, extra: Record<string, unknown> = {}) =>
  api('sendMessage', { chat_id, text, parse_mode: 'HTML', disable_web_page_preview: true, ...extra })

const esc = (s: string) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

Deno.serve(async (req) => {
  /* טלגרם שולח את הסוד בכותרת. השוואה פשוטה מספיקה כאן — הערך
     מגיע מטלגרם בלבד ואינו נגזר מקלט משתמש. */
  if (HOOK_SECRET && req.headers.get('x-telegram-bot-api-secret-token') !== HOOK_SECRET)
    return new Response('forbidden', { status: 403 })
  if (req.method !== 'POST') return new Response('ok')

  let update: any
  try { update = await req.json() } catch { return new Response('ok') }

  const msg = update?.message ?? update?.edited_message
  const chatId = msg?.chat?.id
  const text = String(msg?.text ?? '').trim()
  if (!chatId || !text) return new Response('ok')

  /* עזר להתקנה: מחזיר את מזהה הצ'אט כדי להגדיר TG_OWNER_ID */
  if (text === '/id') {
    await send(chatId, `מזהה הצ'אט שלך:\n<code>${chatId}</code>\n\nהעתק אותו להגדרת <code>TG_OWNER_ID</code>.`)
    return new Response('ok')
  }

  if (!text.startsWith('/start')) {
    /* הבוט אינו ערוץ שיחה — מפנה לשיחה ישירה כדי שלא ייווצר רושם
       שמישהו קורא כאן הודעות. */
    await send(chatId, 'הבוט מקבל הזמנות מהקטלוג בלבד 🧪\nלשאלות אפשר לכתוב ישירות: @HFitjourney')
    return new Response('ok')
  }

  const payload = text.slice(6).trim()          // מה שאחרי "/start"
  const from = msg.from ?? {}
  const who = [from.first_name, from.last_name].filter(Boolean).join(' ') || 'לקוח'
  const handle = from.username ? '@' + from.username : null

  let productLine = 'לא צוין מוצר'
  let customerLine = 'הפנייה התקבלה'

  /* המטען הוא p<id> — מזהה המוצר. טלגרם מגביל ל-64 תווים ולתווי
     base64url בלבד, ולכן מזהה מספרי ולא שם המוצר. */
  const m = payload.match(/^p(\d{1,18})$/)
  if (m && SB_URL && SERVICE_KEY) {
    try {
      const sb = createClient(SB_URL, SERVICE_KEY)
      const { data } = await sb.from('shop_products')
        .select('name,price,spec').eq('id', Number(m[1])).maybeSingle()
      if (data) {
        const price = data.price != null ? ` · ${Number(data.price).toLocaleString('he-IL')} ₪` : ''
        productLine  = `<b>${esc(data.name)}</b>${price}${data.spec ? `\n${esc(data.spec)}` : ''}`
        customerLine = `קיבלנו את הפנייה על <b>${esc(data.name)}</b> 🧪`
      }
    } catch { /* שליפה כושלת לא תמנע את ההתראה — עדיף פנייה חלקית מכלום */ }
  }

  /* התראה לבעלים. כפתור לשיחה ישירה מופיע רק אם ללקוח יש שם משתמש —
     בלעדיו אין לטלגרם קישור ציבורי, ועדיף להגיד זאת מאשר לתת כפתור מת. */
  if (OWNER_ID) {
    const lines = [
      '🛒 <b>פנייה חדשה מהחנות</b>', '', productLine, '',
      `👤 ${esc(who)}${handle ? ` (${esc(handle)})` : ''}`,
      handle ? '' : '⚠️ ללקוח אין שם משתמש — אין דרך לפתוח איתו שיחה מכאן. המתן שיכתוב.',
    ].filter(Boolean)
    await send(OWNER_ID, lines.join('\n'), handle ? {
      reply_markup: { inline_keyboard: [[{ text: `💬 פתח שיחה עם ${handle}`, url: `https://t.me/${from.username}` }]] },
    } : {})
  }

  await send(chatId,
    `${customerLine}\n\nנחזור אליך כאן בהקדם. אם נוח לך, אפשר גם לכתוב ישירות: @HFitjourney`)

  return new Response('ok')
})
