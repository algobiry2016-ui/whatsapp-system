-- فصل مبلغ التوصيل عن مبلغ الطلب في طلبات الواتس. يُشغَّل مرة وحدة في SQL Editor قبل 1 نوفمبر 2026.
-- عمود جديد بس: amount يبقى الإجمالي المدفوع (الطلب + التوصيل)، و delivery_fee جزء التوصيل منه.
-- الطلبات القديمة تبقى delivery_fee فاضي (null). الواجهة تبدأ تطلب المبلغين من 1 نوفمبر.
alter table wa_orders add column if not exists delivery_fee numeric check (delivery_fee >= 0);
