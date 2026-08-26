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
const BUCKET = 'client-files'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

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
    if (WEB3FORMS_KEY) {
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
      } catch (_e) { /* המייל הוא התראה — הנתונים כבר נשמרו */ }
    }

    return json({ ok: true, id: row.id, pdf_url: pdfUrl, pdf_error: pdfError || undefined })
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500)
  }
})
