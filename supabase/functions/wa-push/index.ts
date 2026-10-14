// إشعارات الجوال لموظفات الواتس — تشغّلها الجدولة (pg_cron) في supabase/push.sql
// المتغيرات (Edge Function Secrets): VAPID_PUBLIC و VAPID_PRIVATE — تتولد من صفحة push-keys.html
// SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY تجي جاهزة من Supabase
// لازم "Verify JWT" يكون مقفل للدالة. الحماية بسر تولّده القاعدة في wa_push_config (ما يقراه إلا مفتاح الخدمة)
// والجدولة ترسله في x-cron-secret
// شكوى جديدة: trigger على wa_complaints يستدعي ?job=complaint، وتوصل للإدارة (إشعار جوال، وتيليجرام إذا
// انضاف TELEGRAM_BOT_TOKEN و TELEGRAM_CHAT_ID في Secrets)
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import webpush from 'npm:web-push@3.6.7';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
webpush.setVapidDetails('https://algobiry2016-ui.github.io/whatsapp-system/', Deno.env.get('VAPID_PUBLIC')!, Deno.env.get('VAPID_PRIVATE')!);

const RIYADH = 3 * 3600e3;
const OPEN_ST = ['قيد التجهيز', 'تم التجهيز'];

Deno.serve(async (req) => {
  // المفتاح العام للتطبيق (عام أصلًا، ما يحتاج سر)
  if (new URL(req.url).searchParams.get('job') === 'key')
    return new Response(Deno.env.get('VAPID_PUBLIC') || '', { headers: { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'text/plain' } });
  const { data: cfg } = await sb.from('wa_push_config').select('v').eq('k', 'cron_secret').maybeSingle();
  const given = req.headers.get('x-cron-secret');
  if (!cfg?.v || given !== cfg.v) return new Response('forbidden', { status: 403 });
  const job = new URL(req.url).searchParams.get('job') || '';
  const today = new Date(Date.now() + RIYADH).toISOString().slice(0, 10);
  const dayStart = new Date(Date.parse(today + 'T00:00:00Z') - RIYADH).toISOString();

  const [{ data: staff }, { data: subs }] = await Promise.all([
    sb.from('wa_profiles').select('email,name,role'),
    sb.from('wa_push_subs').select('*'),
  ]);
  const sent: string[] = [], gone: string[] = [];
  type Msg = { title: string; body: string; tab?: string };
  const pushTo = async (email: string, msg: Msg) => {
    for (const s of (subs || []).filter((x) => x.email.toLowerCase() === email.toLowerCase())) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(msg), { TTL: 3 * 3600 });
        sent.push(email);
      } catch (e: any) {
        // الجهاز ألغى الاشتراك أو انحذف التطبيق: نشيله
        if (e.statusCode === 404 || e.statusCode === 410) { gone.push(s.endpoint); await sb.from('wa_push_subs').delete().eq('endpoint', s.endpoint); }
        else console.error('push failed', email, e.statusCode, e.body);
      }
    }
  };

  if (job === 'complaint') {   // شكوى جديدة: للإدارة
    const { id } = await req.json().catch(() => ({ id: null }));
    const { data: c } = await sb.from('wa_complaints').select('*').eq('id', id).maybeSingle();
    if (!c) return Response.json({ job, sent });
    const who = (staff || []).find((s) => s.email.toLowerCase() === String(c.created_by || '').toLowerCase())?.name;
    const details = String(c.details || '').slice(0, 160);
    // شكوى بتاريخ سابق: نوضح تاريخها
    const day = c.received_at ? new Date(Date.parse(c.received_at) + RIYADH).toISOString().slice(0, 10) : today;
    const msg: Msg = { title: 'شكوى جديدة 🔴', tab: 'complaints',
      body: `طلب ${c.order_code} · ${c.ctype}${day !== today ? ` · بتاريخ ${day}` : ''}${c.responsible ? ` · المتسبب: ${c.responsible}` : ''}\n${details}${who ? `\nسجّلتها: ${who}` : ''}` };
    for (const p of (staff || []).filter((s) => s.role === 'admin')) await pushTo(p.email, msg);
    const tg = Deno.env.get('TELEGRAM_BOT_TOKEN'), chat = Deno.env.get('TELEGRAM_CHAT_ID');
    if (tg && chat) {
      const r = await fetch(`https://api.telegram.org/bot${tg}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chat, text: `🔴 شكوى جديدة — مبيعات الواتس\n${msg.body}` }) });
      if (r.ok) sent.push('telegram'); else console.error('telegram failed', r.status, await r.text());
    }
    return Response.json({ job, sent, removed: gone.length });
  }

  for (const p of (staff || []).filter((s) => s.role !== 'admin')) {
    const name = p.name || '';
    let msg: Msg | null = null;

    if (job === 'test') msg = { title: 'مبيعات الواتس', body: `${name}، الإشعارات شغالة ✅` };

    if (job === 'due') {   // بداية الدوام: طلبات لازم تتسلم اليوم
      const { count } = await sb.from('wa_orders').select('id', { count: 'exact', head: true })
        .in('status', OPEN_ST).eq('delivery_date', today).neq('approval', 'مرفوض');
      if (count) msg = { title: 'طلبات اليوم', body: `${name}، عندك ${count} ${count === 1 ? 'طلب' : 'طلبات'} لازم تتسلم اليوم`, tab: 'orders' };
    }

    if (job === 'orders') {   // العصر: ما سجّلت ولا طلب
      const { count } = await sb.from('wa_orders').select('id', { count: 'exact', head: true })
        .ilike('created_by', p.email).gte('created_at', dayStart);
      if (!count) msg = { title: 'طلبات الواتس', body: `${name}، لا تنسي تسجلي طلبات الواتس — ما انسجل ولا طلب اليوم`, tab: 'orders' };
    }

    if (job === 'daily') {   // الليل: نشاط اليوم ما انسجل
      const { data } = await sb.from('wa_daily').select('day').eq('day', today).maybeSingle();
      if (!data) msg = { title: 'النشاط اليومي', body: `${name}، لا تنسي تسجلي نشاط اليوم (الستوري والمشاهدات والاستفسارات)، وإذا ما فيه نشاط اكتبي السبب`, tab: 'daily' };
    }

    if (msg) await pushTo(p.email, msg);
  }
  return Response.json({ job, today, sent, removed: gone.length });
});
