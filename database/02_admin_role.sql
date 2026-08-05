-- =====================================================================
--  02 — دور الأدمن + دالة الدور الحالي (أساس للـSLA وإدارة المستخدمين)
--  إضافي وآمن: يوسّع قيم role المسموحة فقط، لا يمسّ أي صف قائم.
-- =====================================================================

-- إضافة قيمة 'admin' لقائمة الأدوار المسموحة
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('accountant','accounts_manager','finance_manager',
                  'general_manager','bank_officer','admin'));

-- دالة مساعدة تُرجع دور المستخدم الحالي (تُستخدم في سياسات RLS للأدمن)
create or replace function public.current_role_of()
returns text
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;
