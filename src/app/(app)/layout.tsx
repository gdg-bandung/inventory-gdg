import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/session";
import { InventoryProvider } from "@/components/inventory/InventoryContext";
import { AppShell } from "@/components/inventory/AppShell";

export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  return <InventoryProvider user={user}><AppShell>{children}</AppShell></InventoryProvider>;
}
