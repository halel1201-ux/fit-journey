/**
 * telegram-shop — בוט ההזמנות של החנות.
 *
 * למה בוט: טלגרם לא מאפשר להכניס טקסט מראש לשיחה בין שני אנשים, ולכן
 * רק קישור לבוט יכול לשאת את זהות המוצר.
 *
 * הזרימה — ארבעה שלבים, ובכולם ההזמנה כבר שמורה כטיוטה:
 *   /start p12  →  מאשר מוצר ומחיר
 *   referrer    →  "מי הפנה אותך?" (כפתורים) — נשאל ראשון בכוונה:
 *                  זו לחיצה אחת, וזה הנתון שמזכה בעמלה. אילו נשאל
 *                  אחרון, כל נוטש היה לוקח איתו את שיוך העמלה.
 *   details     →  שם, טלפון וכתובת בהודעה אחת — במקום ארבע שאלות
 *                  שכל אחת מהן הזדמנות לנטוש.
 *   payment     →  אמצעי תשלום (כפתורים)
 *   confirm     →  סיכום, ואז אישור או תיקון
 *
 * המחיר ואחוז העמלה מצולמים בהזמנה ולא נקראים מאוחר יותר: שינוי מחיר
 * או שינוי חוזה אסור שישנו הזמנות שכבר בוצעו.
 *
 * פריסה: verify_jwt=false — טלגרם אינו שולח JWT. האימות נעשה דרך
 * secret_token שטלגרם מצרף לכל קריאה.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const BOT_TOKEN   = Deno.env.get('TG_BOT_TOKEN') ?? ''
const OWNER_ID    = Deno.env.get('TG_OWNER_ID') ?? ''
const HOOK_SECRET = Deno.env.get('TG_WEBHOOK_SECRET') ?? ''
const SB_URL      = Deno.env.get('SB_URL') ?? Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('ADMIN_DB_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const CONTACT     = Deno.env.get('TG_CONTACT') ?? 'HFitjourney'

/* אמצעי התשלום שמוצעים ללקוח. שינוי כאן משנה את הכפתורים מיד. */
const PAYMENTS = ['ביט', 'העברה בנקאית', 'מזומן במסירה']

const sb = createClient(SB_URL, SERVICE_KEY)

const tg = (method: string, body: unknown) =>
  fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }).then(r => r.json()).catch(() => null)

const esc = (s: unknown) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

const send = (chat_id: number | string, text: string, extra: Record<string, unknown> = {}) =>
  tg('sendMessage', { chat_id, text, parse_mode: 'HTML', disable_web_page_preview: true, ...extra })

const kb = (rows: Array<Array<{ text: string; data: string }>>) =>
  ({ reply_markup: { inline_keyboard: rows.map(r => r.map(b => ({ text: b.text, callback_data: b.data }))) } })

const ils = (n: unknown) => Number(n ?? 0).toLocaleString('he-IL')

/* ── שאלות השלבים ── */

async function askReferrer(chatId: number, order: any) {
  /* רשימת הפרזנטורים נבנית מהמסד ולא קשיחה בקוד — הוספה או כיבוי
     בפאנל משנים את הכפתורים בלי לגעת בפונקציה. מוצגים רק פעילים
     שמשווקים את החנות. */
  const { data } = await sb.from('presenters')
    .select('id,name,pct').eq('active', true).in('markets', ['shop', 'both']).order('name')
  const rows = (data || []).map((p: any) => [{ text: p.name, data: `ref:${p.id}` }])
  rows.push([{ text: 'אף אחד / הגעתי לבד', data: 'ref:none' }])
  await send(chatId,
    `<b>${esc(order.product_name)}</b> · ${ils(order.product_price)} ₪\n` +
    (order.qty > 1 ? `כמות: ${order.qty}\n` : '') +
    `\nמי הפנה אותך אלינו?`, kb(rows))
}

const askDetails = (chatId: number) => send(chatId,
  'מעולה 🙌\n\nשלח בהודעה <b>אחת</b> את פרטי המשלוח:\n\n' +
  '<code>שם מלא\nטלפון\nכתובת מלאה + עיר</code>\n\n' +
  'לדוגמה:\n<i>ישראל כהן\n052-1234567\nהרצל 15 דירה 4, תל אביב</i>')

const askPayment = (chatId: number) => send(chatId, 'איך נוח לך לשלם?',
  kb(PAYMENTS.map(p => [{ text: p, data: `pay:${p}` }])))

