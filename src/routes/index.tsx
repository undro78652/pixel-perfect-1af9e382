import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AuthCard } from "@/components/auth-card";
import { Input } from "@/components/ui/input";
import { Field, SubmitButton } from "@/components/ui-kit";
import { loginIdFor, normalizeMobile } from "@/lib/format";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Sign in — XYZ Society" },
      { name: "description", content: "Sign in to XYZ Society with your mobile number and password." },
      { property: "og:title", content: "Sign in — XYZ Society" },
      { property: "og:description", content: "Private resident portal for XYZ Society." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Login,
});

function Login() {
  const nav = useNavigate();
  const [mobile, setMobile] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => { if (data.user) nav({ to: "/overview" }); });
  }, [nav]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    if (!normalizeMobile(mobile)) return setErr("Enter a valid 10-digit Indian mobile number");
    if (!password) return setErr("Enter your password");
    setBusy(true);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email: await loginIdFor(mobile), password });
      if (error) setErr(error.message.includes("Invalid") ? "Mobile number or password is incorrect" : error.message);
      else nav({ to: "/overview" });
    } finally { setBusy(false); }
  }

  return (
    <AuthCard title="Sign in" subtitle="Use your mobile number and password."
      footer={<span>New here? <Link to="/register" className="font-medium text-primary underline">Register or join a house</Link></span>}>
      <form onSubmit={submit} className="space-y-4" noValidate>
        <Field label="Mobile number" htmlFor="m"><Input id="m" inputMode="tel" autoComplete="tel" placeholder="98765 43210" value={mobile} onChange={(e) => setMobile(e.target.value)} /></Field>
        <Field label="Password" htmlFor="p"><Input id="p" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} /></Field>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <SubmitButton type="submit" className="w-full" pending={busy}>Sign in</SubmitButton>
        <p className="text-xs text-muted-foreground">Forgot your password? Contact the Society admin. After checking your identity in person they can issue a temporary password.</p>
      </form>
    </AuthCard>
  );
}
