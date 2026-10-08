import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { db } from "./db";

export type Me = {
  id: string;
  full_name: string;
  mobile: string;
  status: "pending_society" | "pending_household" | "active" | "rejected" | "suspended";
  status_reason: string | null;
  must_change_password: boolean;
  roles: string[];
  perms: string[];
  houseId: string | null;
  houseNumber: string | null;
  isHouseAdmin: boolean;
  collectorAccountId: string | null;
  isAdmin: boolean;
  isManager: boolean;
  can: (perm: string) => boolean;
};

export async function loadMe(): Promise<Me | null> {
  const { data: u } = await supabase.auth.getUser();
  if (!u.user) return null;
  const uid = u.user.id;
  const [{ data: p }, { data: roles }, { data: perms }, { data: m }] = await Promise.all([
    db.from("profiles").select("*").eq("id", uid).maybeSingle(),
    db.from("user_roles").select("role").eq("user_id", uid),
    db.from("manager_permissions").select("permission").eq("user_id", uid),
    db.from("memberships").select("house_id,is_house_admin,houses(house_number)").eq("user_id", uid).eq("status", "active").maybeSingle(),
  ]);
  if (!p) return null;
  let collector: string | null = null;
  if (p.status === "active") {
    const { data: a } = await db.from("fund_accounts").select("id").eq("holder_user", uid).eq("kind", "collector").eq("active", true).maybeSingle();
    collector = a?.id ?? null;
  }
  const r: string[] = (roles ?? []).map((x: { role: string }) => x.role);
  const pm: string[] = (perms ?? []).map((x: { permission: string }) => x.permission);
  const active = p.status === "active" && !!m;
  const isAdmin = active && r.includes("society_admin");
  const isManager = active && r.includes("society_manager");
  return {
    ...p,
    roles: r,
    perms: pm,
    houseId: m?.house_id ?? null,
    houseNumber: m?.houses?.house_number ?? null,
    isHouseAdmin: !!m?.is_house_admin,
    collectorAccountId: collector,
    isAdmin,
    isManager,
    can: (perm: string) => isAdmin || (isManager && pm.includes(perm)),
  };
}

export function useMe() {
  return useQuery({ queryKey: ["me"], queryFn: loadMe, staleTime: 30_000 });
}

export const PERMISSION_GROUPS: { group: string; items: { key: string; label: string }[] }[] = [
  { group: "Membership", items: [{ key: "membership.review", label: "Review new-house and membership requests, create accounts" }] },
  { group: "Houses", items: [{ key: "houses.manage", label: "Create and edit houses, change house admins" }] },
  { group: "Charges", items: [{ key: "charges.manage", label: "Prepare charges and maintenance schedules" }] },
  { group: "Projects", items: [{ key: "projects.manage", label: "Create and edit projects" }] },
  { group: "Official updates", items: [{ key: "updates.publish", label: "Publish and edit official updates" }] },
  { group: "Complaints", items: [
    { key: "complaints.self_assign", label: "Take responsibility for unassigned complaints" },
    { key: "complaints.priority", label: "Change complaint priority" },
    { key: "complaints.manage", label: "Change status, assign, reopen complaints" },
  ] },
  { group: "Suggestions", items: [{ key: "suggestions.manage", label: "Manage suggestions" }] },
  { group: "Financial recording", items: [{ key: "finance.record", label: "Record collections, transfers, opening funds, expense payments, refunds (no approval power)" }] },
  { group: "Reports", items: [{ key: "reports.export", label: "Export reports (viewing is open to all members)" }] },
  { group: "Moderation", items: [{ key: "moderation", label: "Remove comments with a reason" }] },
];
export const MANAGER_TEMPLATE = ["complaints.self_assign"];
