-- الدفع المقسّم على طريقتين (طلب رؤوف 2026-11-09): مثل عميل يدفع جزء شبكة وجزء تحويل بنكي.
-- ثلاث أعمدة اختيارية بس، والطلبات الموجودة ما تتغير (تبقى فاضية = طريقة وحدة).
--   amount        يبقى الإجمالي المدفوع مثل ما هو
--   payment2      الطريقة الثانية (تحويل بنكي أو شبكة أو كاش)
--   amount2       مبلغ الطريقة الثانية (جزء من الإجمالي، مو زيادة عليه). الطريقة الأولى = amount - amount2
--   receipt_path2 صورة إثبات الطريقة الثانية
-- التقسيم بين التحويل والشبكة والكاش بس (تابي وتمارا ياخذون المبلغ كامل).
-- ولو تعدّل أي شي فيها لطلب متحقق منه، يرجع يحتاج تحقق من الإدارة (مثل المبلغ والدفع).

alter table wa_orders add column if not exists payment2 text;
alter table wa_orders add column if not exists amount2 numeric;
alter table wa_orders add column if not exists receipt_path2 text;

alter table wa_orders drop constraint if exists wa_orders_split_check;
alter table wa_orders add constraint wa_orders_split_check check (
  (payment2 is null and amount2 is null and receipt_path2 is null)
  or (payment in ('تحويل بنكي','شبكة','كاش') and payment2 in ('تحويل بنكي','شبكة','كاش')
      and payment2 <> payment and amount2 > 0 and amount2 < amount)
);

-- نفس الدالة الشغالة (manal-permissions.sql)، والفرق الوحيد: أعمدة الطريقة الثانية في شرط "يرجع يحتاج تحقق"
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
    -- لو تغيّر شي في الفلوس لطلب متحقق منه (ومنها الطريقة الثانية)، يرجع يحتاج تحقق من الإدارة
    if old.verified and (new.amount, new.payment, new.paid_date, new.txn_ref, new.receipt_path, new.payment2, new.amount2, new.receipt_path2)
                        is distinct from (old.amount, old.payment, old.paid_date, old.txn_ref, old.receipt_path, old.payment2, old.amount2, old.receipt_path2) then
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
