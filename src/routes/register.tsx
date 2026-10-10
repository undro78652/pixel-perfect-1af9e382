import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { AuthCard } from "@/components/auth-card";
import { Input } from "@/components/ui/input";
import { Field, SubmitButton } from "@/components/ui-kit";
import { loginIdFor, normalizeMobile } from "@/lib/format";
import { rpc } from "@/lib/db";

export const Route = createFileRoute("/register")({
  validateSearch: (s) => z.object({ invite: z.string().optional() }).parse(s),
  head: () => ({
    meta: [
      { title: "Register — XYZ Society" },
      { name: "description", content: "Register and request to join a house in XYZ Society." },
      { property: "og:title", content: "Register — XYZ Society" },
      { property: "og:description", content: "Request membership in XYZ Society." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Register,
});

const sel = "flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm";

function Register() {
  const { invite } = Route.useSearch();
  const nav = useNavigate();
  const [inviteInfo, setInviteInfo] = useState<{ house_number: string; valid: boolean } | null>(null);
  const [path, setPath] = useState<"existing" | "new">("existing");
  const [f, setF] = useState({ name: "", mobile: "", password: "", confirm: "", house: "", block: "", address: "", occupancy: "owner_occupied", relation: "family" });
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setF({ ...f, [k]: e.target.value });

  useEffect(() => {
    if (invite) rpc<{ house_number: string; valid: boolean } | null>("invitation_info", { _token: invite }).then(setInviteInfo).catch(() => setInviteInfo(null));
  }, [invite]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    if (!f.name.trim()) return setErr("Enter your name");
    if (!normalizeMobile(f.mobile)) return setErr("Enter a valid 10-digit Indian mobile number");
    if (f.password.length < 8) return setErr("Password must be at least 8 characters");
    if (f.password !== f.confirm) return setErr("Passwords do not match");
    if (!invite && !f.house.trim()) return setErr("Enter the house number");
    if (invite && !inviteInfo?.valid) return setErr("This invitation link is invalid, expired or revoked");
    setBusy(true);
    try {
      const { data, error } = await supabase.auth.signUp({
        email: await loginIdFor(f.mobile), password: f.password,
        options: { data: { full_name: f.name.trim(), mobile: f.mobile } },
      });
      if (error) {
        setErr(error.message.toLowerCase().includes("registered") ? "An account with this mobile number already exists. Sign in instead." : error.message);
        return;
      }
      if (!data.session) { setErr("Account created. Please sign in to continue."); return; }
      try {
        if (invite) await rpc("accept_invitation", { _token: invite, _relation: f.relation });
        else if (path === "existing") await rpc("request_house_membership", { _house_number: f.house, _relation: f.relation });
        else await rpc("request_new_house", { _house_number: f.house, _block: f.block, _address: f.address, _occupancy: f.occupancy, _relation: f.relation === "family" ? "owner" : f.relation });
      } catch (e2) {
        // Account exists; the request can be retried from the status page.
        sessionStorage.setItem("join_error", (e2 as Error).message);
      }
      nav({ to: "/status" });
    } finally { setBusy(false); }
  }

  return (
    <AuthCard title={invite ? "Accept family invitation" : "Register"}
      subtitle={invite ? (inviteInfo ? (inviteInfo.valid ? `You were invited to house ${inviteInfo.house_number}. Your house admin must approve you.` : "This invitation is expired or revoked.") : "Checking invitation…") : "Create your account, then your house admin or the Society admin approves you."}
      footer={<span>Already registered? <Link to="/" className="font-medium text-primary underline">Sign in</Link></span>}>
      <form onSubmit={submit} className="space-y-4" noValidate>
        <Field label="Full name" htmlFor="n"><Input id="n" value={f.name} onChange={set("name")} maxLength={100} /></Field>
        <Field label="Mobile number" htmlFor="m" hint="Used to sign in. No OTP is sent."><Input id="m" inputMode="tel" value={f.mobile} onChange={set("mobile")} /></Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Password" htmlFor="p"><Input id="p" type="password" autoComplete="new-password" value={f.password} onChange={set("password")} /></Field>
          <Field label="Confirm password" htmlFor="c"><Input id="c" type="password" autoComplete="new-password" value={f.confirm} onChange={set("confirm")} /></Field>
        </div>
        {!invite && (
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">How are you joining?</legend>
            <label className="flex items-center gap-2 text-sm"><input type="radio" checked={path === "existing"} onChange={() => setPath("existing")} /> My house is already registered</label>
            <label className="flex items-center gap-2 text-sm"><input type="radio" checked={path === "new"} onChange={() => setPath("new")} /> Register a new house (Society admin reviews)</label>
          </fieldset>
        )}
        {!invite && <Field label="House number" htmlFor="h"><Input id="h" value={f.house} onChange={set("house")} maxLength={30} /></Field>}
        {!invite && path === "new" && (
          <>
            <Field label="Row or block (optional)" htmlFor="b"><Input id="b" value={f.block} onChange={set("block")} maxLength={30} /></Field>
            <Field label="Address description (optional)" htmlFor="a"><Input id="a" value={f.address} onChange={set("address")} maxLength={200} /></Field>
            <Field label="Occupancy" htmlFor="o">
              <select id="o" className={sel} value={f.occupancy} onChange={set("occupancy")}>
                <option value="owner_occupied">Owner occupied</option><option value="tenant_occupied">Tenant occupied</option>
              </select>
            </Field>
          </>
        )}
        <Field label="Your relationship to the house" htmlFor="r">
          <select id="r" className={sel} value={f.relation} onChange={set("relation")}>
            <option value="owner">Owner</option><option value="tenant">Tenant</option><option value="family">Family member</option>
          </select>
        </Field>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <SubmitButton type="submit" className="w-full" pending={busy}>Create account and send request</SubmitButton>
      </form>
    </AuthCard>
  );
}
