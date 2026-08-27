/**
 * intake-form — שאלון קליטה מדף הנחיתה (ציבורי).
 * מקבל את התשובות + PDF (base64) שנוצר בדפדפן, שומר ב-DB וב-Storage,
 * ושולח מייל למאמן עם כל התשובות + קישור להורדת ה-PDF.
 *
 * ה-PDF נוצר בצד הלקוח (הדפדפן מרנדר עברית נכון), וההעלאה נעשית כאן עם
 * service_role — כך שאין צורך לפתוח הרשאות כתיבה ל-anon.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SB_URL') ?? Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY  = Deno.env.get('ADMIN_DB_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WEB3FORMS_KEY = Deno.env.get('WEB3FORMS_KEY') ?? ''
const NOTIFY_EMAIL  = Deno.env.get('INTAKE_NOTIFY_EMAIL') ?? 'halel1201@gmail.com'
const RESEND_KEY    = Deno.env.get('RESEND_API_KEY') ?? ''
/* כתובת השולח חייבת להיות בדומיין מאומת אצל ספק המייל. ברירת
   המחדל היא דומיין הבדיקה שלו — עובד מיד, בלי הגדרת DNS. */
const MAIL_FROM     = Deno.env.get('INTAKE_MAIL_FROM') ?? 'Fit Journey <onboarding@resend.dev>'
const BUCKET = 'client-files'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

/* מייל ממותג FJ. HTML למייל אינו HTML לדפדפן: טבלאות ולא flex,
   סגנון בשורה ולא גיליון, ורוחב קבוע — אחרת לקוחות מייל שוברים
   את הפריסה. הכותרת כהה עם כתום כמו המותג, והגוף בהיר כי מיילים
   כהים נשברים במצב לילה של ג׳ימייל. */
function esc(v: unknown) {
  return String(v ?? '').replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))
}

