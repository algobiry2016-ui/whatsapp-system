-- ربط طلبات الواتس مع برنامج طلبات الموقع (website-orders).
-- منال تسجّل الطلب هنا مثل العادة من تبويب "طلبات الواتس" (باسمها وبنفس قواعد الاعتماد)،
-- والتبويب يرسله لبرنامج الطلبات (بالصور والتسجيلات الصوتية والمنسق). وبعدها البرنامج
-- يحدّث حالته هنا: تم التجهيز، تم التوصيل/الاستلام، ملغي.
-- البرنامج يدخل بمفتاح الخدمة (service role)، وهذا التعديل يسمح له بشي واحد فقط:
-- تغيير الحالة على الطلبات الموجودة. ما يضيف ولا يحذف ولا يعدّل مبلغ ولا يوثّق.
-- وسجل التدقيق يكتب "orders-system" بدل الإيميل لما يكون التغيير منه.
-- ما يمسح ولا يغيّر أي بيانات موجودة.

create or replace function public.wa_guard_verify()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

    if r <> 'admin' then
      new.verified := false; new.verified_by := null; new.verified_at := null;
      new.reject_reason := null;
      if new.paid_date < wa_today() then
        new.approval := 'بانتظار الاعتماد'; new.approved_by := null; new.approved_at := null;
      else
        new.approval := 'معتمد'; new.approved_by := null; new.approved_at := null;
      end if;
    else
      new.approval := 'معتمد';
      if new.paid_date < wa_today() then new.approved_by := me; new.approved_at := now(); end if;
      if new.verified then new.verified_by := me; new.verified_at := now(); end if;
    end if;
    return new;
  end if;

  -- UPDATE: هذي ما تتغير أبداً حتى من الأدمن
  new.id := old.id; new.created_at := old.created_at; new.created_by := old.created_by;

  if r <> 'admin' then
    -- الموظفة تغيّر الحالة بس، وأي عمود ثاني مرفوض
    if (to_jsonb(new) - 'status' - 'delivered_at' - 'code') is distinct from (to_jsonb(old) - 'status' - 'delivered_at' - 'code') then
      raise exception 'غير مسموح: تقدرين تغيّرين حالة الطلب فقط';
    end if;
    return new;
  end if;

  -- الأدمن
  if new.paid_date > wa_today() then raise exception 'تاريخ التحويل ما يصير في المستقبل'; end if;
  if new.verified and not old.verified then new.verified_by := me; new.verified_at := now();
  elsif not new.verified then new.verified_by := null; new.verified_at := null; end if;
  if new.approval is distinct from old.approval then
    if new.approval = 'بانتظار الاعتماد' then new.approved_by := null; new.approved_at := null;
    else new.approved_by := me; new.approved_at := now(); end if;
    if new.approval <> 'مرفوض' then new.reject_reason := null; end if;
  end if;
  return new;
end $function$;

create or replace function public.wa_audit_log()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into wa_audit (actor, tbl, row_id, action, old_data, new_data)
  values (coalesce(auth.jwt() ->> 'email', case when auth.role() = 'service_role' then 'orders-system' end), tg_table_name,
          coalesce((case when tg_op = 'DELETE' then old.id else new.id end), null),
          tg_op,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return null;
end $function$;
