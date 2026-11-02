-- دور "مساعد" (helper) لمساعد منال (راشد، 2026-11-02): يدخل بجواله، ويشوف تبويب "طلبات الواتس" بس،
-- يضيف طلب ويسنده للمنسق. ما يعدّل ولا يحذف طلب، وما يشوف الشكاوى ولا العملاء المحتملين ولا النشاط اليومي.
-- منال (staff) والإدارة (admin) ما يتغير عليهم شي.
-- حساب المساعد نفسه (الإيميل من الجوال) ينضاف في wa_profiles من لوحة Supabase، مو هنا (المستودع عام).

alter table wa_profiles drop constraint wa_profiles_role_check;
alter table wa_profiles add constraint wa_profiles_role_check check (role in ('admin','staff','helper'));

-- الطلبات: المساعد يضيف ويقرأ (يحتاجها لـ "عميل جديد/سابق" والمبالغ)، والتعديل والحذف لمنال والإدارة
drop policy if exists wa_orders_upd on wa_orders;
create policy wa_orders_upd on wa_orders for update to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_orders_del on wa_orders;
create policy wa_orders_del on wa_orders for delete to authenticated using (wa_role() in ('staff','admin'));

-- الشكاوى والعملاء المحتملين والنشاط اليومي: لمنال والإدارة بس
drop policy if exists wa_complaints_sel on wa_complaints;
create policy wa_complaints_sel on wa_complaints for select to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_complaints_ins on wa_complaints;
create policy wa_complaints_ins on wa_complaints for insert to authenticated with check (wa_role() in ('staff','admin'));
drop policy if exists wa_complaints_upd on wa_complaints;
create policy wa_complaints_upd on wa_complaints for update to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_complaints_del on wa_complaints;
create policy wa_complaints_del on wa_complaints for delete to authenticated using (wa_role() in ('staff','admin'));

drop policy if exists wa_leads_sel on wa_leads;
create policy wa_leads_sel on wa_leads for select to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_leads_ins on wa_leads;
create policy wa_leads_ins on wa_leads for insert to authenticated with check (wa_role() in ('staff','admin'));
drop policy if exists wa_leads_upd on wa_leads;
create policy wa_leads_upd on wa_leads for update to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_leads_del on wa_leads;
create policy wa_leads_del on wa_leads for delete to authenticated using (wa_role() in ('staff','admin'));

drop policy if exists wa_daily_sel on wa_daily;
create policy wa_daily_sel on wa_daily for select to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_daily_ins on wa_daily;
create policy wa_daily_ins on wa_daily for insert to authenticated with check (wa_role() in ('staff','admin'));
drop policy if exists wa_daily_upd on wa_daily;
create policy wa_daily_upd on wa_daily for update to authenticated using (wa_role() in ('staff','admin'));
drop policy if exists wa_daily_del on wa_daily;
create policy wa_daily_del on wa_daily for delete to authenticated using (wa_role() in ('staff','admin'));
