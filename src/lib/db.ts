import { supabase } from "@/integrations/supabase/client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

// Loosely typed handle: all writes go through permission-checked database functions.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const db = supabase as any;

export async function rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export async function rows<T = any>(q: PromiseLike<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return data ?? [];
}

export function useRows<T = any>(key: unknown[], fn: () => Promise<T[]>, enabled = true) {
  return useQuery({ queryKey: key, queryFn: fn, enabled });
}

/** Mutation that toasts success/failure and refreshes all data afterwards. */
export function useAction<A>(fn: (a: A) => Promise<unknown>, success?: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      if (success) toast.success(success);
      qc.invalidateQueries();
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export async function uploadEvidence(files: FileList | File[]): Promise<string[]> {
  const { data: u } = await supabase.auth.getUser();
  if (!u.user) throw new Error("Not signed in");
  const out: string[] = [];
  for (const f of Array.from(files)) {
    if (f.size > 10 * 1024 * 1024) throw new Error(`${f.name} is larger than 10 MB`);
    const path = `${u.user.id}/${crypto.randomUUID()}-${f.name.replace(/[^\w.-]/g, "_")}`;
    const { error } = await supabase.storage.from("evidence").upload(path, f);
    if (error) throw new Error(error.message);
    out.push(path);
  }
  return out;
}

export async function signedUrl(path: string) {
  const { data, error } = await supabase.storage.from("evidence").createSignedUrl(path, 600);
  if (error) throw new Error(error.message);
  return data.signedUrl;
}
