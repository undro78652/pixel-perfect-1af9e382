import type { ReactNode } from "react";
import { Building2 } from "lucide-react";

export function AuthCard({ title, subtitle, children, footer }: { title: string; subtitle?: string; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background px-4 py-10">
      <div className="mb-6 flex items-center gap-2 text-primary">
        <Building2 className="h-7 w-7" />
        <span className="font-display text-xl font-bold">XYZ Society</span>
      </div>
      <div className="w-full max-w-md rounded-xl border bg-card p-6 shadow-sm sm:p-8">
        <h1 className="text-2xl font-bold">{title}</h1>
        {subtitle && <p className="mt-1 text-muted-foreground">{subtitle}</p>}
        <div className="mt-6">{children}</div>
      </div>
      {footer && <div className="mt-4 text-sm text-muted-foreground">{footer}</div>}
    </div>
  );
}
