-- =====================================================================
--  03 — تنبيهات التأخير حسب المراحل (SLA) — المرحلة ب
--  ينفّذ بعد 01 (role_for_stage, status_changed_at, notifications) و02 (admin).
--
--  ⚠️ enabled = false افتراضيًا عمدًا: القاعدة فيها 562 طلبًا تاريخيًا مستوردًا
--  يقف على المرحلة 2، ولو فعّلنا التنبيهات فورًا سيصل لرئيس الحسابات مئات
--  تنبيهات «متأخر» دفعة واحدة. الأدمن يفعّلها من لوحته بعد ضبط بيانات
--  التشغيل الفعلي.
-- =====================================================================

create table if not exists public.sla_settings (
  id          boolean primary key default true,
  stage2_days int  not null default 2,   -- رئيس الحسابات
  stage3_days int  not null default 2,   -- المدير المالي
  stage4_days int  not null default 2,   -- المدير العام
  stage5_days int  not null default 3,   -- مسؤول البنوك (تنفيذ الصرف)
  stage6_days int  not null default 2,   -- الأرشفة (موظف الحسابات)
  enabled     boolean not null default false,
  updated_at  timestamptz not null default now(),
  constraint sla_singleton check (id)
);
insert into public.sla_settings(id) values (true) on conflict (id) do nothing;

alter table public.sla_settings enable row level security;

-- الجميع (المسجّلون) يقرؤون الإعدادات لحساب شارة «متأخر» في الواجهة
drop policy if exists sla_read on public.sla_settings;
create policy sla_read on public.sla_settings for select
  using (auth.uid() is not null);

-- الأدمن فقط يعدّل الإعدادات
drop policy if exists sla_write on public.sla_settings;
create policy sla_write on public.sla_settings for all
  using (current_role_of() = 'admin')
  with check (current_role_of() = 'admin');

-- ---------------------------------------------------------------------
--  دالة توليد تنبيهات التأخير: تفحص الطلبات المعلّقة التي تجاوزت مدة
--  مرحلتها، وتنشئ تنبيهًا واحدًا لكل (طلب/مرحلة) بدون تكرار.
-- ---------------------------------------------------------------------
create or replace function public.generate_delay_alerts()
returns int
language plpgsql security definer set search_path = public
as $$
declare
  s    public.sla_settings;
  rec  record;
  d    int;
  cnt  int := 0;
  v_role text;
begin
  select * into s from public.sla_settings where id;
  if not found or not s.enabled then
    return 0;
  end if;

  for rec in
    select id, entity, current_stage_order, status_changed_at
    from public.requests
    where status = 'pending' and current_stage_order between 2 and 6
  loop
    d := case rec.current_stage_order
      when 2 then s.stage2_days when 3 then s.stage3_days
      when 4 then s.stage4_days when 5 then s.stage5_days
      when 6 then s.stage6_days else 0 end;

    if d > 0 and rec.status_changed_at < now() - make_interval(days => d) then
      if not exists (
        select 1 from public.notifications n
        where n.request_id = rec.id and n.message like 'متأخر:%'
          and n.created_at > rec.status_changed_at
      ) then
        v_role := role_for_stage(rec.current_stage_order);
        insert into public.notifications(target_role, request_id, message)
        values (v_role, rec.id,
          'متأخر: طلب صرف ' || coalesce(rec.entity,'') ||
          ' تجاوز ' || d || ' يوم في مرحلته الحالية');
        cnt := cnt + 1;
      end if;
    end if;
  end loop;

  return cnt;
end;
$$;

-- الدالة داخلية — لا تُستدعى مباشرة عبر REST RPC
revoke execute on function public.generate_delay_alerts() from anon, authenticated;

-- ---------------------------------------------------------------------
--  جدولة تلقائية كل ساعة عبر pg_cron (بدون خادم خارجي)
--  (تعمل حتى لو enabled=false — الدالة ترجع 0 فورًا وقتها)
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;

select cron.unschedule('deyabi-delay-alerts')
  where exists (select 1 from cron.job where jobname = 'deyabi-delay-alerts');

select cron.schedule('deyabi-delay-alerts', '0 * * * *',
  $$select public.generate_delay_alerts();$$);
