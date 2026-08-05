# HANDOFF — نظام طلبات الصرف | مجموعة الذيابي

> **الغرض من هذا الملف:** نقل المشروع بالكامل إلى وكيل Claude Code (أو أي مطوّر جديد)
> بكل السياق والقرارات التقنية والحالة الحالية والمهام المتبقية، بدون الحاجة للرجوع
> لأي محادثة سابقة.
>
> **آخر تحديث:** يوليو 2026 — الإصدار الحالي: **v8**
>
> **لغة التواصل مع المالك:** العربية (لهجة مصرية). المالك ليس مطوّرًا — يحتاج خطوات
> تفصيلية "خطوة بخطوة" مع أسماء الأزرار الحرفية، وليس أوامر terminal أو مصطلحات مجرّدة.

---

## 1. نظرة عامة على المشروع

نظام ويب داخلي لإدارة **طلبات الصرف المالية** في مجموعة الذيابي (السعودية)، يتتبّع كل
طلب عبر **دورة اعتماد من 6 مراحل** لا يمكن تجاوز أي مرحلة فيها.

**المتطلبات الأصلية من المالك:**
- واجهة عربية RTL احترافية، شعار الشركة أعلى يسار كل الشاشات.
- نفس حقول شيت Excel القديم بالضبط (م، التاريخ، طريقة السداد، الجهة، الغرض، المبلغ، حالة الصرف، ملاحظات).
- رفع مرفقات لكل طلب + تسجيل تاريخ الرفع تلقائيًا.
- سلسلة اعتمادات متسلسلة، كل مرحلة تكتب تعليقًا (سواء اعتمدت أو رفضت)، والجميع يرى تعليقات الآخرين.
- لوحة مؤشرات (KPI) موحّدة يراها كل المستخدمين + فلاتر بكل الأنواع.
- تصدير Excel بنفس محتوى الشاشة + حالة الاعتماد المحدّثة + ملاحظات كل مرحلة.
- حساب مستخدم منفصل لكل دور.

---

## 2. الحالة الحالية — ما هو **مكتمل وشغّال** ✅

| البند | الحالة |
|---|---|
| التطبيق (واجهة + منطق) في ملف واحد `index.html` | ✅ مكتمل ومُختبَر |
| مشروع Supabase منشأ ومُعدّ بالكامل | ✅ `deyabi-disbursement` |
| جداول `profiles` و `requests` + RLS + Storage bucket | ✅ منشأة عبر `supabase-setup.sql` |
| 5 مستخدمين منشأين بأدوارهم | ✅ (القائمة في القسم 5) |
| دورة الاعتماد الكاملة (6 مراحل) مُختبَرة من الطرفين | ✅ اختبرها المالك بنجاح |
| رفع/تنزيل المرفقات | ✅ بعد إصلاح مشكلة الأسماء العربية |
| تصدير Excel | ✅ |
| استيراد الطلبات القديمة من CSV | ✅ نجح المالك في استيرادها بنفسه |
| رفع المشروع على GitHub | ✅ `ehabemil87-a11y/deyabi-expense-app` |
| نشر على GitHub Pages | ⚠️ **غير مؤكد** — راجع القسم 9 |
| إشعارات البريد الإلكتروني | ❌ **قيد التنفيذ** — راجع القسم 8 (المهمة الرئيسية المتبقية) |

---

## 3. القرارات المعمارية المهمة (ولماذا اتُخذت)

### 3.1 لماذا Supabase وليس Firebase؟
بدأ المشروع على **Firebase** واكتمل عليه فعليًا، ثم **تم ترحيله بالكامل إلى Supabase**
لسبب واحد حاسم: اعتبارًا من فبراير 2026، أصبحت خدمة **Firebase Storage تتطلب ترقية
لخطة Blaze** (وبالتالي ربط بطاقة ائتمان)، **والمالك ليس لديه بطاقة ائتمان**.

Supabase تقدّم: 500MB قاعدة بيانات + **1GB تخزين ملفات** + 50k مستخدم شهريًا،
**بدون أي بطاقة على الإطلاق**.

> ⚠️ **قيد مهم يجب تذكيره للمالك دوريًا:** أي مشروع Supabase مجاني **يتوقف تلقائيًا
> (Pause)** بعد **7 أيام** من عدم الاستخدام. الحل: زر `Restore/Resume` من اللوحة،
> ولا تُفقد أي بيانات. حل استباقي مقترح: ping دوري عبر cron-job.org.