function buildIntakeEmailHtml(o: {
  name: string; phone: string; email: string; planLabel: string; payRef: string
  proofUrl: string; pdfUrl: string; answers: Record<string, string>
}) {
  const row = (q: string, a: string, i: number) => `
    <tr>
      <td style="padding:10px 14px;border-bottom:1px solid #eee;color:#666;font-size:13px;width:42%;vertical-align:top;">
        ${i + 1}. ${esc(q)}</td>
      <td style="padding:10px 14px;border-bottom:1px solid #eee;color:#111;font-size:14px;font-weight:600;">
        ${esc(a) || '&mdash;'}</td>
    </tr>`

  const chip = (label: string, value: string) => value ? `
    <td style="padding:0 6px 8px 0;">
      <table cellpadding="0" cellspacing="0" style="background:#fff5ec;border:1px solid #ffd0a8;border-radius:8px;">
        <tr><td style="padding:7px 12px;font-size:12px;color:#8a4b00;">
          <span style="color:#b06a1a;">${esc(label)}</span> <b style="color:#7a3d00;">${esc(value)}</b>
        </td></tr></table></td>` : ''

  return `<!doctype html><html dir="rtl" lang="he"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1"></head>
  <body style="margin:0;padding:0;background:#f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:24px 12px;">
    <tr><td align="center">
      <table width="620" cellpadding="0" cellspacing="0" style="width:620px;max-width:100%;background:#ffffff;
        border-radius:16px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;
        box-shadow:0 2px 12px rgba(0,0,0,0.08);">

        <tr><td style="background:#0d0d0f;padding:22px 24px;border-bottom:4px solid #FF6B00;">
          <div style="font-size:24px;font-weight:900;color:#ffffff;letter-spacing:0.5px;">
            FIT <span style="color:#FF6B00;">JOURNEY</span></div>
          <div style="font-size:13px;color:#9aa0a6;margin-top:4px;">שאלון קליטה חדש</div>
        </td></tr>

        <tr><td style="padding:20px 24px 6px;">
          <div style="font-size:20px;font-weight:900;color:#111;">${esc(o.name)}</div>
          <table cellpadding="0" cellspacing="0" style="margin-top:12px;"><tr>
            ${chip('טלפון', o.phone)}${chip('אימייל', o.email)}
          </tr><tr>
            ${chip('מסלול', o.planLabel)}${chip('אסמכתא', o.payRef)}
          </tr></table>
        </td></tr>

        <tr><td style="padding:6px 24px 0;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:#fffbe8;border:1px solid #f0d98a;border-radius:10px;">
            <tr><td style="padding:12px 14px;font-size:13px;color:#7a5c00;line-height:1.6;">
              <b>⏳ ממתין לאימות תשלום</b><br>
              ${o.proofUrl
                ? `אישור התשלום צורף — <a href="${esc(o.proofUrl)}" style="color:#b45309;">פתח את הצילום</a>`
                : '📲 לא צורף צילום — המתאמן נתבקש לשלוח בוואטסאפ. אמת מול האסמכתא.'}
              <br>לאשר בפאנל לפני תחילת העבודה.
            </td></tr></table>
        </td></tr>

        <tr><td style="padding:18px 24px 4px;font-size:13px;font-weight:900;color:#FF6B00;">התשובות</td></tr>
        <tr><td style="padding:0 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #eee;border-radius:10px;">
            ${Object.entries(o.answers).map(([q, a], i) => row(q, a, i)).join('')}
          </table>
        </td></tr>

        <tr><td style="padding:18px 24px 24px;">
          ${o.pdfUrl ? `<a href="${esc(o.pdfUrl)}" style="display:inline-block;padding:11px 20px;
            background:#FF6B00;color:#fff;text-decoration:none;border-radius:9px;font-weight:900;
            font-size:14px;">📄 השאלון כ-PDF</a>` :
            `<div style="font-size:12px;color:#888;">ה-PDF לא נוצר אצל הממלא — אפשר להפיק אותו
             מהפאנל בכפתור "הצג והדפס".</div>`}
        </td></tr>

        <tr><td style="background:#fafafa;border-top:1px solid #eee;padding:14px 24px;
          font-size:11px;color:#999;">הודעה אוטומטית ממערכת Fit Journey</td></tr>
      </table>
    </td></tr></table></body></html>`
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'method' }, 405)

  try {
    const body = await req.json()
    const name = String(body.full_name || '').trim()
    if (!name) return json({ error: 'שם מלא הוא שדה חובה' }, 400)

    const answers: Record<string, string> = body.answers && typeof body.answers === 'object' ? body.answers : {}
    const phone = String(body.phone || '').trim()
    const email = String(body.email || '').trim()

    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // 1. שמירת השאלון — תמיד 'ממתין לאימות'; המאמן מאמת ידנית בפאנל
    const planLabel = String(body.plan_label || '').trim()
    const payRef    = String(body.payment_ref || '').trim()
    const amount    = (planLabel.match(/([\d,]+)\s*₪/) || [])[1]?.replace(/,/g, '')
    const { data: row, error: insErr } = await admin.from('intake_forms')
      .insert({
        full_name: name, phone: phone || null, email: email || null, answers,
        plan_label: planLabel || null, payment_ref: payRef || null,
        payment_amount: amount ? Number(amount) : null,
        payment_status: 'pending',
      })
      .select('id').single()
    if (insErr) return json({ error: insErr.message }, 400)

    // 1b. צילום אישור התשלום
    let proofUrl = ''
    if (typeof body.proof_base64 === 'string' && body.proof_base64.length > 100) {
      try {
        const m = body.proof_base64.match(/^data:(image\/[a-z+]+);base64,(.*)$/)
        if (m) {
          const ext = m[1].split('/')[1].replace('jpeg', 'jpg')
          const bin = Uint8Array.from(atob(m[2].replace(/\s/g, '')), (c) => c.charCodeAt(0))
          const p = `intake/proof_${row.id}_${Date.now()}.${ext}`
          const { error: pErr } = await admin.storage.from(BUCKET).upload(p, bin, { contentType: m[1], upsert: true })
          if (!pErr) {
            proofUrl = admin.storage.from(BUCKET).getPublicUrl(p).data.publicUrl
            await admin.from('intake_forms').update({ payment_proof_url: proofUrl }).eq('id', row.id)
          }
        }
      } catch (_e) { /* האסמכתא היא תוספת — אין להפיל את השליחה */ }
    }

    // 2. העלאת ה-PDF (base64 מהדפדפן) ל-Storage
    let pdfUrl = ''
    let pdfError = ''
    if (typeof body.pdf_base64 === 'string' && body.pdf_base64.length > 100) {
      try {
        const b64 = body.pdf_base64.replace(/^data:application\/pdf;base64,/, '').replace(/\s/g, '')
        const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
        // Storage דוחה מפתחות שאינם ASCII — לכן שם הקובץ הוא מזהה בלבד
        // (השם המלא של הממלא מופיע בתוך ה-PDF ובמייל).
        const path = `intake/${row.id}_${Date.now()}.pdf`
        const { error: upErr } = await admin.storage.from(BUCKET)
          .upload(path, bin, { contentType: 'application/pdf', upsert: true })
        if (upErr) { pdfError = upErr.message }
        else {
          pdfUrl = admin.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
          await admin.from('intake_forms').update({ pdf_url: pdfUrl }).eq('id', row.id)
        }
      } catch (e) { pdfError = String((e as Error)?.message || e) }
    }

    // 3. מייל למאמן — כל התשובות + קישור ל-PDF
    let mailSent = false, mailErr = '', mailVia = ''
    const emailHtml = buildIntakeEmailHtml({
      name, phone, email, planLabel, payRef, proofUrl, pdfUrl, answers,
    })

    /* ספק שתומך ב-HTML קודם; Web3Forms נשאר כנפילה חזרה כדי
       שהיעדר מפתח לא ישתיק את ההתראה לגמרי. */
    if (RESEND_KEY) {
      try {
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${RESEND_KEY}` },
          body: JSON.stringify({
            from: MAIL_FROM,
            to: [NOTIFY_EMAIL],
            subject: `📋 שאלון קליטה (ממתין לאימות) — ${name}`,
            html: emailHtml,
          }),
        })
        if (r.ok) { mailSent = true; mailVia = 'resend' }
        else { mailErr = `resend ${r.status}: ${(await r.text()).slice(0, 200)}` }
      } catch (e) { mailErr = 'resend: ' + String((e as Error)?.message || e) }
    }

    if (!mailSent && WEB3FORMS_KEY) {
      const lines = [
        `שאלון קליטה חדש — ${name}`,
        '⏳ ממתין לאימות תשלום — לאשר בפאנל לפני תחילת העבודה',
        '',
        planLabel ? `מסלול: ${planLabel}` : '',
        payRef ? `אסמכתא: ${payRef}` : '',
        proofUrl ? `🧾 אישור התשלום: ${proofUrl}` : '📲 לא צורף צילום — המתאמן נתבקש לשלוח בוואטסאפ. אמת מול האסמכתא.',
        '',
        phone ? `טלפון: ${phone}` : '',
        email ? `אימייל: ${email}` : '',
        '',
        ...Object.entries(answers).map(([q, a]) => `• ${q}\n  ${a || '—'}`),
        '',
        pdfUrl ? `📄 השאלון כ-PDF: ${pdfUrl}` : '(PDF לא נוצר)',
      ].filter(Boolean)
      try {
        await fetch('https://api.web3forms.com/submit', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({
            access_key: WEB3FORMS_KEY,
            subject: `📋 שאלון קליטה (ממתין לאימות תשלום) — ${name}`,
            from_name: 'Fit Journey — שאלון קליטה',
            email: NOTIFY_EMAIL,
            message: lines.join('\n'),
          }),
        })
        mailSent = true; mailVia = 'web3forms'
      } catch (e) {
        /* המייל הוא התראה בלבד — הנתונים כבר נשמרו. אבל שקט מוחלט
           כאן הוא מה שגרם ל"מילאתי ולא הגיע": צריך לדעת שהוא נכשל. */
        mailErr = String((e as Error)?.message || e)
      }
    }

    return json({
      ok: true, id: row.id, pdf_url: pdfUrl, pdf_error: pdfError || undefined,
      /* mail_sent=false פירושו שהשאלון נשמר אך ההתראה לא יצאה —
         בדרך כלל כי מפתח שירות המייל אינו מוגדר. */
      mail_sent: mailSent,
      mail_via: mailVia || undefined,
      /* הסיבה שה-PDF נכשל אצל הממלא — נשלחת מהדפדפן כדי שלא
         נגלה חודש אחרי שאין קבצים ולא נדע למה. */
      pdf_client_error: String(body.pdf_client_error || '') || undefined,
      mail_error: mailErr || (WEB3FORMS_KEY ? undefined : 'מפתח שירות המייל אינו מוגדר'),
    })
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500)
  }
})
