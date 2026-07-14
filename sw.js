/* ── HF Coaching Service Worker ── */
// מאחדים את ה-Service Worker של OneSignal עם שלנו, כדי שלא יתחרו על אותו scope
// (שני SW-ים נפרדים על "/" גורמים לבעיות הרשמה ל-Push, בעיקר ב-iOS Safari)
importScripts('https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js');

const CACHE = 'hf-v5'; // bumped: centered full-bleed FJ icon (no border seam) — refresh installed clients

// relative paths — work from root AND from a subpath like /fit-journey/
const STATIC = [
  './login.html',
  './index.html',
  './coach.html',
  './admin.html',
  './dashboard.html',
  './food.html',
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
      .catch(() => caches.match(e.request).then(cached => cached || caches.match('./login.html')))
  );
});