**⛔ لا ترجع للـ Firebase.** كل آثاره أُزيلت من المشروع (firebase.json, firestore.rules,
storage.rules, .firebaserc, .github/workflows/deploy.yml).

### 3.2 لماذا Polling وليس Realtime؟
تم تعمّد **عدم** استخدام Supabase Realtime لتقليل نقاط الفشل. بدلًا منه:
- تحديث تلقائي صامت كل **20 ثانية** (`startPolling()`).
- تحديث فوري عند عودة التبويب للواجهة (`visibilitychange`).
- تحديث فوري بعد أي إجراء يقوم به المستخدم نفسه.
- زر يدوي **"↻ تحديث"** فوق الجدول.

لو أردنا Realtime لاحقًا: تفعيل Replication على جدول `requests` من
Database → Replication، ثم `sb.channel(...).on('postgres_changes', ...)`.

### 3.3 لماذا ملف HTML واحد؟
لا build step، لا npm، لا bundler. المالك غير مطوّر ويحتاج أن يفتح الملف مباشرة
أو يرفعه كما هو. **حافظ على هذا القيد** — أي مكتبة جديدة تُضاف عبر CDN فقط.

المكتبات الحالية (CDN):
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

---

## 4. دورة العمل (Workflow) — 6 مراحل

```
1. موظف الحسابات   → يرفع الطلب + المرفقات + يوقّع (تلقائي لحظة الإنشاء)
2. رئيس الحسابات   → يوقّع + تعليق
3. المدير المالي    → يوقّع + تعليق
4. المدير العام     → يوقّع + تعليق
5. مسؤول البنوك    → يوقّع + ينفّذ الصرف فعليًا + يرفع إثبات الصرف
6. موظف الحسابات   → يستلم الطلب مجددًا ويؤرشفه (إغلاق الدورة)
```

**تفاصيل حرجة يجب فهمها:**

- **المرحلة 1 لا تظهر كإجراء في الواجهة أبدًا.** يتم تسجيلها تلقائيًا في `approvals["1"]`
  لحظة إنشاء الطلب، والطلب يُولد مباشرة بـ `current_stage_order = 2`.
- **دور `accountant` يملك مرحلتين** (1 و 6). التمييز بينهما عبر `activeStage.isArchive`.
- **زر "طلب صرف جديد" يظهر فقط لدور `accountant`** (يُخفى عبر `style.display` في `handleSignedIn`).
- **الرفض في أي مرحلة يوقف الطلب نهائيًا** (`status='rejected'`, `rejected_at_order=N`).
- **الأرشفة** تضع `status='archived'` و `current_stage_order = LAST_ORDER + 1` (أي 7).
- المستخدم يرى زر الإجراء **فقط** إذا كان `activeStage.role === currentUser.role`
  و `status === 'pending'`.

### الأدوار وقيمها الحرفية في قاعدة البيانات

| الدور في الواجهة | قيمة `role` | المرحلة |
|---|---|---|
| موظف الحسابات | `accountant` | 1 (تلقائي) و 6 (أرشفة) |
| رئيس الحسابات | `accounts_manager` | 2 |
| المدير المالي | `finance_manager` | 3 |
| المدير العام | `general_manager` | 4 |
| مسؤول البنوك | `bank_officer` | 5 (تنفيذ الصرف) |

---

## 5. بيانات الوصول والحسابات

### مشروع Supabase
```
Project name : طلبات الصرف
Project ref  : mwppgpllmtxfqxmgmyju
URL          : https://mwppgpllmtxfqxmgmyju.supabase.co
Region       : Oceania (Sydney) — ap-southeast-2
Plan         : Free
Org          : AlDeyabi
```

مفتاح `anon public` مضمّن مباشرة في `index.html` (سطر ~516). **هذا آمن ومقصود** —
الحماية عبر RLS، وليس بإخفاء المفتاح.

### المستخدمون الخمسة (منشأون بالفعل في Authentication + profiles)

| البريد | الاسم | `role` |
|---|---|---|
| abdulwahab@aldeyabi.com | محمد القحطاني محاسب | `accountant` |
| m.soliman@aldeyabi.com | محمد سليمان رئيس الحسابات | `accounts_manager` |
| tayyash@aldeyabi.com | طارق عياش المدير المالي | `finance_manager` |
| maged@aldeyabi.com | ماجد الذيابي المدير العام | `general_manager` |
| a.khaled@aldeyabi.com | عبدالرحمن مسؤول البنك | `bank_officer` |

