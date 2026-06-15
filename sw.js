/* ── HF Coaching Service Worker ── */
// מאחדים את ה-Service Worker של OneSignal עם שלנו, כדי שלא יתחרו על אותו scope
// (שני SW-ים נפרדים על "/" גורמים לבעיות הרשמה ל-Push, בעיקר ב-iOS Safari)
importScripts('https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js');

const CACHE = 'hf-v1';

const STATIC = [
  '/login.html',
  '/index.html',
  '/coach.html',
  '/admin.html',
  '/dashboard.html',
  '/food.html',
  '/manifest.json',
  '/icon.svg',
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

  /* API calls (Supabase / Anthropic / OneSignal) → always network, never cache */
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('anthropic.com') ||
    url.hostname.includes('onesignal.com') ||
    url.hostname.includes('bitpay.co.il') ||
    url.protocol === 'chrome-extension:'
  ) {
    e.respondWith(fetch(e.request));
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

  /* App HTML/assets → network first (get latest), cache fallback for offline */
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then(cached => cached || caches.match('/login.html')))
  );
});
