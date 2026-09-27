/* ═══ 📅 פגישות מאמן–מתאמן + סנכרון ליומן ═══
   קובץ משותף ל-coach.html ול-dashboard.html.

   הכל עטוף בפונקציה סגורה וחושף שם גלובלי אחד בלבד (FJMeet). הדפים
   מצהירים על עשרות const/let ברמה העליונה, והצהרה כפולה של אותו שם
   מקובץ נוסף זורקת SyntaxError שמשבית את כל הסקריפט של הדף.

   משתני הדף (sb, coachEmail, currentEmail, clientData) נקראים רק בזמן
   קריאה ורק בפונקציות של הצד הרלוונטי — מה שקיים בדף אחד לא קיים בשני.

   יומן: באפליקציה הנייטיבית קיים window.FJCalendar (גשר EventKit).
   הדף מוסר לו את כל רשימת האירועים הרצויה והוא מסנכרן — יוצר, מזיז,
   מוחק. בדפדפן אין גשר, ושם כל פגישה מקבלת קובץ .ics. */
(function () {
  const KIND = {
    in_person: { ic: '🤝', nm: 'פרונטלית', loc: 'כתובת',        ph: 'רחוב, עיר' },
    video:     { ic: '🎥', nm: 'וידאו',     loc: 'קישור לשיחה', ph: 'Zoom / Google Meet / WhatsApp' },
    phone:     { ic: '📞', nm: 'שיחה',      loc: 'טלפון',        ph: '050-0000000' },
  };
  const TOPICS = ['ניתוח התקדמות', 'בדיקת גוף וצילומים', 'עדכון תוכנית', 'שיחת היכרות'];
  const MIN = 60000, HOUR = 3600, DAY = 86400;

  const H = s => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const isUrl = s => /^https?:\/\/\S+$/i.test(String(s || '').trim());
  const pad = n => String(n).padStart(2, '0');

  function say(msg, err) {
    if (typeof toast === 'function') toast(msg, err ? 'err' : 'ok');
    else if (typeof showDashToast === 'function') showDashToast(msg);
  }
  function dayLabel(d) {
    const t = new Date(); t.setHours(0, 0, 0, 0);
    const x = new Date(d); x.setHours(0, 0, 0, 0);
    const diff = Math.round((x - t) / 864e5);
    if (diff === 0) return 'היום';
    if (diff === 1) return 'מחר';
    return d.toLocaleDateString('he-IL', { weekday: 'short', day: '2-digit', month: '2-digit' });
  }
  const timeLabel = d => d.toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
  const whenLabel = iso => { const d = new Date(iso); return dayLabel(d) + ' · ' + timeLabel(d); };

  /* טבלה שעוד לא נוצרה (לפני הרצת המיגרציה) היא לא תקלה — פשוט אין פגישות */
  const missingTable = e => e && (e.code === '42P01' || e.code === 'PGRST205' ||
    /coach_meetings/.test(e.message || '') && /(exist|find|schema)/i.test(e.message || ''));

  /* ════════════════════════ צד המאמן ════════════════════════ */
  const C = { email: null, list: [], editing: null, kind: 'video' };

  async function renderCoach(email) {
    C.email = email; C.editing = null;
    const wrap = document.getElementById('meetings-editor');
    if (!wrap) return;
    const { data, error } = await sb.from('coach_meetings').select('*')
      .eq('client_email', email).order('starts_at', { ascending: true });
    if (C.email !== email) return;               // המאמן כבר עבר למתאמן אחר
    if (error) {
      wrap.innerHTML = `<div style="color:#888;font-size:0.82rem;padding:6px 0;">${missingTable(error)
        ? 'פיצ׳ר הפגישות עוד לא הופעל במסד הנתונים.' : 'שגיאה בטעינת הפגישות — נסה שוב.'}</div>`;
      return;
    }
    C.list = data || [];
    paintCoach();
  }

  function paintCoach() {
    const wrap = document.getElementById('meetings-editor');
    if (!wrap) return;
    const now = Date.now();
    const upcoming = C.list.filter(m => m.status === 'scheduled' && Date.parse(m.starts_at) + m.duration_min * MIN > now);
    const past = C.list.filter(m => !upcoming.includes(m)).reverse().slice(0, 6);

    const row = (m, isPast) => {
      const k = KIND[m.kind] || KIND.video;
      const dim = m.status === 'cancelled' ? 'opacity:.45;text-decoration:line-through;' : (isPast ? 'opacity:.7;' : '');
      const badge = m.status === 'done' ? '<span style="color:#4ade80;font-weight:800;">✓ בוצעה</span>'
                  : m.status === 'cancelled' ? '<span style="color:#f87171;font-weight:800;">בוטלה</span>' : '';
      const acts = m.status !== 'scheduled' ? '' : isPast
        ? `<button class="btn-sm btn-outline" onclick="FJMeet.done(${m.id})">✓ בוצעה</button>`
        : `<button class="btn-sm btn-outline" onclick="FJMeet.openForm(${m.id})">✏️</button>
           <button class="btn-sm btn-red" onclick="FJMeet.cancel(${m.id})">✕</button>`;
      return `<div style="display:flex;align-items:center;gap:10px;padding:10px 12px;margin-bottom:7px;border-radius:10px;
                  background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.07);">
        <div style="font-size:1.3rem;flex:none;">${k.ic}</div>
        <div style="flex:1;min-width:0;${dim}">
          <div style="font-weight:800;font-size:0.88rem;">${H(whenLabel(m.starts_at))} <span style="color:#888;font-weight:600;font-size:0.76rem;">· ${m.duration_min} דק׳ · ${k.nm}</span></div>
          ${m.topic ? `<div style="font-size:0.78rem;color:#bbb;margin-top:2px;">${H(m.topic)}</div>` : ''}
          ${m.location ? `<div style="font-size:0.72rem;color:#777;margin-top:2px;direction:${isUrl(m.location) ? 'ltr;text-align:right' : 'rtl'};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${H(m.location)}</div>` : ''}
        </div>
        <div style="display:flex;gap:5px;flex:none;align-items:center;">${badge}${acts}</div>
      </div>`;
    };

    wrap.innerHTML = `
      ${upcoming.length ? upcoming.map(m => row(m, false)).join('')
        : '<div style="color:#777;font-size:0.82rem;padding:4px 0 10px;">אין פגישות קרובות.</div>'}
      <button class="btn-sm btn-orange" style="margin-top:4px;" onclick="FJMeet.openForm()">➕ קבע פגישה</button>
      <div id="fjm-form" style="display:none;margin-top:12px;"></div>
      ${past.length ? `<details style="margin-top:12px;"><summary style="cursor:pointer;color:#888;font-size:0.8rem;font-weight:700;">היסטוריה (${past.length})</summary>
        <div style="margin-top:8px;">${past.map(m => row(m, true)).join('')}</div></details>` : ''}`;
  }

  function openForm(id) {
    const m = id ? C.list.find(x => x.id === id) : null;
    C.editing = m ? m.id : null;
    C.kind = m ? m.kind : 'video';
    let date, time;
    if (m) {
      const d = new Date(m.starts_at);
      date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
      time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    } else {                                     // ברירת מחדל: מחר ב-18:00
      const d = new Date(Date.now() + 864e5);
      date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
      time = '18:00';
    }
    const dur = m ? m.duration_min : 30;
    const f = document.getElementById('fjm-form');
    const inp = 'width:100%;padding:9px 10px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:8px;color:#fff;font-family:Heebo,sans-serif;font-size:0.88rem;color-scheme:dark;';
    const lbl = 'display:block;font-size:0.74rem;color:#999;font-weight:700;margin-bottom:4px;';
    f.innerHTML = `
      <div style="padding:14px;border-radius:12px;background:rgba(255,107,0,0.05);border:1px solid rgba(255,107,0,0.25);">
        <div style="font-weight:900;font-size:0.9rem;margin-bottom:10px;">${m ? '✏️ עדכון פגישה' : '📅 פגישה חדשה'}</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:9px;">
          <div><label style="${lbl}">תאריך</label><input id="fjm-date" type="date" value="${date}" style="${inp}"></div>
          <div><label style="${lbl}">שעה</label><input id="fjm-time" type="time" step="300" value="${time}" style="${inp}"></div>
        </div>
        <label style="${lbl}margin-top:10px;">סוג הפגישה</label>
        <div id="fjm-kinds" style="display:flex;gap:6px;">
          ${Object.entries(KIND).map(([k, v]) => `<button type="button" data-k="${k}" onclick="FJMeet.setKind('${k}')"
            style="flex:1;padding:8px 4px;border-radius:9px;cursor:pointer;font-family:Heebo,sans-serif;font-weight:800;font-size:0.8rem;"
            >${v.ic} ${v.nm}</button>`).join('')}
        </div>
        <div style="display:grid;grid-template-columns:1fr 2fr;gap:9px;margin-top:10px;">
          <div><label style="${lbl}">משך</label>
            <select id="fjm-dur" style="${inp}">${[15, 20, 30, 45, 60, 90].map(n =>
              `<option value="${n}" ${n === dur ? 'selected' : ''}>${n} דק׳</option>`).join('')}</select></div>
          <div><label style="${lbl}" id="fjm-loc-lbl"></label>
            <input id="fjm-loc" type="text" maxlength="300" value="${H(m ? m.location : '')}" style="${inp}"></div>
        </div>
        <label style="${lbl}margin-top:10px;">מטרת הפגישה</label>
        <input id="fjm-topic" type="text" maxlength="200" value="${H(m ? m.topic : '')}" placeholder="למשל: ניתוח התקדמות" style="${inp}">
        <div style="display:flex;flex-wrap:wrap;gap:5px;margin-top:6px;">
          ${TOPICS.map(t => `<button type="button" onclick="FJMeet.chip(this)" style="padding:4px 10px;border-radius:14px;cursor:pointer;
            background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);color:#ccc;font-family:Heebo,sans-serif;font-size:0.72rem;">${t}</button>`).join('')}
        </div>
        <label style="display:flex;align-items:center;gap:7px;margin-top:12px;font-size:0.8rem;color:#ccc;cursor:pointer;">
          <input id="fjm-notify" type="checkbox" checked style="width:16px;height:16px;accent-color:#FF6B00;"> שלח למתאמן הודעה בצ׳אט
        </label>
        <div style="display:flex;gap:8px;margin-top:12px;">
          <button class="btn-sm btn-orange" id="fjm-save" style="flex:1;padding:10px;" onclick="FJMeet.save()">💾 ${m ? 'עדכן' : 'קבע פגישה'}</button>
          <button class="btn-sm btn-outline" onclick="FJMeet.closeForm()">ביטול</button>
        </div>
      </div>`;
    f.style.display = 'block';
    setKind(C.kind);
    f.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  function setKind(k) {
    C.kind = k;
    document.querySelectorAll('#fjm-kinds [data-k]').forEach(b => {
      const on = b.dataset.k === k;
      b.style.background = on ? 'rgba(255,107,0,0.18)' : 'rgba(255,255,255,0.04)';
      b.style.border = '1px solid ' + (on ? 'rgba(255,107,0,0.6)' : 'rgba(255,255,255,0.12)');
      b.style.color = on ? '#FF8A1E' : '#aaa';
    });
    const l = document.getElementById('fjm-loc-lbl'), i = document.getElementById('fjm-loc');
    if (l) l.textContent = KIND[k].loc + ' (לא חובה)';
    if (i) { i.placeholder = KIND[k].ph; i.style.direction = k === 'in_person' ? 'rtl' : 'ltr'; i.style.textAlign = 'right'; }
  }

  function chip(btn) { const t = document.getElementById('fjm-topic'); if (t) t.value = btn.textContent.trim(); }
  function closeForm() { const f = document.getElementById('fjm-form'); if (f) { f.style.display = 'none'; f.innerHTML = ''; } C.editing = null; }

  async function notifyClient(email, text) {
    try {
      await sb.from('messages').insert({ coach_email: coachEmail, client_email: email, sender_email: coachEmail, content: text });
    } catch (e) { /* ההודעה היא תוספת — הפגישה עצמה כבר נשמרה */ }
  }
  function describe(m) {
    const k = KIND[m.kind] || KIND.video;
    let s = `${whenLabel(m.starts_at)} (${k.nm}, ${m.duration_min} דק׳)`;
    if (m.topic) s += ` — ${m.topic}`;
    if (m.location) s += `\n${k.loc}: ${m.location}`;
    return s;
  }

  async function save() {
    const date = document.getElementById('fjm-date').value;
    const time = document.getElementById('fjm-time').value;
    if (!date || !time) { say('בחר תאריך ושעה', true); return; }
    const start = new Date(`${date}T${time}`);
    if (isNaN(start)) { say('תאריך או שעה לא תקינים', true); return; }
    if (start.getTime() < Date.now() - 5 * MIN) { say('אי אפשר לקבוע פגישה בעבר', true); return; }
    const dur = parseInt(document.getElementById('fjm-dur').value, 10) || 30;
    const row = {
      starts_at: start.toISOString(), duration_min: dur, kind: C.kind,
      location: document.getElementById('fjm-loc').value.trim() || null,
      topic: document.getElementById('fjm-topic').value.trim() || null,
    };
    const notify = document.getElementById('fjm-notify').checked;

    /* חפיפה עם פגישה אחרת של המאמן באותו יום — גם של מתאמנים אחרים */
    const d0 = new Date(start); d0.setHours(0, 0, 0, 0);
    const { data: sameDay } = await sb.from('coach_meetings').select('id,client_email,starts_at,duration_min')
      .eq('coach_email', coachEmail).eq('status', 'scheduled')
      .gte('starts_at', d0.toISOString()).lt('starts_at', new Date(d0.getTime() + 864e5).toISOString());
    const s1 = start.getTime(), e1 = s1 + dur * MIN;
    const clash = (sameDay || []).find(o => o.id !== C.editing &&
      Date.parse(o.starts_at) < e1 && Date.parse(o.starts_at) + o.duration_min * MIN > s1);
    if (clash) {
      const who = (typeof clients !== 'undefined' && clients.find(c => c.email === clash.client_email)?.name) || clash.client_email;
      if (!confirm(`יש לך כבר פגישה עם ${who} ב-${timeLabel(new Date(clash.starts_at))}.\nלקבוע בכל זאת?`)) return;
    }

    const btn = document.getElementById('fjm-save'); if (btn) { btn.disabled = true; btn.textContent = '⏳ שומר...'; }
    const email = C.email, editing = C.editing;
    const beforeStart = editing ? (C.list.find(x => x.id === editing) || {}).starts_at : null;   // ערך, לא הפניה
    const res = editing
      ? await sb.from('coach_meetings').update(row).eq('id', editing).select().single()
      : await sb.from('coach_meetings').insert({ ...row, coach_email: coachEmail, client_email: email, status: 'scheduled' }).select().single();
    if (res.error) {
      if (btn) { btn.disabled = false; btn.textContent = '💾 נסה שוב'; }
      say(missingTable(res.error) ? 'פיצ׳ר הפגישות עוד לא הופעל במסד הנתונים' : 'שמירה נכשלה: ' + res.error.message, true);
      return;
    }
    if (notify) {
      const moved = beforeStart && Date.parse(beforeStart) !== Date.parse(res.data.starts_at);
      await notifyClient(email, editing
        ? (moved ? `📅 הפגישה שלנו עודכנה:\n${describe(res.data)}` : `📅 פרטי הפגישה עודכנו:\n${describe(res.data)}`)
        : `📅 קבעתי לנו פגישה:\n${describe(res.data)}\n\nהיא תופיע לך באפליקציה, ואפשר להוסיף אותה ליומן.`);
    }
    say(editing ? 'הפגישה עודכנה ✓' : 'הפגישה נקבעה ✓');
    await renderCoach(email);
  }

  async function cancel(id) {
    const m = C.list.find(x => x.id === id);
    if (!m || !confirm(`לבטל את הפגישה ב-${whenLabel(m.starts_at)}?`)) return;
    const { error } = await sb.from('coach_meetings').update({ status: 'cancelled' }).eq('id', id);
    if (error) { say('הביטול נכשל: ' + error.message, true); return; }
    await notifyClient(m.client_email, `❌ הפגישה שלנו ב-${whenLabel(m.starts_at)} בוטלה.`);
    say('הפגישה בוטלה');
    await renderCoach(C.email);
  }

  async function done(id) {
    const { error } = await sb.from('coach_meetings').update({ status: 'done' }).eq('id', id);
    if (error) { say('העדכון נכשל: ' + error.message, true); return; }
    await renderCoach(C.email);
  }

  /* ════════════════════════ צד המתאמן ════════════════════════ */
  const SYNC_KEY = 'fj_cal_sync', DISMISS_KEY = 'fj_cal_dismiss';
  const T = { list: [], hooked: false, lastSync: 0, syncing: false, again: false };
  const native = () => !!(window.FJCalendar && window.FJCalendar.native);
  const lsGet = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) {} };
  const syncOn = () => lsGet(SYNC_KEY) === '1';

  async function loadTraineeMeetings() {
    const { data, error } = await sb.from('coach_meetings').select('*')
      .eq('client_email', currentEmail).eq('status', 'scheduled')
      .gte('starts_at', new Date(Date.now() - 3 * 3600e3).toISOString())
      .order('starts_at', { ascending: true }).limit(8);
    if (error) return missingTable(error) ? [] : null;
    return (data || []).filter(m => Date.parse(m.starts_at) + m.duration_min * MIN > Date.now());
  }

  async function initTrainee() {
    if (typeof currentEmail === 'undefined' || !currentEmail) return;
    const list = await loadTraineeMeetings();
    T.list = list || [];
    await paintTrainee();
    syncCalendar();
    if (!T.hooked) {
      T.hooked = true;
      /* חזרה לאפליקציה מהרקע: רענון הכרטיס וסנכרון — פגישה שהמאמן
         קבע בינתיים נכנסת ליומן בלי שהמתאמן יעשה כלום */
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && Date.now() - T.lastSync > 60e3) initTrainee();
      });
    }
  }

  function actionFor(m) {
    const loc = String(m.location || '').trim();
    const a = (href, txt, ext) => `<a href="${H(href)}" ${ext ? 'target="_blank" rel="noopener"' : ''} style="flex:none;padding:7px 12px;border-radius:9px;
      background:linear-gradient(135deg,var(--orange,#FF6B00),#FF8C00);color:#fff;font-weight:800;font-size:0.76rem;text-decoration:none;">${txt}</a>`;
    if (m.kind === 'video' && isUrl(loc)) return a(loc, 'הצטרף', true);
    if (m.kind === 'phone' && loc) return a('tel:' + loc.replace(/[^\d+]/g, ''), 'התקשר');
    if (m.kind === 'in_person' && loc) return a('https://maps.apple.com/?q=' + encodeURIComponent(loc), 'ניווט', true);
    return '';
  }

  async function paintTrainee() {
    const box = document.getElementById('hl-meetings');
    if (!box) return;
    const cd = typeof clientData !== 'undefined' ? clientData : null;
    const hasOther = cd && (cd.checkin_day != null || cd.studio_owner_email);
    const nat = native();
    let status = null;
    if (nat) { try { status = (await window.FJCalendar.status()).status; } catch (e) {} }

    /* שורת היומן: באפליקציה — סנכרון אחד לכל האירועים; בדפדפן — אין */
    let calRow = '';
    if (nat) {
      if (syncOn() && status === 'granted') {
        calRow = `<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:10px;font-size:0.74rem;color:#4ade80;font-weight:700;">
          <span>✓ מסונכרן ליומן · תזכורת יום לפני</span>
          <button onclick="FJMeet.disableCalendar()" style="background:none;border:none;color:#777;font-family:Heebo,sans-serif;font-size:0.72rem;cursor:pointer;text-decoration:underline;">הפסק</button></div>`;
      } else if (syncOn() && status !== 'granted') {
        calRow = `<div style="margin-top:10px;font-size:0.74rem;color:#f87171;line-height:1.6;">הגישה ליומן בוטלה. אפשר להחזיר אותה ב<b>הגדרות ← Fit Journey ← יומנים</b>.</div>`;
      } else {
        calRow = `<button onclick="FJMeet.enableCalendar()" style="width:100%;margin-top:10px;padding:10px;border-radius:10px;cursor:pointer;
          background:rgba(255,255,255,0.05);border:1px solid rgba(255,107,0,0.4);color:var(--orange,#FF6B00);font-family:Heebo,sans-serif;font-weight:800;font-size:0.82rem;">
          📅 הוסף ליומן שלי — עם תזכורת יום לפני</button>`;
      }
    }

    if (!T.list.length) {
      /* אין פגישות: באפליקציה מציעים סנכרון פעם אחת (צ׳ק-אין / סטודיו),
         ובלי להציק — "לא עכשיו" מסתיר, וכשהסנכרון פעיל אין מה להציג */
      if (nat && hasOther && !syncOn() && lsGet(DISMISS_KEY) !== '1') {
        box.style.display = 'block';
        box.innerHTML = `<div style="background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:12px 14px;">
          <div style="display:flex;align-items:center;gap:10px;">
            <div style="font-size:1.4rem;">📅</div>
            <div style="flex:1;font-size:0.8rem;color:#ccc;line-height:1.5;"><b style="color:#fff;">הכל ביומן שלך</b><br>
              ${cd.checkin_day != null ? 'העדכון השבועי' : ''}${cd.checkin_day != null && cd.studio_owner_email ? ' ו' : ''}${cd.studio_owner_email ? 'שיעורי הסטודיו' : ''}, עם תזכורת מראש</div>
          </div>
          <div style="display:flex;gap:8px;margin-top:10px;">
            <button onclick="FJMeet.enableCalendar()" style="flex:1;padding:9px;border-radius:10px;border:none;cursor:pointer;
              background:linear-gradient(135deg,var(--orange,#FF6B00),#FF8C00);color:#fff;font-family:Heebo,sans-serif;font-weight:800;font-size:0.8rem;">הוסף ליומן</button>
            <button onclick="FJMeet.dismissCal()" style="padding:9px 14px;border-radius:10px;cursor:pointer;background:none;
              border:1px solid rgba(255,255,255,0.12);color:#888;font-family:Heebo,sans-serif;font-weight:700;font-size:0.8rem;">לא עכשיו</button>
          </div></div>`;
      } else { box.style.display = 'none'; box.innerHTML = ''; }
      return;
    }

    box.style.display = 'block';
    box.innerHTML = `<div style="background:linear-gradient(135deg,rgba(255,107,0,0.12),rgba(255,215,0,0.04));
        border:1px solid rgba(255,107,0,0.35);border-radius:16px;padding:14px 16px;">
      <div style="font-weight:900;font-size:0.92rem;margin-bottom:10px;">📅 ${T.list.length > 1 ? 'הפגישות שלי' : 'פגישה עם המאמן'}</div>
      ${T.list.map(m => {
        const k = KIND[m.kind] || KIND.video;
        return `<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid rgba(255,255,255,0.06);">
          <div style="font-size:1.25rem;flex:none;">${k.ic}</div>
          <div style="flex:1;min-width:0;">
            <div style="font-weight:800;font-size:0.86rem;">${H(whenLabel(m.starts_at))}</div>
            <div style="font-size:0.72rem;color:#aaa;">${k.nm} · ${m.duration_min} דק׳${m.topic ? ' · ' + H(m.topic) : ''}</div>
          </div>
          ${actionFor(m)}
          ${nat ? '' : `<button onclick="FJMeet.ics(${m.id})" title="הוסף ליומן" style="flex:none;padding:7px 10px;border-radius:9px;cursor:pointer;
            background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.14);color:#ddd;font-family:Heebo,sans-serif;font-weight:800;font-size:0.74rem;">➕ ליומן</button>`}
        </div>`;
      }).join('')}
      ${calRow}
    </div>`;
  }

  /* כל האירועים שאמורים להיות ביומן של המתאמן כרגע. מחזיר null אם
     טעינה כלשהי נכשלה — סנכרון עם רשימה חלקית היה מוחק מהיומן אירועים
     אמיתיים רק בגלל תקלת רשת. */
  async function collectEvents() {
    const cd = typeof clientData !== 'undefined' ? clientData : null;
    if (!cd) return null;
    const out = [];

    const meetings = await loadTraineeMeetings();
    if (meetings === null) return null;
    T.list = meetings;
    for (const m of meetings) {
      const k = KIND[m.kind] || KIND.video, start = Date.parse(m.starts_at), loc = String(m.location || '').trim();
      out.push({
        key: 'meet-' + m.id,
        title: `${k.ic} פגישה עם המאמן · ${k.nm}`,
        start, end: start + m.duration_min * MIN,
        location: m.kind === 'in_person' ? loc : (m.kind === 'phone' ? 'שיחת טלפון' : 'שיחת וידאו'),
        url: m.kind === 'video' && isUrl(loc) ? loc : undefined,
        notes: [m.topic, m.kind === 'phone' && loc ? 'טלפון: ' + loc : '', m.kind === 'video' && loc ? 'קישור: ' + loc : '',
                'נקבע ב-Fit Journey'].filter(Boolean).join('\n'),
        alarms: [-DAY, -HOUR],
      });
    }

    if (cd.studio_owner_email) {
      const { data: bk, error } = await sb.from('studio_bookings').select('id,slot_id,status')
        .eq('client_email', currentEmail).neq('status', 'cancelled');
      if (error) return null;
      const ids = (bk || []).map(b => b.slot_id);
      if (ids.length) {
        const [slotsR, typesR, studioR] = await Promise.all([
          sb.from('studio_slots').select('id,slot_start,slot_end,title,class_type_id,status').in('id', ids),
          sb.from('studio_class_types').select('id,name').eq('owner_email', cd.studio_owner_email),
          sb.from('studios').select('*').eq('owner_email', cd.studio_owner_email).maybeSingle(),
        ]);
        if (slotsR.error) return null;
        const slot = {}; (slotsR.data || []).forEach(s => slot[s.id] = s);
        const type = {}; (typesR.data || []).forEach(t => type[t.id] = t.name);
        const st = studioR.data || {};
        const place = [st.name, st.address].filter(Boolean).join(', ');
        for (const b of bk) {
          const s = slot[b.slot_id];
          if (!s || s.status === 'cancelled') continue;
          const start = Date.parse(s.slot_start);
          if (!(start > Date.now())) continue;
          const end = s.slot_end ? Date.parse(s.slot_end) : start + 60 * MIN;
          const cls = type[s.class_type_id] || s.title || 'שיעור';
          out.push({
            key: 'studio-' + b.id,
            title: `🏋️ ${cls}${st.name ? ' · ' + st.name : ''}`,
            start, end: end > start ? end : start + 60 * MIN,
            location: place || undefined,
            notes: 'שיעור בסטודיו — Fit Journey',
            alarms: [-DAY, -2 * HOUR],
          });
        }
      }
    }

    const day = cd.checkin_day;
    if (day != null && day >= 0 && day <= 6) {
      const d = new Date(); d.setHours(9, 0, 0, 0);
      d.setDate(d.getDate() + ((day - d.getDay() + 7) % 7));
      out.push({
        key: 'checkin',
        title: '📋 עדכון שבועי למאמן',
        start: d.getTime(), end: d.getTime() + 15 * MIN,
        notes: 'שקילה, צילומים ועדכון קצר למאמן באפליקציית Fit Journey',
        alarms: [0], weekly: true,
      });
    }
    return out;
  }

  async function syncCalendar() {
    if (!native() || !syncOn()) return null;
    if (T.syncing) { T.again = true; return null; }
    T.syncing = true;
    try {
      const { status } = await window.FJCalendar.status();
      if (status !== 'granted') return null;
      const events = await collectEvents();
      if (!events) return null;
      const r = await window.FJCalendar.sync(events);
      T.lastSync = Date.now();
      return r;
    } catch (e) { return null; }
    finally {
      T.syncing = false;
      if (T.again) { T.again = false; syncCalendar(); }
    }
  }

  async function enableCalendar() {
    if (!native()) return;
    let st = 'denied';
    try { st = (await window.FJCalendar.request()).status; } catch (e) {}
    if (st !== 'granted') {
      say(st === 'writeOnly' ? 'צריך גישה מלאה ליומן כדי לעדכן פגישות — הגדרות ← Fit Journey ← יומנים'
                             : 'אין גישה ליומן. אפשר לאשר ב: הגדרות ← Fit Journey ← יומנים');
      return;
    }
    lsSet(SYNC_KEY, '1');
    const r = await syncCalendar();
    await paintTrainee();
    say(r ? 'נוסף ליומן ✓ תקבל תזכורת יום לפני' : 'הסנכרון ליומן הופעל');
  }

  async function disableCalendar() {
    if (!confirm('להפסיק את הסנכרון ולמחוק מהיומן את האירועים שנוספו מכאן?')) return;
    lsSet(SYNC_KEY, null);
    lsSet(DISMISS_KEY, '1');
    try { if (native()) await window.FJCalendar.clear(); } catch (e) {}
    await paintTrainee();
    say('הסנכרון הופסק');
  }

  function dismissCal() { lsSet(DISMISS_KEY, '1'); paintTrainee(); }

  /* ── בדפדפן: קובץ .ics לכל פגישה (אייפון פותח "הוסף ליומן") ── */
  function ics(id) {
    const m = T.list.find(x => x.id === id);
    if (!m) return;
    const k = KIND[m.kind] || KIND.video, loc = String(m.location || '').trim();
    const start = Date.parse(m.starts_at), end = start + m.duration_min * MIN;
    const stamp = t => new Date(t).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const e = s => String(s || '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/,/g, '\\,').replace(/;/g, '\\;');
    const title = `פגישה עם המאמן · ${k.nm}`;
    const lines = [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Fit Journey//HE', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      `UID:fj-meet-${m.id}@fitjourney-net.com`, `DTSTAMP:${stamp(Date.now())}`,
      `DTSTART:${stamp(start)}`, `DTEND:${stamp(end)}`,
      `SUMMARY:${e(title)}`,
      loc ? `LOCATION:${e(m.kind === 'in_person' ? loc : (m.kind === 'phone' ? 'טלפון: ' + loc : loc))}` : '',
      `DESCRIPTION:${e([m.topic, 'נקבע ב-Fit Journey'].filter(Boolean).join('\n'))}`,
      m.kind === 'video' && isUrl(loc) ? `URL:${loc}` : '',
      'BEGIN:VALARM', 'TRIGGER:-P1D', 'ACTION:DISPLAY', `DESCRIPTION:${e(title)}`, 'END:VALARM',
      'BEGIN:VALARM', 'TRIGGER:-PT1H', 'ACTION:DISPLAY', `DESCRIPTION:${e(title)}`, 'END:VALARM',
      'END:VEVENT', 'END:VCALENDAR',
    ].filter(Boolean).join('\r\n');
    const url = URL.createObjectURL(new Blob([lines], { type: 'text/calendar;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url; a.download = 'fit-journey-meeting.ics';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  window.FJMeet = {
    // מאמן
    renderCoach, openForm, closeForm, setKind, chip, save, cancel, done,
    // מתאמן
    initTrainee, syncCalendar, enableCalendar, disableCalendar, dismissCal, ics,
  };
})();