const summary = (o: any) =>
  `<b>סיכום ההזמנה</b>\n\n` +
  `🧪 ${esc(o.product_name)} · ${ils(o.product_price)} ₪${o.qty > 1 ? ` × ${o.qty}` : ''}\n` +
  `👤 ${esc(o.customer_name || '—')}\n📞 ${esc(o.customer_phone || '—')}\n` +
  `📍 ${esc(o.address || '—')}\n💳 ${esc(o.payment_method || '—')}\n` +
  (o.presenter_name ? `🎤 הופנה ע״י ${esc(o.presenter_name)}\n` : '') +
  `\n<b>סה״כ: ${ils(Number(o.product_price || 0) * (o.qty || 1))} ₪</b>`

const askConfirm = (chatId: number, o: any) => send(chatId,
  summary(o) + '\n\nהכל נכון?',
  kb([[{ text: '✅ אישור ההזמנה', data: 'ok' }], [{ text: '✏️ תיקון הפרטים', data: 'fix' }]]))

/* ── עזרים ── */

const openOrder = async (chatId: number) => {
  const { data } = await sb.from('shop_orders').select('*')
    .eq('tg_chat_id', chatId).eq('status', 'draft')
    .order('created_at', { ascending: false }).limit(1).maybeSingle()
  return data
}
const setOrder = (id: number, patch: Record<string, unknown>) =>
  sb.from('shop_orders').update(patch).eq('id', id)

/* ── טיפול בהודעת טקסט ── */

async function onText(chatId: number, text: string, from: any) {
  if (text === '/id') {
    await send(chatId, `מזהה הצ'אט שלך:\n<code>${chatId}</code>`)
    return
  }

  if (text.startsWith('/start')) {
    const m = text.slice(6).trim().match(/^p(\d{1,18})$/)
    if (!m) {
      await send(chatId, `היי 👋\nלהזמנה בחר מוצר בקטלוג ולחץ "להזמנה".\nלשאלות: @${CONTACT}`)
      return
    }
    const { data: prod } = await sb.from('shop_products')
      .select('id,name,price,in_stock,visible').eq('id', Number(m[1])).maybeSingle()
    if (!prod || prod.visible === false) {
      await send(chatId, 'המוצר לא נמצא בקטלוג. ייתכן שהוסר.\nלשאלות: @' + CONTACT)
      return
    }
    if (prod.in_stock === false) {
      await send(chatId, `<b>${esc(prod.name)}</b> אזל מהמלאי כרגע 😕\nכתוב לי ואעדכן כשיחזור: @${CONTACT}`)
      return
    }
    /* טיוטה פתוחה קודמת מבוטלת — לקוח שהתחיל הזמנה אחרת ולא סיים
       לא אמור להיתקע עם שני תהליכים במקביל. */
    const prev = await openOrder(chatId)
    if (prev) await setOrder(prev.id, { status: 'cancelled', note: 'הוחלף בהזמנה חדשה' })

    const { data: order } = await sb.from('shop_orders').insert({
      tg_chat_id: chatId, tg_username: from?.username ?? null,
      tg_name: [from?.first_name, from?.last_name].filter(Boolean).join(' ') || null,
      product_id: prod.id, product_name: prod.name, product_price: prod.price,
      step: 'referrer',
    }).select('*').single()
    await askReferrer(chatId, order)
    return
  }

  const order = await openOrder(chatId)
  if (!order) {
    await send(chatId, `להזמנה חדשה בחר מוצר בקטלוג ולחץ "להזמנה" 🧪\nלשאלות: @${CONTACT}`)
    return
  }

  if (order.step === 'details') {
    /* הודעה אחת עם שם, טלפון וכתובת. הטלפון הוא העוגן: בלעדיו אין
       דרך ליצור קשר, ולכן זו הבדיקה היחידה שחוסמת. */
    const phone = (text.match(/0\d[\d\- ]{7,}\d/) || [])[0]?.replace(/[\s-]/g, '')
    if (!phone) {
      await send(chatId, 'לא מצאתי מספר טלפון בהודעה 🤔\nשלח שוב וכלול טלפון ליצירת קשר.')
      return
    }
    const lines = text.split('\n').map(l => l.trim()).filter(Boolean)
    const name = lines.find(l => !/\d/.test(l)) || lines[0] || ''
    const addr = lines.filter(l => l !== name && !l.replace(/[\s-]/g, '').includes(phone)).join(', ')
    await setOrder(order.id, {
      customer_name: name.slice(0, 120),
      customer_phone: phone,
      address: (addr || text).slice(0, 400),
      step: 'payment',
    })
    await askPayment(chatId)
    return
  }

  if (order.step === 'payment') { await askPayment(chatId); return }
  if (order.step === 'referrer') { await askReferrer(chatId, order); return }
  if (order.step === 'confirm') { await askConfirm(chatId, order); return }
}

