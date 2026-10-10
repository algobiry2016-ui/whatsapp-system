// إشعارات الجوال لموظفات الواتس — تشغّلها الجدولة (pg_cron) في supabase/push.sql
// المتغيرات (Edge Function Secrets): VAPID_PUBLIC و VAPID_PRIVATE و CRON_SECRET — تتولد من صفحة push-keys.html
// SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY تجي جاهزة من Supabase
// لازم "Verify JWT" يكون مقفل للدالة، والحماية بـ CRON_SECRET
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
  if (req.headers.get('x-cron-secret') !== Deno.env.get('CRON_SECRET')) return new Response('forbidden', { status: 403 });
  const job = new URL(req.url).searchParams.get('job') || '';
  const today = new Date(Date.now() + RIYADH).toISOString().slice(0, 10);
  const dayStart = new Date(Date.parse(today + 'T00:00:00Z') - RIYADH).toISOString();

  const [{ data: staff }, { data: subs }] = await Promise.all([
    sb.from('wa_profiles').select('email,name,role'),
    sb.from('wa_push_subs').select('*'),
  ]);
  const sent: string[] = [], gone: string[] = [];

  for (const p of (staff || []).filter((s) => s.role !== 'admin')) {
    const name = p.name || '';
    let msg: { title: string; body: string; tab?: string } | null = null;

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

    if (!msg) continue;
    for (const s of (subs || []).filter((x) => x.email.toLowerCase() === p.email.toLowerCase())) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(msg), { TTL: 3 * 3600 });
        sent.push(p.email);
      } catch (e) {
        // الجهاز ألغى الاشتراك أو انحذف التطبيق: نشيله
        if (e.statusCode === 404 || e.statusCode === 410) { gone.push(s.endpoint); await sb.from('wa_push_subs').delete().eq('endpoint', s.endpoint); }
        else console.error('push failed', p.email, e.statusCode, e.body);
      }
    }
  }
  return Response.json({ job, today, sent, removed: gone.length });
});
