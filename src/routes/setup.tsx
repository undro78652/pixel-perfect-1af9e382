import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { AuthCard } from "@/components/auth-card";
import { Input } from "@/components/ui/input";
import { Field, SubmitButton } from "@/components/ui-kit";
import { bootstrapAdmin, setupStatus } from "@/lib/admin.functions";

export const Route = createFileRoute("/setup")({
  head: () => ({
    meta: [
      { title: "Initial setup — XYZ Society" },
      { name: "description", content: "One-time creation of the first Society admin." },
      { property: "og:title", content: "Initial setup — XYZ Society" },
      { property: "og:description", content: "One-time setup." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: Setup,
});

function Setup() {
  const run = useServerFn(bootstrapAdmin);
  const status = useServerFn(setupStatus);
  const [done, setDone] = useState<boolean | null>(null);
  const [f, setF] = useState({ setupCode: "", fullName: "", mobile: "", password: "", houseNumber: "", block: "" });
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => { status().then((r) => setDone(r.done)).catch(() => setDone(false)); }, [status]);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  if (done === null) return <AuthCard title="Initial setup">Checking…</AuthCard>;
  if (done || ok) return (
    <AuthCard title="Setup complete" subtitle="The first Society admin exists. This screen is now locked.">
      <Link to="/" className="font-medium text-primary underline">Go to sign in</Link>
    </AuthCard>
  );
  return (
    <AuthCard title="Create the first Society admin" subtitle="Enter the private setup code saved in your project settings. This works only once.">
      <form className="space-y-4" onSubmit={async (e) => {
        e.preventDefault(); setErr(null); setBusy(true);
        try {
          const r = await run({ data: { ...f, block: f.block || undefined } });
          if (r.ok) setOk(true); else setErr(r.error);
        } catch (x) { setErr((x as Error).message); } finally { setBusy(false); }
      }}>
        <Field label="Setup code" htmlFor="sc"><Input id="sc" type="password" value={f.setupCode} onChange={set("setupCode")} /></Field>
        <Field label="Full name" htmlFor="fn"><Input id="fn" value={f.fullName} onChange={set("fullName")} /></Field>
        <Field label="Mobile number" htmlFor="mb"><Input id="mb" inputMode="tel" value={f.mobile} onChange={set("mobile")} /></Field>
        <Field label="Password (8+ characters)" htmlFor="pw"><Input id="pw" type="password" value={f.password} onChange={set("password")} /></Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Your house number" htmlFor="hn"><Input id="hn" value={f.houseNumber} onChange={set("houseNumber")} /></Field>
          <Field label="Row / block (optional)" htmlFor="bl"><Input id="bl" value={f.block} onChange={set("block")} /></Field>
        </div>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <SubmitButton type="submit" className="w-full" pending={busy}>Create Society admin</SubmitButton>
      </form>
    </AuthCard>
  );
}