> **كلمات المرور بحوزة المالك فقط** ولم تُشارك. لا توجد طريقة لاستعادتها من اللوحة
> (Supabase تخزّنها مشفّرة لا رجعة فيه). لتغيير كلمة مرور: احذف المستخدم وأعد إنشاءه
> — لكن انتبه، سيتغيّر الـ UID وبالتالي يجب تحديث/إعادة إنشاء صفه في `profiles`.

### GitHub
```
Repo  : ehabemil87-a11y/deyabi-expense-app
الملفات المرفوعة: index.html, README.md, supabase-setup.sql, assets/logo.jpg
```

### Resend (خدمة الإيميل — قيد الإعداد)
حساب منشأ، والدومين `aldeyabi.com` مُضاف وفي انتظار التحقق من DNS.
**لم يُنشأ API Key بعد.**

---

## 6. مخطط قاعدة البيانات

### جدول `profiles`
```sql
id         uuid primary key references auth.users(id) on delete cascade
email      text
name       text
role       text check (role in ('accountant','accounts_manager',
                                'finance_manager','general_manager','bank_officer'))
created_at timestamptz default now()
```
- **RLS:** قراءة لأي `authenticated`، **الكتابة ممنوعة تمامًا من العميل** (`allow write: if false`).
  الأدوار تُحدَّد يدويًا من Table Editor فقط — قرار أمني مقصود حتى لا يمنح أحد نفسه دور المدير العام.
- **Trigger `on_auth_user_created`:** ينشئ صفًا تلقائيًا في `profiles` عند إنشاء أي مستخدم
  في `auth.users`، مع `role = null`. هذا يوفّر على المالك نسخ الـ UID يدويًا (كان مصدر
  أخطاء متكررة في مرحلة Firebase).
- المستخدم بدون `role` يُرفض دخوله برسالة "حسابك غير مُفعّل بعد".

### جدول `requests`
```sql
id                  uuid primary key default gen_random_uuid()
request_no          bigint generated always as identity   -- رقم تسلسلي تلقائي
date                date
entity              text
purpose             text
payment_method      text
amount              numeric default 0
disbursement_status text            -- 'تم الصرف' | 'لم يتم الصرف'
notes               text
submitted_by        jsonb  -- {uid, name, role}
submitted_at        timestamptz default now()
last_updated        timestamptz default now()
status              text default 'pending'   -- pending | rejected | archived
current_stage_order int  default 2           -- يبدأ من 2 لأن المرحلة 1 تلقائية
rejected_at_order   int
approvals           jsonb default '{}'  -- {"1":{decision,comment,by,name,at}, "2":{...}}
attachments         jsonb default '[]'  -- [{name, path, uploadedAt}]
```

**⚠️ ملاحظة حرجة عن `jsonb`:** أعمدة `approvals` و `attachments` تُستبدل بالكامل عند
أي `update` (لا يوجد dot-path merge كما في Firestore). الكود يقوم بـ
**read-modify-write**: يقرأ القيمة الحالية من `allRequests` cache، يدمج الجديد، ثم يكتب
الكل. **لا تكسر هذا النمط.**

**RLS الحالي:** أي `authenticated` يستطيع select/insert/update. الحذف ممنوع.
التحقق من "هل دور المستخدم يطابق المرحلة الحالية؟" يتم **في الواجهة فقط** —
مقبول لفريق داخلي من 5 أشخاص موثوقين. للتشديد لاحقًا: انقل منطق `decide()` إلى
Edge Function ثم `allow update: if false`.

### Storage
```
bucket: attachments   (private — public = false)
مسار الملف: {request_id}/{timestamp}_{random}{ext}
```
- **Bucket خاص** → الروابط تُولَّد كـ **Signed URLs** صالحة لساعة، تُنشأ عند فتح كل طلب.
- **قيد حرج:** مفاتيح Storage لا تقبل إلا ASCII آمن. أسماء الملفات العربية كانت تسبب
  خطأ `Invalid key`. الحل المطبّق: دالة `safeStorageKey()` تولّد مفتاحًا إنجليزيًا
  عشوائيًا للتخزين، بينما الاسم العربي الأصلي يُحفظ في حقل `name` داخل الـ jsonb
  ويُعرض للمستخدم. **حافظ على هذا الفصل.**

---

## 7. خريطة الكود (`index.html` — 1322 سطر)

