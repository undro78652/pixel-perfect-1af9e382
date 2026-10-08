export function inr(paise: number | null | undefined) {
  const v = Number(paise ?? 0) / 100;
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", minimumFractionDigits: v % 1 ? 2 : 0, maximumFractionDigits: 2 }).format(v);
}

export function toPaise(rupees: string | number): number {
  const s = String(rupees).replace(/[,₹\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return NaN;
  const [r, p = ""] = s.split(".");
  return Number(r) * 100 + Number((p + "00").slice(0, 2));
}

export function fmtDate(d: string | null | undefined) {
  if (!d) return "—";
  const date = d.length === 10 ? new Date(d + "T00:00:00+05:30") : new Date(d);
  return date.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });
}
export function fmtDateTime(d: string | null | undefined) {
  if (!d) return "—";
  return new Date(d).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Kolkata" });
}
export function todayIST() {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
}

export function normalizeMobile(m: string): string | null {
  let d = m.replace(/\D/g, "");
  if (d.length === 10) d = "91" + d;
  else if (d.length === 11 && d.startsWith("0")) d = "91" + d.slice(1);
  if (d.length !== 12 || !d.startsWith("91")) return null;
  return "+" + d;
}

/** Private sign-in identifier derived from the mobile number by one-way hash.
 * It is never displayed, never receives email, and does not reveal the number. */
export async function loginIdFor(mobile: string): Promise<string> {
  const n = normalizeMobile(mobile);
  if (!n) throw new Error("Enter a valid 10-digit Indian mobile number");
  const data = new TextEncoder().encode("xyz-society-login:" + n);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
  return `u${hex}@login.xyz-society.invalid`;
}

export const label = (s: string | null | undefined) => (s ?? "").replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());

export function downloadCsv(name: string, rows: Record<string, unknown>[]) {
  if (!rows.length) return;
  const cols = Object.keys(rows[0]);
  const esc = (v: unknown) => {
    const s = v == null ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [cols.join(","), ...rows.map((r) => cols.map((c) => esc(r[c])).join(","))].join("\n");
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
  const a = document.createElement("a");
  a.href = url; a.download = name; a.click();
  URL.revokeObjectURL(url);
}
