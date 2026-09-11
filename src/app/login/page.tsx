import { redirect } from "next/navigation";
import { Boxes } from "lucide-react";
import { getSessionUser } from "@/lib/session";
import { LoginForm } from "./LoginForm";

export default async function LoginPage() {
  if (await getSessionUser()) redirect("/inventory");
  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#eef3f9] p-5">
      <div className="absolute inset-0 opacity-60" style={{ backgroundImage: "radial-gradient(circle at 15% 15%, rgba(36,99,235,.13), transparent 28%), radial-gradient(circle at 85% 85%, rgba(14,165,233,.10), transparent 30%)" }} />
      <div className="relative w-full max-w-md">
        <div className="mb-8 flex items-center justify-center gap-3">
          <div className="grid h-12 w-12 place-items-center rounded-2xl bg-navy text-white shadow-lg shadow-blue-900/15"><Boxes className="h-6 w-6" /></div>
          <div><p className="text-xl font-bold tracking-tight text-ink">Inventaris</p><p className="text-sm text-slate-500">GDG Bandung</p></div>
        </div>
        <section className="panel p-6 sm:p-8">
          <div className="mb-7">
            <p className="mb-2 text-xs font-bold uppercase tracking-[.18em] text-brand">Ruang pengurus</p>
            <h1 className="text-2xl font-bold tracking-tight text-ink">Masuk ke inventaris</h1>
            <p className="mt-2 text-sm leading-6 text-slate-500">Gunakan akun yang dibuat oleh pengurus untuk mencatat dan memantau barang.</p>
          </div>
          <LoginForm />
        </section>
        <p className="mt-5 text-center text-xs text-slate-500">Tidak punya akun? Hubungi pengurus yang mengelola inventaris.</p>
      </div>
    </main>
  );
}
