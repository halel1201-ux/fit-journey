/* ── HF Coaching Service Worker ── */
// מאחדים את ה-Service Worker של OneSignal עם שלנו, כדי שלא יתחרו על אותו scope
// (שני SW-ים נפרדים על "/" גורמים לבעיות הרשמה ל-Push, בעיקר ב-iOS Safari)
importScripts('https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js');

const CACHE = 'hf-v17'; // bumped: דילאוד מנוהל

// relative paths — work from root AND from a subpath like /fit-journey/
const STATIC = [
  './login.html',
  './index.html',
  './coach.html',
  './admin.html',
  './dashboard.html',
  './food.html',
  './nutrition-editor.js',   // עורך התזונה המשותף — נטען בכל אחד משני הפאנלים
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-512-maskable.png',
  './apple-touch-icon.png',
  './favicon.png',
];

/* ── Install: cache static files ── */
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  );
});

/* ── Activate: remove old caches ── */
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

/* ── Fetch strategy ── */
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  /* API calls (Supabase / Anthropic / OneSignal) → bypass SW entirely, let browser handle */
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('anthropic.com') ||
    url.hostname.includes('onesignal.com') ||
    url.hostname.includes('bitpay.co.il') ||
    url.protocol === 'chrome-extension:'
  ) {
    return; // don't call e.respondWith — browser fetches directly, body stream intact
  }

  /* Static JSON databases (strength_exercises.json, food_all.json, …) → bypass SW entirely.
     These are large, same-origin, and must always load fresh from network. Never route them
     through cache logic — a stale/faulty SW must not be able to break the exercise/food DB. */
  if (url.pathname.endsWith('.json') && url.origin === self.location.origin) {
    return;
  }

  /* Google Fonts → network first, cache fallback */
  if (url.hostname.includes('fonts.googleapis.com') || url.hostname.includes('fonts.gstatic.com')) {
    e.respondWith(
      caches.open(CACHE).then(c =>
        c.match(e.request).then(cached =>
          cached || fetch(e.request).then(res => { c.put(e.request, res.clone()); return res; })
        )
      )
    );
    return;
  }

  const isDoc = e.request.method === 'GET' &&
                url.origin === self.location.origin &&
                e.request.mode === 'navigate';

  /* ── דפי HTML: מגישים מהמטמון ומרעננים ברקע ──
     הבעיה המקורית: ה-fetch כאן נענה ממטמון ה-HTTP של הדפדפן, וגיטהאב
     מגיש max-age=600 — עד עשר דקות שבהן גם רענון קשיח מחזיר גרסה
     ישנה, ותיקון שכבר עלה נראה כאילו לא נעשה.

     הפתרון הקודם, אימות כפוי בכל ניווט, תיקן את זה אבל יצר בעיה
     גדולה יותר: ה-ETag של גיטהאב אינו יציב בין צמתי הקצה, ולכן
     האימות החזיר את הקובץ המלא כמעט תמיד. coach.html שוקל 830
     קילובייט — כלומר כל כניסה לפאנל שילמה הורדה מלאה, ובסלולרי זה
     שניות ארוכות. זה מה שהאט את ההתחברות ואת הטעינה.

     כאן מגישים את העותק השמור מיד — טעינה מיידית — ובמקביל מורידים
     ברקע ומעדכנים את המטמון. התיקון מופיע בטעינה הבאה במקום להשהות
     את הנוכחית. waitUntil שומר על ה-Service Worker חי עד שהרענון
     מסתיים, אחרת הדפדפן היה עלול לקטול אותו באמצע. */
  if (isDoc) {
    e.respondWith(
      caches.open(CACHE).then(async cache => {
        const cached = await cache.match(e.request);
        const fresh = fetch(new Request(url.href, { cache: 'no-cache', credentials: 'same-origin' }))
          .then(res => { if (res.ok) cache.put(e.request, res.clone()); return res; })
          .catch(() => null);
        e.waitUntil(fresh);
        return cached || (await fresh) || cache.match('./login.html');
      })
    );
    return;
  }

  /* שאר הנכסים → רשת תחילה, מטמון כגיבוי לאופליין */
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then(cached => cached || caches.match('./login.html')))
  );
});