```
1–500      HTML: شاشة الدخول، shell التطبيق، التبويبات، الجداول، المودالات
             + CSS كامل (design tokens بهوية الشركة: ذهبي #b8874f على خلفية #faf7f1)
515–516    SUPABASE_URL و SUPABASE_ANON_KEY
523–533    ROLE_LABELS
535–544    STAGES  ← مصدر الحقيقة الوحيد لدورة العمل. أي تعديل على المراحل يبدأ هنا.
546–550    حالة عامة: currentUser, allRequests, pendingFiles, pendingActionFiles, pollTimer
553–610    مساعدات: showToast, setLoading, fmtMoney, safeStorageKey, formatSerial,
                     fmtDate, fmtDateTime, openModal, closeModal
612–622    statusInfo(req) → {text, cls, kind}
~625–705   المصادقة: تسجيل الدخول، الخروج، handleSignedIn، استعادة الجلسة عند التحميل
707–731    loadRequests / startPolling / stopPolling / زر التحديث / visibilitychange
733–751    populatePaymentMethodFilter / populateApprovalFilter
753–784    renderDashboard  (بطاقات KPI + صف المراحل)
786–842    getFilteredRequests / renderTable / مستمعو الفلاتر
844–870    escapeHtml / منطق فورم الطلب الجديد + renderFileList
872–945    إرسال طلب جديد (insert + رفع المرفقات + تسجيل توقيع المرحلة 1)
947–1199   openDetail(id)  ← الأكبر والأهم. يبني: الحقول، شريط المراحل، المرفقات
                              (signed URLs)، سجل الاعتمادات، صندوق الإجراء حسب الدور،
                              زر تنزيل الكل، ورافع المرفقات الإضافي
1201–1277  decide(requestId, stage, decision)  ← منطق الانتقال بين المراحل
1279–1322  تصدير Excel
```

### الدوال التي يجب فهمها قبل أي تعديل

**`STAGES`** — مصفوفة تعريف المراحل. كل عنصر: `{order, role, label, short, exportLabel}`
وبعضها `isDisbursement` أو `isArchive`. تُشتق منها: شريط التقدّم، الفلاتر، أعمدة
التصدير، ومنطق الصلاحيات. **أي تغيير في دورة العمل يبدأ من هنا.**

**`openDetail(id)`** — `async` لأنها تنتظر توليد الـ signed URLs. تبني الـ HTML كنص
ثم تحقنه عبر `innerHTML`، وبعدها **تربط المستمعات (listeners)**. عند إضافة أي عنصر
تفاعلي جديد: أضف الـ HTML في القالب **وأضف الربط بعد الحقن** — وإلا لن يعمل.

**`decide(requestId, stage, decision)`** — تعالج ثلاث حالات:
1. رفض → `status='rejected'` + `rejected_at_order`
2. أرشفة نهائية (`isArchive && approved`) → `status='archived'`
3. اعتماد عادي → `current_stage_order = order + 1`

وفي حالة `isDisbursement` تضيف: `disbursement_status` + رفع ملفات إثبات الصرف
ودمجها في `attachments`.

---

## 8. 🎯 المهمة الرئيسية المتبقية: إشعارات البريد الإلكتروني

### المطلوب من المالك حرفيًا
> "في حالة قبول الطلب أو رفضه، يجي ميل على ميل المرحلة التالية — بمعنى لو المحاسب
> بعت طلب، يرسل ميل تنبيه لرئيس الحسابات إن في طلب تم إرساله، وهكذا لكل مرحلة."

### الحالة الحالية للإعداد
1. ✅ حساب Resend منشأ.
2. ✅ الدومين `aldeyabi.com` مُضاف في Resend.
3. ⏳ **عالق هنا:** سجلات DNS أُعطيت للمالك ليمررها لمسؤول الدومين، **ولم تُضف بعد**.
4. ❌ API Key لم يُنشأ.
5. ❌ Edge Function لم تُكتب.
6. ❌ استدعاء الإشعار من الكود لم يُضف.

### سجلات DNS المطلوبة (القيم النهائية الحقيقية)

| Type | Name/Host | Value | TTL | Priority |
|---|---|---|---|---|
| TXT | `resend._domainkey.aldeyabi.com` | `p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDiH6G+lpdHN0RqdlHfNCoxJq6tZXAvBTDPvRGKKCYQ/8INr0yiFf8by52XgmPSdw4+JTPYIFfz5hzeS0wzlhvm69YkpSFSGk7gI4ev6+1UEclHmGBlIBUe+yRUOGmUQL1eDvi8jhXwUGQUVFPIa4Q0ZtEpx8IIlf9c0Qt3xKlXZwIDAQAB` | Auto | – |
| MX | `send.aldeyabi.com` | `feedback-smtp.us-east-1.amazonses.com` | Auto | 10 |
| TXT | `send.aldeyabi.com` | `v=spf1 include:amazonses.com ~all` | Auto | – |

