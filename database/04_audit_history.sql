-- =====================================================================
--  04 — سجل التدقيق (Audit Trail) — المرحلة ب
--  جدول append-only يسجّل كل انتقال في دورة الطلب تلقائيًا عبر trigger،
--  مستقل عن عمود approvals الـjsonb (الذي يمكن الكتابة فوقه). ينفّذ بعد 01.
-- =====================================================================

create table if not exists public.request_history (
  id          bigint generated always as identity primary key,
  request_id  uuid references public.requests(id) on delete cascade,
  action      text not null,   -- submitted | approved | disbursed | rejected | archived
  stage_order int,
  actor_uid   uuid,
  actor_name  text,
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_history_req on public.request_history(request_id, created_at);

alter table public.request_history enable row level security;

-- قراءة لأي مسجّل دخول (نفس نموذج بقية النظام)
drop policy if exists history_read on public.request_history;
create policy history_read on public.request_history for select
  using (auth.uid() is not null);

-- الإدراج فقط عبر trigger (security definer) — لا كتابة مباشرة من العميل.

-- ---------------------------------------------------------------------
--  trigger التسجيل: يلتقط كل انتقال حالة/مرحلة
-- ---------------------------------------------------------------------
create or replace function public.log_request_history()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_actor   uuid := auth.uid();
  v_name    text;
  v_stage   int;
  v_action  text;
  v_comment text;
begin
  begin
    select name into v_name from public.profiles where id = v_actor;

    if tg_op = 'INSERT' then
      insert into public.request_history(request_id, action, stage_order, actor_uid, actor_name, comment)
      values (new.id, 'submitted', 1,
              nullif(new.submitted_by->>'uid','')::uuid,
              coalesce(new.submitted_by->>'name', v_name),
              nullif(new.approvals->'1'->>'comment',''));
      return new;
    end if;

    if tg_op = 'UPDATE' then
      if (new.status = 'rejected' and old.status is distinct from 'rejected') then
        v_stage  := coalesce(new.rejected_at_order, old.current_stage_order);
        v_action := 'rejected';
      elsif (new.status = 'archived' and old.status is distinct from 'archived') then
        v_stage  := 6;
        v_action := 'archived';
      elsif (new.status = 'pending'
             and new.current_stage_order is distinct from old.current_stage_order) then
        v_stage  := old.current_stage_order;   -- المرحلة التي تم اعتمادها للتوّ
        v_action := case when old.current_stage_order = 5 then 'disbursed' else 'approved' end;
      else
        return new;
      end if;

      v_comment := nullif(new.approvals->(v_stage::text)->>'comment','');
      insert into public.request_history(request_id, action, stage_order, actor_uid, actor_name, comment)
      values (new.id, v_action, v_stage, v_actor, v_name, v_comment);
    end if;

  exception when others then
    null;   -- سجل التدقيق لا يجوز أن يعطّل العملية الأساسية
  end;
  return new;
end;
$$;

drop trigger if exists trg_history_ins on public.requests;
create trigger trg_history_ins
  after insert on public.requests
  for each row execute function public.log_request_history();

drop trigger if exists trg_history_upd on public.requests;
create trigger trg_history_upd
  after update on public.requests
  for each row execute function public.log_request_history();
