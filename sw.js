// نسخة التطبيق — الشبكة أولاً عشان أي تحديث على GitHub يوصل مباشرة
const CACHE = 'dm-whatsapp-v13';
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return; // بيانات Supabase ما تتخزن
  e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; })
    .catch(() => caches.match(e.request).then(r => r || caches.match('./index.html'))));
});

// إشعارات الجوال من دالة wa-push، توصل حتى لو التطبيق مقفل
self.addEventListener('push', e => {
  let m = { title:'مبيعات الواتس', body:'' };
  try { m = e.data.json(); } catch (_) { if (e.data) m.body = e.data.text(); }
  e.waitUntil(self.registration.showNotification(m.title, { body:m.body, icon:'icon-192.png', badge:'icon-192.png', lang:'ar', dir:'rtl', data:{ tab:m.tab||'' } }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL('./' + (e.notification.data && e.notification.data.tab ? '#' + e.notification.data.tab : ''), self.registration.scope).href;
  e.waitUntil(clients.matchAll({ type:'window', includeUncontrolled:true }).then(ws => {
    if (ws[0]) return ws[0].navigate(url).then(w => (w||ws[0]).focus()).catch(() => ws[0].focus());
    return clients.openWindow(url);
  }));
});