> **لماذا التحقق من الدومين إلزامي؟** بدونه، Resend يسمح بالإرسال **فقط** إلى بريد
> صاحب الحساب نفسه (من `onboarding@resend.dev`). لن تصل الإشعارات لبقية الأربعة.
> **لا يوجد التفاف على هذا القيد** — هو سياسة كل مزوّدي البريد.

### خطة التنفيذ المقترحة (بعد تحقّق الدومين)

**الخطوة أ — API Key**
Resend → API Keys → Create → صلاحية `Sending access` → نسخ المفتاح مرة واحدة.

**الخطوة ب — تخزين المفتاح كسر (Secret) في Supabase**
Edge Functions → Secrets → إضافة `RESEND_API_KEY`.
**⛔ لا تضع المفتاح في `index.html` إطلاقًا** — على عكس مفتاح anon، هذا المفتاح سري
ويسمح بالإرسال باسم الشركة.

**الخطوة ج — Edge Function باسم `notify-stage`**
تُنشأ من اللوحة مباشرة: Edge Functions → Deploy a new function → Via Editor
(لا حاجة لـ CLI أو Docker — المالك غير مطوّر).

منطق الدالة:
1. تستقبل `{ requestId }`.
2. تقرأ الطلب من `requests` باستخدام Service Role.
3. تحدّد المرحلة الحالية → الدور المطلوب.
4. تجلب بريد/أسماء أصحاب هذا الدور من `profiles`.
5. ترسل عبر Resend API من `no-reply@send.aldeyabi.com`.
6. حالات خاصة: عند الرفض → أبلغ **مقدّم الطلب**. عند الأرشفة → لا إشعار (أو أبلغ الجميع).

**الخطوة د — الاستدعاء من الواجهة**
في نهاية `decide()` وبعد `insert` الطلب الجديد (كلاهما بعد نجاح العملية):
```js
sb.functions.invoke('notify-stage', { body: { requestId } })
  .catch(err => console.error('notify failed:', err));
```
**بدون `await`** — فشل الإشعار يجب ألّا يُفشل العملية الأساسية أو يُبطئ الواجهة.

**بديل أبسط لو تعذّر التحقق من الدومين نهائيًا:** استخدام Supabase Database Webhooks
مع خدمة بديلة، أو التخلي عن البريد لصالح **مؤشر "طلبات تنتظرك"** داخل التطبيق نفسه
(عدّاد على التبويب) — أقل فائدة لكن بلا أي اعتماد خارجي.

---

## 9. مهام ثانوية معلّقة

### 9.1 التأكد من نشر GitHub Pages
رُفعت الملفات بنجاح، لكن **لم يتأكد أن Pages مُفعّل ويعمل**.
المسار: Settings → Pages → Source: `Deploy from a branch` → Branch: `main` → Folder: `/ (root)` → Save.
الرابط المتوقع: `https://ehabemil87-a11y.github.io/deyabi-expense-app/`

### 9.2 مزامنة آخر إصدار مع GitHub
**المالك رفع نسخة أقدم على GitHub.** آخر تعديلات (v7/v8 — الأرقام الإنجليزية) قد لا
تكون موجودة هناك. **تحقّق من تطابق `index.html` على GitHub مع النسخة المحلية.**

### 9.3 مسألة الأرقام الإنجليزية — تحتاج تأكيدًا
شكوى المالك: "المبالغ جاية بالعربي عاوزها إنجليزي".
ما طُبّق:
- `fmtMoney` → `toLocaleString('en-US')`
- `fmtDate` / `fmtDateTime` → `toLocaleDateString('en-GB')`
- حقل إدخال المبلغ → `lang="en"`

**لم يؤكد المالك بعد أن المشكلة انتهت.** إن استمرت، السبب المرجّح هو
`<html lang="ar">` مع إعدادات نظام عربية. الحل الاحتياطي: إضافة
`font-feature-settings` أو تغليف الأرقام في عنصر بـ `lang="en"`.

### 9.4 إعادة ترقيم الطلبات (اختياري — أجّله المالك)
العدّاد بدأ من 5 لأن طلبات التجربة المحذوفة استهلكت 1–4.
قال المالك: "مش ضروري يكون البداية 1، المهم إنه مسلسل" → **مؤجّل**.
السكربت جاهز في `fix-request-numbering.sql` إن طُلب لاحقًا.
> **مهم:** العمود `generated always as identity` لا يقبل التحديث المباشر — السكربت
> يحوّله أولًا إلى `generated by default`.

