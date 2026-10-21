-- صلاحيات الموظفة (منال): تعديل وحذف، وبدون طابور اعتماد، وتبقى موظفة (التذكيرات والإشعارات شغالة لها).
-- اللي يبقى للإدارة بس: التحقق من وصول التحويل (verified)، والاعتماد/الرفض، وسجل التدقيق.
-- سجل التدقيق يسجّل كل تعديل وحذف باسم اللي سواه.
-- طُبّق بموافقة رؤوف (2026-10-21).

-- ١) الطلبات
create or replace function public.wa_guard_verify() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r text := wa_role();
  me text := auth.jwt() ->> 'email';
begin
  -- برنامج طلبات الموقع (مفتاح الخدمة): يغيّر الحالة فقط.
  if r is null and auth.role() = 'service_role' then
    if tg_op = 'INSERT' then raise exception 'لا توجد صلاحية'; end if;
    new.id := old.id; new.created_at := old.created_at; new.created_by := old.created_by;
    if (to_jsonb(new) - 'status' - 'delivered_at' - 'code') is distinct from (to_jsonb(old) - 'status' - 'delivered_at' - 'code') then
      raise exception 'غير مسموح: برنامج الطلبات يغيّر الحالة فقط';
    end if;
    return new;
  end if;

  if r is null then raise exception 'لا توجد صلاحية'; end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := me;
    if new.paid_date is null then new.paid_date := wa_today(); end if;
    if new.paid_date > wa_today() then raise exception 'تاريخ التحويل ما يصير في المستقبل'; end if;
    new.approval := 'معتمد';   -- ما فيه طابور اعتماد
    if r <> 'admin' then
      new.verified := false; new.verified_by := null; new.verified_at := null;
      new.approved_by := null; new.approved_at := null; new.reject_reason := null;
    else
      if new.paid_date < wa_today() then new.approved_by := me; new.approved_at := now(); end if;
      if new.verified then new.verified_by := me; new.verified_at := now(); end if;
    end if;
    return new;
  end if;

  -- UPDATE: هذي ما تتغير أبداً حتى من الأدمن
  new.id := old.id; new.created_at := old.created_at; new.created_by := old.created_by;
  if new.paid_date > wa_today() then raise exception 'تاريخ التحويل ما يصير في المستقبل'; end if;

  if r <> 'admin' then
    -- الموظفة تعدّل كل شي، إلا التحقق والاعتماد
    new.verified := old.verified; new.verified_by := old.verified_by; new.verified_at := old.verified_at;
    new.approval := old.approval; new.approved_by := old.approved_by; new.approved_at := old.approved_at;
    new.reject_reason := old.reject_reason;
    -- لو تغيّر شي في الفلوس لطلب متحقق منه، يرجع يحتاج تحقق من الإدارة
    if old.verified and (new.amount, new.payment, new.paid_date, new.txn_ref, new.receipt_path)
                        is distinct from (old.amount, old.payment, old.paid_date, old.txn_ref, old.receipt_path) then
      new.verified := false; new.verified_by := null; new.verified_at := null;
    end if;
    return new;
  end if;

  -- الأدمن
  if new.verified and not old.verified then new.verified_by := me; new.verified_at := now();
  elsif not new.verified then new.verified_by := null; new.verified_at := null; end if;
  if new.approval is distinct from old.approval then
    if new.approval = 'بانتظار الاعتماد' then new.approved_by := null; new.approved_at := null;
    else new.approved_by := me; new.approved_at := now(); end if;
    if new.approval <> 'مرفوض' then new.reject_reason := null; end if;
  end if;
  return new;
end $$;

-- ٢) الشكاوى: الموظفة تعدّل كل شي (إلا مين سجّلها ومتى)
create or replace function public.wa_guard_complaints() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if wa_role() is null then raise exception 'لا توجد صلاحية'; end if;
  if tg_op = 'INSERT' then
    new.created_at := now(); new.created_by := auth.jwt() ->> 'email';
    return new;
  end if;
  new.id := old.id; new.created_at := old.created_at; new.created_by := old.created_by;
  return new;
end $$;

-- ٣) النشاط اليومي: بدون حد الـ 7 أيام (يبقى ممنوع اليوم اللي ما جا)
create or replace function public.wa_guard_daily() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if wa_role() is null then raise exception 'لا توجد صلاحية'; end if;
  new.updated_by := auth.jwt() ->> 'email'; new.updated_at := now();
  if new.day > wa_today() then raise exception 'ما يصير تسجّل نشاط يوم ما جاء'; end if;
  return new;
end $$;

-- ٤) الحذف (وتعديل العملاء المحتملين) لأي حساب في النظام
drop policy if exists wa_orders_del on wa_orders;
create policy wa_orders_del on wa_orders for delete to authenticated using (wa_role() is not null);
drop policy if exists wa_complaints_del on wa_complaints;
create policy wa_complaints_del on wa_complaints for delete to authenticated using (wa_role() is not null);
drop policy if exists wa_leads_del on wa_leads;
create policy wa_leads_del on wa_leads for delete to authenticated using (wa_role() is not null);
drop policy if exists wa_leads_upd on wa_leads;
create policy wa_leads_upd on wa_leads for update to authenticated using (wa_role() is not null);
drop policy if exists wa_daily_del on wa_daily;
create policy wa_daily_del on wa_daily for delete to authenticated using (wa_role() is not null);
