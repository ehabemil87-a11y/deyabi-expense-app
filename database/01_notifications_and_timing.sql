-- =====================================================================
--  01 — نظام الإشعارات + تتبّع زمن المرحلة (المرحلة أ)
--  نظام طلبات الصرف — مجموعة الذيابي
--
--  إضافي وآمن: لا يعدّل أي بيانات قائمة. كل triggers الإشعارات مغلّفة
--  بمعالجة استثناء بحيث لا يعطّل فشل إشعار أي عملية اعتماد/تقديم أساسية.
--
--  نموذج طلبات الصرف يعتمد على current_stage_order (2..7) + status، وليس
--  على نصّ status وحده كنظام المستخلصات — لذا تُبنى الإشعارات هنا على
--  انتقال المرحلة، مع دالة role_for_stage لربط رقم المرحلة بالدور.
-- =====================================================================

-- ---------------------------------------------------------------------
--  0) دالة: الدور المسؤول عن كل مرحلة (تطابق مصفوفة STAGES في الواجهة)
-- ---------------------------------------------------------------------
create or replace function public.role_for_stage(p_order int)
returns text
language sql immutable
as $$
  select case p_order
    when 2 then 'accounts_manager'
    when 3 then 'finance_manager'
    when 4 then 'general_manager'
    when 5 then 'bank_officer'
    when 6 then 'accountant'   -- مرحلة الأرشفة
    else null
  end;
$$;

-- ---------------------------------------------------------------------
--  1) تتبّع لحظة آخر تغيّر للمرحلة/الحالة (أساس تنبيهات التأخير لاحقًا)
-- ---------------------------------------------------------------------
alter table public.requests
  add column if not exists status_changed_at timestamptz not null default now();

create or replace function public.touch_request_stage_changed()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (tg_op = 'UPDATE'
      and (new.current_stage_order is distinct from old.current_stage_order
           or new.status is distinct from old.status)) then
    new.status_changed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_request_stage_changed on public.requests;
create trigger trg_request_stage_changed
  before update on public.requests
  for each row execute function public.touch_request_stage_changed();

-- ---------------------------------------------------------------------
--  2) جدول الإشعارات
--     الإشعار موجَّه إمّا لدور في سير العمل (target_role) — يراه كل من
--     يحمل هذا الدور — أو لمستخدم بعينه (target_uid) مثل مقدّم الطلب عند
--     الرفض/الأرشفة.
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id          bigint generated always as identity primary key,
  target_role text,                 -- دور سير العمل المستهدف (أو null)
  target_uid  uuid,                 -- مستخدم بعينه (أو null)
  request_id  uuid references public.requests(id) on delete cascade,
  message     text not null,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists idx_notif_role on public.notifications (target_role, is_read);
create index if not exists idx_notif_uid  on public.notifications (target_uid, is_read);
create index if not exists idx_notif_req  on public.notifications (request_id);

alter table public.notifications enable row level security;

-- قراءة: المستخدم يرى إشعارات دوره أو الموجّهة له شخصيًا
drop policy if exists notif_read on public.notifications;
create policy notif_read on public.notifications for select
  using (
    target_uid = auth.uid()
    or target_role = (select role from public.profiles where id = auth.uid())
  );

-- تعليم كمقروء: نفس نطاق الرؤية
drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications for update
  using (
    target_uid = auth.uid()
    or target_role = (select role from public.profiles where id = auth.uid())
  );

-- لا إدراج/حذف من العميل — الإدراج يتم فقط عبر trigger (security definer).

-- ---------------------------------------------------------------------
--  3) توليد الإشعارات عند تغيّر حالة/مرحلة الطلب
--     كل insert مغلّف بمعالجة استثناء: فشل الإشعار لا يُفشل العملية.
-- ---------------------------------------------------------------------
create or replace function public.notify_request_status()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_uid  uuid;
  v_name text := coalesce(new.entity, '');
begin
  begin
    if (tg_op = 'INSERT') then
      -- طلب جديد: يبدأ على المرحلة 2 (رئيس الحسابات)
      v_role := role_for_stage(new.current_stage_order);
      if v_role is not null then
        insert into public.notifications(target_role, request_id, message)
        values (v_role, new.id, 'طلب صرف جديد — ' || v_name || ' بانتظار اعتمادك');
      end if;
      return new;
    end if;

    if (tg_op = 'UPDATE') then
      -- رفض: أبلغ مقدّم الطلب
      if (new.status = 'rejected' and old.status is distinct from 'rejected') then
        v_uid := nullif(new.submitted_by->>'uid','')::uuid;
        if v_uid is not null then
          insert into public.notifications(target_uid, request_id, message)
          values (v_uid, new.id, 'تم رفض طلب الصرف — ' || v_name);
        end if;
        return new;
      end if;

      -- أرشفة (اكتمال): أبلغ مقدّم الطلب
      if (new.status = 'archived' and old.status is distinct from 'archived') then
        v_uid := nullif(new.submitted_by->>'uid','')::uuid;
        if v_uid is not null then
          insert into public.notifications(target_uid, request_id, message)
          values (v_uid, new.id, 'تم اكتمال وأرشفة طلب الصرف — ' || v_name);
        end if;
        return new;
      end if;

      -- تقدّم لمرحلة تالية (ما زال قيد الاعتماد): أبلغ صاحب المرحلة الجديدة
      if (new.status = 'pending'
          and new.current_stage_order is distinct from old.current_stage_order) then
        v_role := role_for_stage(new.current_stage_order);
        if v_role is not null then
          insert into public.notifications(target_role, request_id, message)
          values (v_role, new.id, 'طلب صرف — ' || v_name || ' بانتظار اعتمادك');
        end if;
      end if;
    end if;

  exception when others then
    -- لا تدع فشل الإشعار يعطّل عملية الاعتماد/التقديم الأساسية
    null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_request_ins on public.requests;
create trigger trg_notify_request_ins
  after insert on public.requests
  for each row execute function public.notify_request_status();

drop trigger if exists trg_notify_request_upd on public.requests;
create trigger trg_notify_request_upd
  after update on public.requests
  for each row execute function public.notify_request_status();

-- =====================================================================
--  انتهى 01. لا يتطلّب أي تعديل يدوي على البيانات القائمة.
--  ملاحظة: يلزم تفعيل Realtime على جدول notifications لو أردنا الجرس
--  الفوري؛ وإلا يعمل الجرس عبر الاستطلاع (polling) الحالي كل 20 ثانية.
-- =====================================================================
