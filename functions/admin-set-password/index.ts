// =====================================================================
//  Edge Function: admin-set-password  (نظام طلبات الصرف)
//  يتيح للأدمن إعادة تعيين كلمة مرور أي مستخدم. يتحقق أولًا أن المستدعي أدمن.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) return json({ error: "غير مصرح" }, 401);
    const { data: callerProfile } = await admin
      .from("profiles").select("role").eq("id", caller.user.id).single();
    if (callerProfile?.role !== "admin") return json({ error: "هذه العملية للأدمن فقط" }, 403);

    const { user_id, password } = await req.json();
    if (!user_id || !password) return json({ error: "بيانات ناقصة" }, 400);
    if (String(password).length < 6) return json({ error: "كلمة المرور قصيرة (6 أحرف على الأقل)" }, 400);

    const { error: updErr } = await admin.auth.admin.updateUserById(user_id, { password });
    if (updErr) return json({ error: updErr.message }, 400);
    return json({ ok: true }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
