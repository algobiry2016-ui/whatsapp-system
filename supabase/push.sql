-- إشعارات الجوال لنظام الواتس. يُشغَّل مرة وحدة في SQL Editor لمشروع Supabase حق المشتريات، بدون أي تعديل.

-- ١) أجهزة الموظفين اللي فعّلوا الإشعارات. كل شخص يشوف ويضيف ويحذف أجهزته هو بس.
create table if not exists wa_push_subs (
  endpoint   text primary key,
  email      text not null default auth.email(),
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz not null default now()
);
alter table wa_push_subs enable row level security;
create policy "wa_push_subs own select" on wa_push_subs for select to authenticated using (email = auth.email());
create policy "wa_push_subs own insert" on wa_push_subs for insert to authenticated with check (email = auth.email());
create policy "wa_push_subs own update" on wa_push_subs for update to authenticated using (email = auth.email()) with check (email = auth.email());
create policy "wa_push_subs own delete" on wa_push_subs for delete to authenticated using (email = auth.email());

-- ٢) سر الجدولة: تولّده القاعدة بنفسها. RLS مفعّل بلا قواعد، فما يقراه إلا مفتاح الخدمة (الدالة) والجدولة.
create table if not exists wa_push_config (k text primary key, v text not null);
alter table wa_push_config enable row level security;
insert into wa_push_config (k, v) values ('cron_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
  on conflict (k) do nothing;

-- ٣) الجدولة والاتصال بالدالة
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ٤) المواعيد (pg_cron بتوقيت UTC، والرياض = UTC + 3)
--   1:15 الظهر: الطلبات اللي لازم تتسلم اليوم
--   5:00 العصر: إذا ما انسجل ولا طلب اليوم
--   9:30 الليل: إذا نشاط اليوم ما انسجل
select cron.schedule('wa-push-due',    '15 10 * * *', $$select net.http_post(url:='https://eolnpozfksejyfkdcpuz.supabase.co/functions/v1/wa-push?job=due',    headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',(select v from public.wa_push_config where k='cron_secret')), body:='{}'::jsonb)$$);
select cron.schedule('wa-push-orders', '0 14 * * *',  $$select net.http_post(url:='https://eolnpozfksejyfkdcpuz.supabase.co/functions/v1/wa-push?job=orders', headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',(select v from public.wa_push_config where k='cron_secret')), body:='{}'::jsonb)$$);
select cron.schedule('wa-push-daily',  '30 18 * * *', $$select net.http_post(url:='https://eolnpozfksejyfkdcpuz.supabase.co/functions/v1/wa-push?job=daily',  headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',(select v from public.wa_push_config where k='cron_secret')), body:='{}'::jsonb)$$);

-- تجربة يدوية (ترسل "الإشعارات شغالة" لكل موظفة فعّلت):
-- select net.http_post(url:='https://eolnpozfksejyfkdcpuz.supabase.co/functions/v1/wa-push?job=test', headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',(select v from public.wa_push_config where k='cron_secret')), body:='{}'::jsonb);
-- نتيجة آخر اتصال:
-- select status_code, content from net._http_response order by created desc limit 1;
-- إيقاف كل الإشعارات:
-- select cron.unschedule('wa-push-due'); select cron.unschedule('wa-push-orders'); select cron.unschedule('wa-push-daily');
