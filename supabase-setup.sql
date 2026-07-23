-- =========================================================================
-- نظام طلبات الصرف — مجموعة الذيابي
-- سكريبت إعداد قاعدة البيانات على Supabase
--
-- طريقة الاستخدام: من لوحة Supabase اذهب إلى SQL Editor → New query،
-- الصق هذا الملف بالكامل، ثم اضغط Run. يمكن تشغيله مرة واحدة فقط في مشروع جديد.
-- =========================================================================

-- تفعيل الإضافة اللازمة لتوليد معرّفات UUID
create extension if not exists pgcrypto;

-- -------------------------------------------------------------------------
-- 1) جدول الملفات الشخصية (profiles) — يربط كل مستخدم بدوره في سير العمل
-- -------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  name       text,
  role       text check (role in ('accountant','accounts_manager','finance_manager','general_manager','bank_officer')),
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles readable by authenticated users" on public.profiles;
create policy "profiles readable by authenticated users"
  on public.profiles for select
  using (auth.role() = 'authenticated');

-- لا توجد سياسة إضافة/تعديل من العميل عمدًا — الأدوار تُحدَّد فقط من لوحة
-- Supabase (Table Editor) بواسطة المسؤول، وليس من داخل التطبيق نفسه.

-- عند إنشاء أي مستخدم جديد في Authentication، يُنشأ له تلقائيًا صف فارغ هنا
-- (بدون دور بعد) بدلًا من الاضطرار لإنشائه يدويًا من الصفر في كل مرة —
-- كل ما يتبقى هو فتح الصف وتحديد قيمة role.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name, role)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', new.email), null)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- -------------------------------------------------------------------------
-- 2) جدول طلبات الصرف (requests)
-- -------------------------------------------------------------------------
create table if not exists public.requests (
  id                  uuid primary key default gen_random_uuid(),
  request_no          bigint generated always as identity,  -- رقم الطلب (م) تلقائي ومتسلسل من القاعدة نفسها
  date                date,
  entity              text,
  purpose             text,
  payment_method      text,
  amount              numeric default 0,
  disbursement_status text,
  notes               text,
  submitted_by        jsonb default '{}'::jsonb,   -- {uid, name, role}
  submitted_at        timestamptz default now(),
  last_updated        timestamptz default now(),
  status              text default 'pending',      -- pending | rejected | archived
  current_stage_order int default 2,
  rejected_at_order   int,
  approvals           jsonb default '{}'::jsonb,    -- { "1": {decision,comment,by,name,at}, ... }
  attachments          jsonb default '[]'::jsonb    -- [{name, path, uploadedAt}]
);

alter table public.requests enable row level security;

drop policy if exists "requests readable by authenticated" on public.requests;
create policy "requests readable by authenticated"
  on public.requests for select
  using (auth.role() = 'authenticated');

drop policy if exists "requests insertable by authenticated" on public.requests;
create policy "requests insertable by authenticated"
  on public.requests for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "requests updatable by authenticated" on public.requests;
create policy "requests updatable by authenticated"
  on public.requests for update
  using (auth.role() = 'authenticated');

-- ملحوظة أمنية: مثل أي نظام داخلي صغير وموثوق، أي مستخدم مسجّل دخول يقدر
-- يحدّث أي طلب على مستوى القاعدة — التحقق من "هل دوره يطابق المرحلة
-- الحالية؟" يتم داخل واجهة التطبيق فقط. للحماية الإضافية لاحقًا يمكن نقل
-- منطق الاعتماد إلى Supabase Edge Function ثم تشديد سياسة update.

-- -------------------------------------------------------------------------
-- 3) تخزين المرفقات (Storage bucket)
-- -------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

drop policy if exists "attachments readable by authenticated" on storage.objects;
create policy "attachments readable by authenticated"
  on storage.objects for select
  using (bucket_id = 'attachments' and auth.role() = 'authenticated');

drop policy if exists "attachments insertable by authenticated" on storage.objects;
create policy "attachments insertable by authenticated"
  on storage.objects for insert
  with check (bucket_id = 'attachments' and auth.role() = 'authenticated');

-- =========================================================================
-- انتهى الإعداد. الخطوة التالية: أنشئ 5 مستخدمين من Authentication > Users،
-- ثم افتح كل صف تلقائي الإنشاء في Table Editor > profiles وحدّد له name و role.
-- =========================================================================
