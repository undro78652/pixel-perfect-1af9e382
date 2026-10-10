import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { loginIdFor, normalizeMobile } from "./format";

const mobile = z.string().trim().refine((m) => !!normalizeMobile(m), "Enter a valid 10-digit Indian mobile number");
const password = z.string().min(8, "Password must be at least 8 characters").max(72);
const name = z.string().trim().min(1, "Name is required").max(100);

/** One-time setup of the first Society admin. Locked once any Society admin exists. */
export const bootstrapAdmin = createServerFn({ method: "POST" })
  .inputValidator((d) =>
    z.object({ setupCode: z.string().min(1).max(200), fullName: name, mobile, password,
      houseNumber: z.string().trim().min(1).max(30), block: z.string().trim().max(30).optional() }).parse(d))
  .handler(async ({ data }) => {
    const code = process.env["SETUP_CODE"];
    if (!code || data.setupCode !== code) return { ok: false, error: "Setup code is incorrect" };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const sa = supabaseAdmin as any;
    const { count } = await sa.from("user_roles").select("id", { count: "exact", head: true }).eq("role", "society_admin");
    if ((count ?? 0) > 0) return { ok: false, error: "Initial setup has already been completed" };
    const email = await loginIdFor(data.mobile);
    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      email, password: data.password, email_confirm: true,
      user_metadata: { full_name: data.fullName, mobile: data.mobile },
    });
    if (error || !created.user) return { ok: false, error: error?.message ?? "Could not create account" };
    const uid = created.user.id;
    const { data: house, error: he } = await sa.from("houses")
      .insert({ house_number: data.houseNumber, block: data.block || null, primary_admin: uid, owner_name: data.fullName, owner_since: new Date().toISOString().slice(0, 10) })
      .select("id").single();
    if (he) return { ok: false, error: he.message };
    await sa.from("memberships").insert({ user_id: uid, house_id: house.id, relation: "owner", is_house_admin: true, status: "active", started_at: new Date().toISOString().slice(0, 10) });
    await sa.from("user_roles").insert({ user_id: uid, role: "society_admin" });
    await sa.from("profiles").update({ status: "active" }).eq("id", uid);
    await sa.from("audit_log").insert({ actor: uid, action: "setup.first_admin", entity_type: "profile", entity_id: uid, details: { house: data.houseNumber } });
    return { ok: true, error: null };
  });

export const setupStatus = createServerFn({ method: "GET" }).handler(async () => {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { count } = await (supabaseAdmin as any).from("user_roles").select("id", { count: "exact", head: true }).eq("role", "society_admin");
  return { done: (count ?? 0) > 0 };
});

/** Admin (or manager with membership review) creates an account with a temporary password. */
export const provisionAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d) => z.object({ fullName: name, mobile, tempPassword: password, houseId: z.string().uuid(),
    relation: z.enum(["owner", "tenant", "family"]), isHouseAdmin: z.boolean() }).parse(d))
  .handler(async ({ data, context }) => {
    const { data: allowed } = await (context.supabase as any).rpc("has_perm", { _uid: context.userId, _perm: "membership.review" });
    if (!allowed) return { ok: false, error: "You do not have permission to create accounts" };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      email: await loginIdFor(data.mobile), password: data.tempPassword, email_confirm: true,
      user_metadata: { full_name: data.fullName, mobile: data.mobile, must_change_password: true },
    });
    if (error || !created.user) {
      const msg = error?.message?.toLowerCase().includes("already") ? "An account with this mobile number already exists" : error?.message;
      return { ok: false, error: msg ?? "Could not create account" };
    }
    const { error: e2 } = await (context.supabase as any).rpc("attach_provisioned_member", {
      _user: created.user.id, _house: data.houseId, _relation: data.relation, _is_house_admin: data.isHouseAdmin });
    if (e2) return { ok: false, error: e2.message };
    return { ok: true, error: null };
  });

/** Society admin issues a temporary password after offline identity check. Existing passwords are never readable. */
export const resetPassword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d) => z.object({ userId: z.string().uuid(), tempPassword: password, reason: z.string().trim().min(3).max(300) }).parse(d))
  .handler(async ({ data, context }) => {
    const { data: isAdmin } = await (context.supabase as any).rpc("is_admin", { _uid: context.userId });
    if (!isAdmin) return { ok: false, error: "Only the Society admin can reset passwords" };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.auth.admin.updateUserById(data.userId, { password: data.tempPassword });
    if (error) return { ok: false, error: error.message };
    const { error: e2 } = await (context.supabase as any).rpc("log_password_reset", { _user: data.userId, _reason: data.reason });
    if (e2) return { ok: false, error: e2.message };
    return { ok: true, error: null };
  });
