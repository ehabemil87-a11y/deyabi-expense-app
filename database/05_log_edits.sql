-- =====================================================================
--  05 — تسجيل تعديلات موظف الحسابات في سجل التدقيق
--  يوسّع log_request_history() ليلتقط تعديل حقول الطلب الأساسية (action='edited')
--  عندما لا يكون هناك انتقال حالة/مرحلة. التحديثات التي تخصّ المرفقات فقط أو
--  الاعتمادات فقط لا تُسجَّل كتعديل. مغلّف بمعالجة استثناء (لا يعطّل العملية).
-- =====================================================================

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
  v_changes text[] := '{}';
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
        v_stage  := old.current_stage_order;
        v_action := case when old.current_stage_order = 5 then 'disbursed' else 'approved' end;
      else
        -- لا انتقال حالة/مرحلة: افحص تعديل الحقول الأساسية
        if new.entity              is distinct from old.entity              then v_changes := array_append(v_changes, 'الجهة'); end if;
        if new.amount              is distinct from old.amount              then v_changes := array_append(v_changes, 'المبلغ (' || coalesce(old.amount::text,'—') || ' ← ' || coalesce(new.amount::text,'—') || ')'); end if;
        if new.date                is distinct from old.date                then v_changes := array_append(v_changes, 'التاريخ'); end if;
        if new.purpose             is distinct from old.purpose             then v_changes := array_append(v_changes, 'الغرض'); end if;
        if new.payment_method      is distinct from old.payment_method      then v_changes := array_append(v_changes, 'طريقة السداد'); end if;
        if new.disbursement_status is distinct from old.disbursement_status then v_changes := array_append(v_changes, 'حالة الصرف'); end if;
        if new.notes               is distinct from old.notes               then v_changes := array_append(v_changes, 'ملاحظات'); end if;

        if array_length(v_changes, 1) is null then
          return new;   -- تحديث مرفقات/اعتمادات فقط — ليس تعديلًا للحقول
        end if;

        insert into public.request_history(request_id, action, stage_order, actor_uid, actor_name, comment)
        values (new.id, 'edited', old.current_stage_order, v_actor, v_name,
                'تعديل: ' || array_to_string(v_changes, '، '));
        return new;
      end if;

      -- فرع الانتقال (اعتماد/رفض/أرشفة/صرف)
      v_comment := nullif(new.approvals->(v_stage::text)->>'comment','');
      insert into public.request_history(request_id, action, stage_order, actor_uid, actor_name, comment)
      values (new.id, v_action, v_stage, v_actor, v_name, v_comment);
    end if;

  exception when others then
    null;
  end;
  return new;
end;
$$;
