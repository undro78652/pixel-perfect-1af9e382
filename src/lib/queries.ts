import { useQuery } from "@tanstack/react-query";
import { db, rows } from "./db";

export type Person = { id: string; full_name: string; mobile: string; status: string };
export function usePeople() {
  return useQuery({
    queryKey: ["people"],
    queryFn: () => rows<Person>(db.from("profiles").select("id,full_name,mobile,status").order("full_name")),
  });
}
export function useNameOf() {
  const q = usePeople();
  const m = new Map((q.data ?? []).map((p) => [p.id, p.full_name || "Member"]));
  return (id?: string | null) => (id ? m.get(id) ?? "Member" : "—");
}
export type House = { id: string; house_number: string; block: string | null; active: boolean; occupancy: string; primary_admin: string | null };
export function useHouses() {
  return useQuery({ queryKey: ["houses"], queryFn: () => rows<House>(db.from("houses").select("*").order("house_number")) });
}
export type Account = { id: string; kind: "collector" | "bank"; name: string; holder_user: string | null; active: boolean; posted_paise: number; reserved_paise: number; bank_name: string | null; masked_number: string | null };
export function useAccounts() {
  return useQuery({ queryKey: ["accounts"], queryFn: () => rows<Account>(db.from("v_account_balances").select("*").order("kind").order("name")) });
}
export function useActiveMembers(houseId?: string | null) {
  return useQuery({
    queryKey: ["members", houseId],
    queryFn: () => {
      let q = db.from("memberships").select("id,user_id,house_id,relation,is_house_admin,houses(house_number)").eq("status", "active");
      if (houseId) q = q.eq("house_id", houseId);
      return rows<any>(q);
    },
  });
}
export function useProjects() {
  return useQuery({ queryKey: ["projects"], queryFn: () => rows<any>(db.from("projects").select("*").order("created_at", { ascending: false })) });
}
export function useSettings() {
  return useQuery({ queryKey: ["settings"], queryFn: async () => (await db.from("society_settings").select("*").maybeSingle()).data });
}
