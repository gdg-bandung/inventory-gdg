"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Eye, EyeOff, Loader2, LogIn } from "lucide-react";
import { ACTIVITY_STORAGE_KEY, JWT_STORAGE_KEY } from "@/lib/clientAuth";

export function LoginForm() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("reason") === "inactive") {
      setError("Sesi berakhir karena tidak ada aktivitas selama 30 menit. Silakan masuk kembali.");
    }
  }, []);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError("");
    if (!username.trim() || !password) { setError("Username dan password wajib diisi"); return; }
    setLoading(true);
    try {
      const response = await fetch("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username, password }) });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Tidak dapat masuk");
      localStorage.setItem(JWT_STORAGE_KEY, payload.jwt);
      localStorage.setItem(ACTIVITY_STORAGE_KEY, String(Date.now()));
      router.replace("/inventory");
      router.refresh();
    } catch (err) { setError(err instanceof Error ? err.message : "Tidak dapat masuk"); }
    finally { setLoading(false); }
  }

  return (
    <form className="space-y-5" onSubmit={submit}>
      <div><label className="field-label" htmlFor="username">Username</label><input className="field" id="username" autoComplete="username" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="Masukkan username" autoFocus /></div>
      <div>
        <label className="field-label" htmlFor="password">Password</label>
        <div className="relative"><input className="field pr-12" id="password" type={showPassword ? "text" : "password"} autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Masukkan password" /><button type="button" onClick={() => setShowPassword((v) => !v)} className="absolute inset-y-0 right-0 grid w-11 place-items-center text-slate-400 hover:text-slate-700" aria-label={showPassword ? "Sembunyikan password" : "Lihat password"}>{showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}</button></div>
      </div>
      {error && <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3 py-2.5 text-sm font-medium text-rose-700">{error}</p>}
      <button className="btn-primary w-full" disabled={loading}>{loading ? <><Loader2 className="h-4 w-4 animate-spin" />Memeriksa akun...</> : <><LogIn className="h-4 w-4" />Masuk</>}</button>
    </form>
  );
}
