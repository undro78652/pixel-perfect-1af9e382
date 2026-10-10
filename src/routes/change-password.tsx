import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { AuthCard } from "@/components/auth-card";
import { Input } from "@/components/ui/input";
import { Field, SubmitButton } from "@/components/ui-kit";
import { rpc } from "@/lib/db";
import { toast } from "sonner";

export const Route = createFileRoute("/change-password")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Change password — XYZ Society" },
      { name: "description", content: "Choose a new password for your XYZ Society account." },
      { property: "og:title", content: "Change password — XYZ Society" },
      { property: "og:description", content: "Set a new password." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ChangePassword,
});

function ChangePassword() {
  const nav = useNavigate();
  const qc = useQueryClient();
  const [cur, setCur] = useState(""); const [p1, setP1] = useState(""); const [p2, setP2] = useState("");
  const [err, setErr] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  return (
    <AuthCard title="Choose a new password" subtitle="You signed in with a temporary password. Set your own before continuing.">
      <form className="space-y-4" onSubmit={async (e) => {
        e.preventDefault(); setErr(null);
        if (p1.length < 8) return setErr("Password must be at least 8 characters");
        if (p1 !== p2) return setErr("Passwords do not match");
        if (p1 === cur) return setErr("Choose a password different from the temporary one");
        setBusy(true);
        try {
          const { error } = await supabase.auth.updateUser({ password: p1, current_password: cur } as any);
          if (error) { setErr(error.message); return; }
          await rpc("clear_must_change_password");
          toast.success("Password changed");
          await qc.invalidateQueries();
          nav({ to: "/overview" });
        } finally { setBusy(false); }
      }}>
        <Field label="Temporary password" htmlFor="c"><Input id="c" type="password" value={cur} onChange={(e) => setCur(e.target.value)} /></Field>
        <Field label="New password" htmlFor="n"><Input id="n" type="password" autoComplete="new-password" value={p1} onChange={(e) => setP1(e.target.value)} /></Field>
        <Field label="Confirm new password" htmlFor="n2"><Input id="n2" type="password" autoComplete="new-password" value={p2} onChange={(e) => setP2(e.target.value)} /></Field>
        {err && <p role="alert" className="text-sm text-destructive">{err}</p>}
        <SubmitButton type="submit" className="w-full" pending={busy}>Save new password</SubmitButton>
      </form>
    </AuthCard>
  );
}
