import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Inventaris GDG",
  description: "Pencatatan barang dan keluar-masuk inventaris organisasi",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="id"><body>{children}</body></html>;
}