---

## 10. المشاكل التي حُلّت (لا تكررها)

| المشكلة | السبب الجذري | الحل المطبّق |
|---|---|---|
| `Failed to fetch` عند الدخول | المالك يفتح HTML من داخل ملف ZIP مؤقت / نسخة قديمة بقيم placeholder | إعطاء كل إصدار **اسم ملف مختلف** (v2, v3...) + التشديد على Extract قبل الفتح |
| `Invalid key` عند رفع PDF | اسم ملف عربي في مسار Storage | `safeStorageKey()` |
| "حدث خطأ أثناء تحميل بيانات المستخدم" | RLS يمنع القراءة قبل نشر السياسات | نشر `supabase-setup.sql` |
| زر تنزيل المرفقات يختفي | كان داخل صندوق إجراء الأرشفة فقط | نُقل إلى قسم المرفقات الدائم |
| لا يمكن إعادة محاولة الرفع بعد الفشل | المرفقات تُضاف عند الإنشاء فقط | زر "+ إضافة مرفق جديد" لأي طلب `pending` |
| رسائل خطأ عامة غير مفيدة | لم تكن تُظهر رسالة المزوّد | إظهار `err.message` الفعلية في كل مسارات الرفع/الدخول |
| رقم الطلب يدوي وعرضة للتكرار | كان حقل نص حر | `request_no` identity + عرضه كـ `Serial N` |
| تحذير "destructive operation" في SQL Editor | `DROP POLICY IF EXISTS` الاحترازية | طبيعي — يُؤكَّد ويُكمَل |

---

## 11. قواعد عمل مع هذا المشروع

1. **العربية أولًا.** كل نصوص الواجهة والرسائل بالعربية. الكود وتعليقاته بالإنجليزية.
2. **ملف واحد.** لا build، لا npm، لا bundler. مكتبات جديدة عبر CDN فقط.
3. **اسم إصدار جديد لكل تسليم.** `deyabi-expense-app-vN.zip` — المالك واجه ارتباكًا
   حقيقيًا مع نسخ متعددة بنفس الاسم.
4. **تحقّق من الصياغة قبل التسليم:**
   ```bash
   python3 -c "import re;h=open('index.html',encoding='utf-8').read();\
   open('/tmp/a.js','w',encoding='utf-8').write(re.findall(r'<script>(.*?)</script>',h,re.S)[-1])"
   node --check /tmp/a.js
   ```
   وتأكد من توازن `<div>`/`</div>`.
5. **`STAGES` هو مصدر الحقيقة.** لا تُثبّت (hardcode) أرقام مراحل في أماكن متفرقة.
6. **أعمدة jsonb:** اقرأ ← ادمج ← اكتب. دائمًا.
7. **لا تكسر تدفق الأدوار** بإضافة صلاحيات عامة — كل زر إجراء مشروط بمطابقة الدور للمرحلة.
8. **عند شرح خطوة للمالك:** اذكر اسم الزر الحرفي وموقعه على الشاشة. لا تفترض معرفة تقنية.

---

## 12. ملفات المشروع

```
deyabi-expense-app/
├── index.html                  التطبيق بالكامل (1322 سطر) — الملف الوحيد المطلوب للتشغيل
├── supabase-setup.sql          سكربت الإعداد الكامل (شُغّل بالفعل — لا حاجة لإعادته)
├── fix-request-numbering.sql   سكربت اختياري لإعادة الترقيم من 1
├── README.md                   دليل الإعداد والاستخدام بالعربية للمالك
├── HANDOFF.md                  هذا الملف
└── assets/
    └── logo.jpg                شعار مجموعة الذيابي (مطلوب — يُشار إليه بـ assets/logo.jpg)
```

---

## 13. أول ما يجب فعله عند استلام المشروع

1. اقرأ `STAGES` و `openDetail()` و `decide()` في `index.html` — هذه ثلثا المنطق.
2. تحقّق من حالة مشروع Supabase (قد يكون Paused → اضغط Resume).
3. تحقّق مما إذا أُضيفت سجلات DNS (من لوحة Resend → Domains → هل الحالة `Verified`؟).
4. تحقّق من تطابق `index.html` على GitHub مع النسخة المحلية.
5. **المهمة الرئيسية:** أكمل إشعارات البريد (القسم 8).
