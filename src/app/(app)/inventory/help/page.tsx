import Link from "next/link";
import {
  AlertTriangle,
  ArrowRight,
  BookOpen,
  Boxes,
  CheckCircle2,
  ChevronDown,
  ClipboardCheck,
  ClipboardList,
  HelpCircle,
  PackagePlus,
  RotateCcw,
  ShieldCheck,
  Users,
} from "lucide-react";

const transactionTypes = [
  ["Barang Masuk", "Menambah stok karena pembelian, donasi, atau barang baru diterima."],
  ["Barang Keluar", "Mengurangi stok. Aktifkan opsi pinjaman jika barang akan dikembalikan."],
  ["Barang Kembali", "Mengembalikan stok dari pinjaman aktif yang dipilih pada Terkait pinjaman."],
  ["Barang Rusak", "Mencatat barang rusak, baik dari penyimpanan maupun dari pinjaman aktif."],
  ["Barang Hilang", "Mencatat kehilangan barang, baik dari penyimpanan maupun dari pinjaman aktif."],
  ["Koreksi Stok", "Menyamakan stok sistem dengan hasil hitung fisik. Hanya tersedia untuk admin."],
] as const;

const faqs = [
  ["Kenapa dropdown Terkait pinjaman kosong?", "Dropdown hanya menampilkan transaksi Barang Keluar yang ditandai sebagai pinjaman, belum dibatalkan, dan masih memiliki jumlah yang belum kembali. Buat pinjaman terlebih dahulu atau periksa filter Belum kembali di Riwayat Keluar-Masuk."],
  ["Dari mana pilihan nama peminjam berasal?", "Pilihan peminjam berasal dari akun aktif pada menu Pengguna. Untuk orang yang tidak memiliki akun, pilih Peminjam eksternal lalu isi nama lengkap atau organisasinya."],
  ["Kenapa opsi Barang dipinjam tidak selalu aktif?", "Opsi ini otomatis aktif untuk kategori Barang Tetap. Untuk kategori lain, aktifkan secara manual hanya jika barang memang harus kembali."],
  ["Kenapa stok tidak bisa dikurangi?", "Jumlah keluar tidak boleh melebihi stok yang tersedia. Pastikan barang dan jumlah sudah benar, atau lakukan stock opname/koreksi stok bila stok fisik berbeda."],
  ["Bisakah transaksi dihapus?", "Transaksi tidak dihapus permanen agar jejak audit tetap utuh. Admin dapat memakai aksi Batalkan dan wajib mengisi alasannya."],
  ["Kenapa barang tidak bisa diarsipkan?", "Barang yang masih memiliki pinjaman aktif belum boleh diarsipkan. Selesaikan pengembalian, kerusakan, atau kehilangan terkait terlebih dahulu."],
  ["Apa bedanya pencatat dan peminjam?", "Pencatat adalah akun yang sedang login dan menyimpan transaksi. Peminjam adalah orang atau organisasi yang membawa barang."],
  ["Siapa yang dapat mengelola barang dan pengguna?", "Admin dapat mengelola master barang, pengguna, koreksi stok, perubahan, dan pembatalan transaksi. Member dapat mencatat barang masuk, keluar, dan kembali."],
  ["Kapan memakai stock opname?", "Gunakan stock opname untuk menghitung seluruh stok fisik dalam satu sesi. Selama sesi masih draft, pergerakan stok dan perubahan master barang dibekukan agar hasil konsisten."],
  ["Bagaimana mengunduh laporan?", "Buka menu Laporan untuk membuat PDF, atau gunakan Export CSV pada halaman inventaris dan Riwayat Keluar-Masuk."],
] as const;

function Step({ number, title, children }: { number: number; title: string; children: React.ReactNode }) {
  return <li className="flex gap-3"><span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-brand text-xs font-bold text-white">{number}</span><div><p className="font-semibold text-ink">{title}</p><p className="mt-1 text-sm leading-6 text-slate-600">{children}</p></div></li>;
}

