// =====================================================================
//  Edge Function: create-user  (نظام طلبات الصرف)
//  ينشئ مستخدمًا جديدًا (بريد + كلمة مرور + اسم + دور) — للأدمن فقط.
//  يتحقق أن المستدعي أدمن ثم يستخدم مفتاح الخدمة (السري) لإنشاء المستخدم.
//
//  SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY متوفّران تلقائيًا في بيئة الدالة.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_ROLES = [
  "accountant", "accounts_manager", "finance_manager",
  "general_manager", "bank_officer", "admin",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) التحقق أن المستدعي أدمن
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) return json({ error: "غير مصرح" }, 401);
    const { data: callerProfile } = await admin
      .from("profiles").select("role").eq("id", caller.user.id).single();
    if (callerProfile?.role !== "admin") return json({ error: "هذه العملية للأدمن فقط" }, 403);

    // 2) قراءة البيانات
    const { email, password, name, role } = await req.json();
    if (!email || !password || !name || !role) return json({ error: "بيانات ناقصة" }, 400);
    if (!ALLOWED_ROLES.includes(role)) return json({ error: "دور غير صالح" }, 400);
    if (String(password).length < 6) return json({ error: "كلمة المرور قصيرة (6 أحرف على الأقل)" }, 400);
    const cleanEmail = String(email).toLowerCase().trim();

    // 3) إنشاء مستخدم Auth (مؤكّد تلقائيًا)
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: cleanEmail, password, email_confirm: true, user_metadata: { name },
    });
    if (createErr) return json({ error: createErr.message }, 400);

    // 4) ضبط صف الملف الشخصي (تنشئه trigger تلقائيًا بدور null — نحدّثه هنا)
    const { error: profErr } = await admin.from("profiles")
      .upsert({ id: created.user!.id, email: cleanEmail, name, role, is_active: true });
    if (profErr) {
      await admin.auth.admin.deleteUser(created.user!.id); // تراجع
      return json({ error: profErr.message }, 400);
    }

    return json({ ok: true, id: created.user!.id }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
