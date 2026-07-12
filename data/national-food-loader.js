/**
 * Loads the Israeli National Nutrition Database (Tzameret, Ministry of Health)
 * into the food_reference table. Source: data.gov.il CKAN datastore, resource
 * c3cb0630-0650-46c1-a068-82d575c094b2 ("ingredients + recipes, nutrition per 100g").
 * ~4,624 items. Re-run to refresh. Requires the Supabase service key in SB_SECRET.
 *
 *   SB_SECRET=... node national-food-loader.js
 */
const RID = 'c3cb0630-0650-46c1-a068-82d575c094b2'
const REF = 'luwknflmhvcxgifzxgrk'
const SECRET = process.env.SB_SECRET
const B = `https://${REF}.supabase.co/rest/v1/food_reference`
const num = v => { const n = parseFloat(v); return isFinite(n) ? n : null }

;(async () => {
  if (!SECRET) { console.error('set SB_SECRET'); process.exit(1) }
  // 1. pull all records (paged)
  let all = [], off = 0, total = null
  while (true) {
    const u = `https://data.gov.il/api/3/action/datastore_search?resource_id=${RID}&limit=1000&offset=${off}&fields=shmmitzrach,english_name,food_energy,protein,carbohydrates,total_fat,total_dietary_fiber,sodium`
    const j = await (await fetch(u, { headers: { 'User-Agent': 'Mozilla/5.0' } })).json()
    if (!j.success) { console.error('CKAN fail at', off); break }
    total = j.result.total; all = all.concat(j.result.records); off += 1000
    if (all.length >= total || !j.result.records.length) break
  }
  // 2. clean
  const rows = []
  for (const r of all) {
    const name = (r.shmmitzrach || '').trim(); const kcal = num(r.food_energy)
    if (!name || kcal === null) continue
    rows.push({
      name, name_en: (r.english_name || '').trim() || null, kcal: Math.round(kcal),
      protein: Math.round((num(r.protein) || 0) * 10) / 10, carbs: Math.round((num(r.carbohydrates) || 0) * 10) / 10,
      fat: Math.round((num(r.total_fat) || 0) * 10) / 10, fiber: Math.round((num(r.total_dietary_fiber) || 0) * 10) / 10,
      sodium: Math.round(num(r.sodium) || 0),
    })
  }
  // 3. replace table contents (batched)
  const H = { apikey: SECRET, Authorization: 'Bearer ' + SECRET, 'Content-Type': 'application/json' }
  await fetch(B + '?id=gt.0', { method: 'DELETE', headers: H })
  for (let i = 0; i < rows.length; i += 1000) {
    const r = await fetch(B, { method: 'POST', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(rows.slice(i, i + 1000)) })
    if (!r.ok) { console.error('batch', i, 'fail', r.status); process.exit(1) }
  }
  console.log('loaded', rows.length, 'foods into food_reference')
})()