export default function HelpPage() {
  return <div className="mx-auto max-w-[1200px] p-4 sm:p-6 xl:p-8">
    <header className="rounded-3xl bg-navy px-5 py-7 text-white sm:px-8 sm:py-9">
      <div className="flex items-start gap-4"><div className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-white/10"><BookOpen className="h-6 w-6" /></div><div><p className="text-sm font-semibold text-blue-200">Pusat bantuan</p><h1 className="mt-1 text-2xl font-bold sm:text-3xl">Panduan &amp; FAQ Inventaris</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-blue-100">Panduan singkat untuk mengelola barang, mencatat pergerakan stok, memproses pinjaman, dan menyelesaikan masalah yang paling sering ditemui.</p></div></div>
    </header>

    <section className="mt-6 grid gap-4 md:grid-cols-3">
      <Link href="/inventory" className="panel group p-5 transition hover:border-blue-200 hover:shadow-md"><Boxes className="h-6 w-6 text-brand" /><h2 className="mt-4 font-bold">Lihat inventaris</h2><p className="mt-1 text-sm leading-6 text-slate-500">Cari barang, periksa stok, lalu klik Catat untuk membuat pergerakan.</p><span className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-brand">Buka inventaris <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" /></span></Link>
      <Link href="/inventory/transactions" className="panel group p-5 transition hover:border-blue-200 hover:shadow-md"><ClipboardList className="h-6 w-6 text-brand" /><h2 className="mt-4 font-bold">Catat transaksi</h2><p className="mt-1 text-sm leading-6 text-slate-500">Buat catatan masuk, keluar, pinjam, kembali, rusak, atau hilang.</p><span className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-brand">Buka riwayat <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" /></span></Link>
      <Link href="/inventory/report" className="panel group p-5 transition hover:border-blue-200 hover:shadow-md"><ClipboardCheck className="h-6 w-6 text-brand" /><h2 className="mt-4 font-bold">Buat laporan</h2><p className="mt-1 text-sm leading-6 text-slate-500">Pilih periode, tinjau ringkasan, lalu unduh laporan PDF.</p><span className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-brand">Buka laporan <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" /></span></Link>
    </section>

    <section className="mt-6 grid gap-6 lg:grid-cols-2">
      <article className="panel p-5 sm:p-6"><div className="flex items-center gap-3"><PackagePlus className="h-5 w-5 text-brand" /><div><p className="text-xs font-bold uppercase tracking-wide text-slate-400">Untuk admin</p><h2 className="font-bold">Mulai menggunakan aplikasi</h2></div></div><ol className="mt-6 space-y-5"><Step number={1} title="Buat akun pengguna">Buka menu Pengguna, lalu isi nama, username, password, dan role.</Step><Step number={2} title="Tambahkan master barang">Buka Inventaris dan pilih Tambah Barang. Isi kode unik, kategori, satuan, dan stok awal.</Step><Step number={3} title="Catat pergerakan">Klik Catat pada barang atau buka Riwayat Keluar-Masuk untuk membuat transaksi.</Step><Step number={4} title="Periksa dan laporkan">Gunakan Stock opname untuk verifikasi fisik dan menu Laporan untuk rekap periode.</Step></ol></article>

      <article className="panel overflow-hidden"><div className="border-b border-blue-100 bg-blue-50/70 p-5 sm:p-6"><div className="flex items-center gap-3"><RotateCcw className="h-5 w-5 text-blue-700" /><div><p className="text-xs font-bold uppercase tracking-wide text-blue-500">Alur utama</p><h2 className="font-bold text-blue-950">Pinjam dan kembalikan barang</h2></div></div></div><div className="p-5 sm:p-6"><ol className="space-y-5"><Step number={1} title="Buat Barang Keluar">Pilih barang dan jenis catatan Barang Keluar.</Step><Step number={2} title="Tandai sebagai pinjaman">Aktifkan “Barang dipinjam dan akan kembali”, kemudian isi rencana kembali dan peminjam.</Step><Step number={3} title="Simpan pinjaman">Setelah tersimpan, catatan akan muncul pada filter Belum kembali.</Step><Step number={4} title="Catat pengembalian">Buat transaksi Barang Kembali dan pilih catatan pada dropdown Terkait pinjaman.</Step><Step number={5} title="Isi jumlah yang kembali">Pengembalian boleh sebagian. Pinjaman tetap muncul sampai seluruh jumlah selesai.</Step></ol><div className="mt-6 flex gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-900"><AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" /><p>Jika barang pinjaman rusak atau hilang, pilih jenis transaksi yang sesuai lalu hubungkan ke pinjaman yang sama.</p></div></div></article>
    </section>

    <section className="panel mt-6 overflow-hidden"><div className="border-b border-slate-100 p-5 sm:p-6"><h2 className="flex items-center gap-2 font-bold"><ClipboardList className="h-5 w-5 text-brand" />Arti jenis transaksi</h2></div><div className="grid md:grid-cols-2">{transactionTypes.map(([title, description], index) => <div key={title} className={`flex gap-3 p-5 ${index < transactionTypes.length - 2 ? "border-b border-slate-100" : ""} ${index % 2 === 0 ? "md:border-r" : ""}`}><CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-500" /><div><h3 className="font-semibold">{title}</h3><p className="mt-1 text-sm leading-6 text-slate-500">{description}</p></div></div>)}</div></section>

    <section className="mt-6 grid gap-4 sm:grid-cols-2"><div className="panel p-5"><ShieldCheck className="h-6 w-6 text-brand" /><h2 className="mt-3 font-bold">Admin</h2><p className="mt-1 text-sm leading-6 text-slate-500">Mengelola barang dan pengguna, melakukan koreksi/stock opname, mengubah transaksi lama, serta membatalkan transaksi.</p></div><div className="panel p-5"><Users className="h-6 w-6 text-brand" /><h2 className="mt-3 font-bold">Member</h2><p className="mt-1 text-sm leading-6 text-slate-500">Melihat inventaris dan laporan serta mencatat barang masuk, keluar, pinjam, dan kembali.</p></div></section>

    <section className="mt-6"><div className="mb-4 flex items-center gap-3"><HelpCircle className="h-6 w-6 text-brand" /><div><p className="text-sm font-semibold text-brand">Pertanyaan umum</p><h2 className="text-xl font-bold">FAQ</h2></div></div><div className="space-y-3">{faqs.map(([question, answer]) => <details key={question} className="panel group"><summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-5 font-semibold marker:content-none"><span>{question}</span><ChevronDown className="h-5 w-5 shrink-0 text-slate-400 transition group-open:rotate-180" /></summary><div className="border-t border-slate-100 px-5 py-4 text-sm leading-6 text-slate-600">{answer}</div></details>)}</div></section>
  </div>;
}
