-- طرق الدفع: إضافة "كاش" و"شبكة" (تطلع للاستلام والتوصيل). طُبّق بطلب رؤوف (2026-11-01).
-- يوسّع القيد بس، وما يمس أي طلب موجود.
alter table wa_orders drop constraint wa_orders_payment_check;
alter table wa_orders add constraint wa_orders_payment_check
  check (payment in ('تمارا','تابي','تحويل بنكي','كاش','شبكة'));
