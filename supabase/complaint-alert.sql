-- تنبيه الإدارة بكل شكوى جديدة. يُشغَّل مرة وحدة في SQL Editor بعد push.sql، بدون أي تعديل.
-- بعد إضافة أي شكوى، القاعدة تنادي دالة wa-push (?job=complaint) وهي ترسل للإدارة.
-- الاتصال ما يأخّر حفظ الشكوى، ولو فشل الإرسال الشكوى تنحفظ عادي.
create or replace function public.wa_complaint_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url     := 'https://eolnpozfksejyfkdcpuz.supabase.co/functions/v1/wa-push?job=complaint',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select v from public.wa_push_config where k='cron_secret')),
    body    := jsonb_build_object('id', new.id));
  return new;
end $$;

drop trigger if exists wa_complaint_notify on public.wa_complaints;
create trigger wa_complaint_notify after insert on public.wa_complaints
  for each row execute function public.wa_complaint_notify();

-- إيقاف التنبيه:
-- drop trigger if exists wa_complaint_notify on public.wa_complaints;
