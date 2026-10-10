import { useEffect, useState, type ReactNode } from "react";
import { Link } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { signedUrl, uploadEvidence } from "@/lib/db";
import { label as lbl, inr } from "@/lib/format";
import { toast } from "sonner";
import { AlertTriangle, FileText, Inbox, Loader2, Paperclip } from "lucide-react";

export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-2xl font-bold text-foreground sm:text-3xl">{title}</h1>
        {description && <p className="mt-1 max-w-2xl text-muted-foreground">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  );
}

export function Loading({ rows = 3 }: { rows?: number }) {
  return <div className="space-y-3" aria-busy="true" aria-label="Loading">{Array.from({ length: rows }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}</div>;
}
export function ErrorBox({ error }: { error: unknown }) {
  return (
    <div role="alert" className="flex items-start gap-2 rounded-md border border-destructive/40 bg-destructive/5 p-4 text-destructive">
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
      <span>{error instanceof Error ? error.message : "Something went wrong"}</span>
    </div>
  );
}
export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-lg border border-dashed bg-card p-8 text-center">
      <Inbox className="mb-2 h-6 w-6 text-muted-foreground" />
      <p className="font-medium">{title}</p>
      {children && <div className="mt-1 text-sm text-muted-foreground">{children}</div>}
    </div>
  );
}

/** Renders loading / error / empty states around a query. */
export function QueryState<T>({ q, empty, children }: { q: { isLoading: boolean; error: unknown; data?: T[] }; empty?: string; children: (d: T[]) => ReactNode }) {
  if (q.isLoading) return <Loading />;
  if (q.error) return <ErrorBox error={q.error} />;
  if (!q.data?.length) return <Empty title={empty ?? "Nothing here yet"} />;
  return <>{children(q.data)}</>;
}

const TONE: Record<string, string> = {
  posted: "bg-success text-success-foreground", approved: "bg-success text-success-foreground", active: "bg-success text-success-foreground",
  completed: "bg-success text-success-foreground", closed: "bg-secondary text-secondary-foreground", settled: "bg-success text-success-foreground",
  paid: "bg-success text-success-foreground", confirmed: "bg-success text-success-foreground",
  disputed: "bg-destructive text-destructive-foreground", rejected: "bg-destructive text-destructive-foreground", suspended: "bg-destructive text-destructive-foreground",
  mismatch: "bg-destructive text-destructive-foreground", urgent: "bg-destructive text-destructive-foreground",
  high: "bg-warning text-warning-foreground", cancelled: "bg-muted text-muted-foreground", reversed: "bg-muted text-muted-foreground", ended: "bg-muted text-muted-foreground",
  awaiting_admin: "bg-info text-info-foreground", in_progress: "bg-info text-info-foreground",
};
export function StatusBadge({ s }: { s: string | null | undefined }) {
  const key = s ?? "";
  const names: Record<string, string> = {
    awaiting_admin: "Awaiting admin approval", awaiting_sender: "Awaiting sender", awaiting_receiver: "Awaiting receiver",
    awaiting_confirmations: "Awaiting confirmations", not_yet: "Not yet", na: "Not required", pending_society: "Pending society approval",
    pending_household: "Pending household approval", paid_personally: "Already paid personally",
  };
  return <Badge className={TONE[key] ?? "bg-warning/25 text-warning-foreground"}>{names[key] ?? lbl(key)}</Badge>;
}

export function Money({ p, className }: { p: number | null | undefined; className?: string }) {
  return <span className={"tabular " + (className ?? "")}>{inr(p)}</span>;
}

export function Stat({ label, value, to, hint }: { label: string; value: ReactNode; to?: string; hint?: string }) {
  const body = (
    <Card className="h-full transition-colors hover:border-primary/50">
      <CardContent className="p-4">
        <p className="text-sm text-muted-foreground">{label}</p>
        <p className="mt-1 text-2xl font-bold tabular">{value}</p>
        {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
  return to ? <Link to={to as never} className="block">{body}</Link> : body;
}

export function Field({ label, htmlFor, children, hint }: { label: string; htmlFor?: string; children: ReactNode; hint?: string }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

export function EvidenceUpload({ value, onChange, label = "Evidence (screenshots, receipts, photos)" }: { value: string[]; onChange: (v: string[]) => void; label?: string }) {
  const [busy, setBusy] = useState(false);
  return (
    <Field label={label} hint="Images or PDF, up to 10 MB each. A screenshot is evidence supplied by a person, not proof of bank receipt.">
      <input type="file" multiple accept="image/*,application/pdf" disabled={busy} className="block w-full text-sm file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-2 file:text-secondary-foreground"
        onChange={async (e) => {
          if (!e.target.files?.length) return;
          setBusy(true);
          try { onChange([...value, ...(await uploadEvidence(e.target.files))]); toast.success("File attached"); }
          catch (err) { toast.error((err as Error).message); }
          finally { setBusy(false); e.target.value = ""; }
        }} />
      {busy && <p className="flex items-center gap-1 text-sm text-muted-foreground"><Loader2 className="h-3 w-3 animate-spin" /> Uploading…</p>}
      {value.length > 0 && <p className="text-sm text-muted-foreground"><Paperclip className="mr-1 inline h-3 w-3" />{value.length} file(s) attached</p>}
    </Field>
  );
}

export function EvidenceList({ paths }: { paths: string[] | null | undefined }) {
  const [urls, setUrls] = useState<Record<string, string>>({});
  useEffect(() => {
    (paths ?? []).forEach((p) => signedUrl(p).then((u) => setUrls((x) => ({ ...x, [p]: u }))).catch(() => {}));
  }, [paths]);
  if (!paths?.length) return <p className="text-sm text-muted-foreground">No evidence attached.</p>;
  return (
    <div className="flex flex-wrap gap-3">
      {paths.map((p) => {
        const u = urls[p]; const isImg = /\.(png|jpe?g|gif|webp)$/i.test(p);
        return (
          <a key={p} href={u} target="_blank" rel="noreferrer" className="block rounded-md border bg-muted p-1 text-xs">
            {u && isImg ? <img src={u} alt="Evidence" className="h-24 w-24 rounded object-cover" /> : <span className="flex h-24 w-24 flex-col items-center justify-center gap-1"><FileText className="h-5 w-5" />Open file</span>}
          </a>
        );
      })}
    </div>
  );
}

export function SubmitButton({ pending, children, ...rest }: React.ComponentProps<typeof Button> & { pending?: boolean }) {
  return <Button disabled={pending || rest.disabled} {...rest}>{pending && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}{children}</Button>;
}

export function Section({ title, children, actions }: { title: string; children: ReactNode; actions?: ReactNode }) {
  return (
    <section className="mb-8">
      <div className="mb-3 flex items-center justify-between gap-2"><h2 className="text-lg font-semibold">{title}</h2>{actions}</div>
      {children}
    </section>
  );
}

export function useNames(ids: (string | null | undefined)[], profiles?: { id: string; full_name: string }[]) {
  const m = new Map((profiles ?? []).map((p) => [p.id, p.full_name]));
  return (id?: string | null) => (id ? m.get(id) ?? "Member" : "—");
}
