import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { AuthCard } from "@/components/auth-card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field, StatusBadge, SubmitButton } from "@/components/ui-kit";
import { db, rpc } from "@/lib/db";
import { loadMe } from "@/lib/me";
import { fmtDateTime } from "@/lib/format";
import { toast } from "sonner";

export const Route = createFileRoute("/status")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Account status — XYZ Society" },
      { name: "description", content: "Check the approval status of your XYZ Society account." },
      { property: "og:title", content: "Account status — XYZ Society" },
      { property: "og:description", content: "Approval status." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Status,
});

function Status() {
  const nav = useNavigate();
  const qc = useQueryClient();
  const me = useQuery({ queryKey: ["me"], queryFn: loadMe });
  const reqs = useQuery({
    queryKey: ["my-requests"],
    enabled: !!me.data,
    queryFn: async () => {
      const [m, h] = await Promise.all([
        db.from("memberships").select("*, houses(house_number)").eq("user_id", me.data!.id).order("created_at", { ascending: false }),
        db.from("house_requests").select("*").eq("user_id", me.data!.id).order("created_at", { ascending: false }),
      ]);
      return { memberships: m.data ?? [], houses: h.data ?? [] };
    },
  });
  const [house, setHouse] = useState("");
  const [busy, setBusy] = useState(false);
  const [joinErr, setJoinErr] = useState<string | null>(null);
  useEffect(() => { const e = sessionStorage.getItem("join_error"); if (e) { setJoinErr(e); sessionStorage.removeItem("join_error"); } }, []);
  useEffect(() => { if (!me.isLoading && !me.data) nav({ to: "/" }); }, [me.isLoading, me.data, nav]);
  useEffect(() => { if (me.data?.status === "active" && me.data.houseId) nav({ to: "/overview" }); }, [me.data, nav]);

  if (!me.data) return <AuthCard title="Account status">Loading…</AuthCard>;
  const p = me.data;
  const hasPending = reqs.data?.memberships.some((m: any) => m.status === "pending") || reqs.data?.houses.some((h: any) => h.status === "pending");
  const signOut = async () => { qc.clear(); await supabase.auth.signOut(); nav({ to: "/", replace: true }); };

  return (
    <AuthCard title={`Hello, ${p.full_name || "resident"}`} subtitle="You can use society pages once your membership is approved." footer={<button className="underline" onClick={signOut}>Sign out</button>}>
      <div className="space-y-4">
        <div className="flex items-center gap-2"><span className="text-sm text-muted-foreground">Account:</span><StatusBadge s={p.status} /></div>
        {p.status_reason && <p className="text-sm">Reason: {p.status_reason}</p>}
        {joinErr && <p role="alert" className="text-sm text-destructive">Your request was not sent: {joinErr}</p>}
        {p.status === "suspended" && <p className="text-sm">Your access is suspended. Contact the Society admin.</p>}
        <div className="space-y-2">
          {reqs.data?.memberships.map((m: any) => (
            <div key={m.id} className="rounded-md border p-3 text-sm">Join house <b>{m.houses?.house_number}</b> — <StatusBadge s={m.status} /> <span className="text-muted-foreground">{fmtDateTime(m.created_at)}</span>{m.decision_reason && <p>Note: {m.decision_reason}</p>}</div>
          ))}
          {reqs.data?.houses.map((h: any) => (
            <div key={h.id} className="rounded-md border p-3 text-sm">New house <b>{h.house_number}</b> — <StatusBadge s={h.status} /> <span className="text-muted-foreground">{fmtDateTime(h.created_at)}</span>{h.decision_reason && <p>Note: {h.decision_reason}</p>}</div>
          ))}
        </div>
        {!hasPending && p.status !== "suspended" && (
          <form className="space-y-3 rounded-md border bg-muted/50 p-3" onSubmit={async (e) => {
            e.preventDefault(); setBusy(true);
            try { await rpc("request_house_membership", { _house_number: house, _relation: "family" }); toast.success("Request sent"); setJoinErr(null); qc.invalidateQueries(); }
            catch (x) { toast.error((x as Error).message); } finally { setBusy(false); }
          }}>
            <Field label="Request to join an existing house" htmlFor="hn"><Input id="hn" value={house} onChange={(e) => setHouse(e.target.value)} placeholder="House number" /></Field>
            <SubmitButton type="submit" pending={busy} disabled={!house.trim()}>Send request</SubmitButton>
            <p className="text-xs text-muted-foreground">To register a brand-new house, use <Link to="/register" className="underline">registration</Link> with a different flow, or ask the Society admin.</p>
          </form>
        )}
        <Button variant="outline" onClick={() => qc.invalidateQueries()}>Refresh status</Button>
      </div>
    </AuthCard>
  );
}