/* ── טיפול בלחיצת כפתור ── */

async function onCallback(cq: any) {
  const chatId = cq.message?.chat?.id
  const data = String(cq.data || '')
  await tg('answerCallbackQuery', { callback_query_id: cq.id })   // מפסיק את סימן הטעינה
  if (!chatId) return

  const order = await openOrder(chatId)
  if (!order) { await send(chatId, 'ההזמנה הזו כבר נסגרה. לחץ "להזמנה" בקטלוג כדי להתחיל מחדש.'); return }

  if (data.startsWith('ref:')) {
    const val = data.slice(4)
    let patch: Record<string, unknown> = { step: 'details', presenter_id: null, presenter_name: null,
                                           commission_pct: null, commission_amount: null }
    if (val !== 'none') {
      const { data: p } = await sb.from('presenters')
        .select('id,name,pct').eq('id', Number(val)).eq('active', true).maybeSingle()
      if (p) {
        /* השם והאחוז נשמרים בשורת ההזמנה ולא רק כהפניה: שינוי החוזה
           או שינוי שם בעתיד אסור שישנה עסקאות שכבר בוצעו. */
        const pct = Number(p.pct || 0)
        patch = {
          step: 'details', presenter_id: p.id, presenter_name: p.name,
          commission_pct: pct,
          commission_amount: Math.round(Number(order.product_price || 0) * (order.qty || 1) * pct) / 100,
        }
      }
    }
    await setOrder(order.id, patch)
    await askDetails(chatId)
    return
  }

  if (data.startsWith('pay:')) {
    await setOrder(order.id, { payment_method: data.slice(4), step: 'confirm' })
    await askConfirm(chatId, { ...order, payment_method: data.slice(4) })
    return
  }

  if (data === 'fix') {
    await setOrder(order.id, { step: 'details' })
    await askDetails(chatId)
    return
  }

  if (data === 'ok') {
    await setOrder(order.id, { status: 'submitted', step: 'done', submitted_at: new Date().toISOString() })
    const { data: full } = await sb.from('shop_orders').select('*').eq('id', order.id).maybeSingle()
    await send(chatId, '✅ ההזמנה נקלטה!\n\nניצור איתך קשר בהקדם לתיאום התשלום והמשלוח.\nתודה 🙏')

    if (OWNER_ID && full) {
      const u = full.tg_username ? '@' + full.tg_username : null
      await send(OWNER_ID,
        `🛒 <b>הזמנה חדשה #${full.id}</b>\n\n` + summary(full) +
        `\n\n👤 ${esc(full.tg_name || '')}${u ? ` (${esc(u)})` : ''}` +
        (full.commission_amount ? `\n💰 עמלה: ${ils(full.commission_amount)} ₪ (${full.commission_pct}%)` : '') +
        (u ? '' : '\n⚠️ ללקוח אין שם משתמש — צור קשר בטלפון שלמעלה.'),
        u ? { reply_markup: { inline_keyboard: [[{ text: `💬 שיחה עם ${u}`, url: `https://t.me/${full.tg_username}` }]] } } : {})
    }
    return
  }
}

Deno.serve(async (req) => {
  if (HOOK_SECRET && req.headers.get('x-telegram-bot-api-secret-token') !== HOOK_SECRET)
    return new Response('forbidden', { status: 403 })
  if (req.method !== 'POST') return new Response('ok')

  let update: any
  try { update = await req.json() } catch { return new Response('ok') }

  /* טלגרם שולח שוב עדכון שלא נענה מהר. המפתח הראשי חוסם עיבוד כפול
     — בלעדיו לחיצת אישור אחת הייתה יוצרת שתי הזמנות ושתי עמלות. */
  if (update?.update_id != null) {
    const { error } = await sb.from('tg_updates').insert({ update_id: update.update_id })
    if (error) return new Response('ok')          // כבר טופל
  }

  try {
    if (update.callback_query) await onCallback(update.callback_query)
    else {
      const msg = update.message ?? update.edited_message
      const chatId = msg?.chat?.id
      const text = String(msg?.text ?? '').trim()
      if (chatId && text) await onText(chatId, text, msg.from)
    }
  } catch (e) {
    console.error('telegram-shop', e)
    /* לא מחזירים שגיאה לטלגרם: הוא היה שולח שוב ושוב את אותו עדכון. */
  }
  return new Response('ok')
})
