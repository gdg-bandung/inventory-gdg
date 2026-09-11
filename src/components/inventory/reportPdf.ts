import { jsPDF } from "jspdf";
import type { InventoryItem, InventoryTransaction } from "./types";
import { formatDateID, formatRupiah } from "./helpers";
import { isExpiring, isLowStock, outstandingLoans } from "./inventoryUtils";

export function exportInventoryReportPdf(items: InventoryItem[], transactions: InventoryTransaction[], start: string, end: string, filename = `laporan-inventaris-${start}-${end}.pdf`) {
  const active = items.filter((row) => !row.is_archived);
  const effectiveTransactions = transactions.filter((row) => !row.reversed_at);
  const period = effectiveTransactions.filter((row) => (!start || row.transaction_date >= start) && (!end || row.transaction_date <= end));
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  const margin = 16;
  const pageWidth = doc.internal.pageSize.getWidth();
  let y = 18;

  const header = (first = true) => {
    doc.setFillColor(18, 50, 92); doc.rect(0, 0, pageWidth, first ? 34 : 12, "F");
    doc.setTextColor(255, 255, 255); doc.setFont("helvetica", "bold"); doc.setFontSize(first ? 19 : 9);
    doc.text(first ? "Laporan Inventaris GDG Bandung" : "Inventaris GDG Bandung", margin, first ? 17 : 8);
    if (first) { doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.text(`Periode ${formatDateID(start)} - ${formatDateID(end)}`, margin, 25); y = 44; }
    else doc.setTextColor(18, 33, 58);
  };
  const ensure = (height: number) => { if (y + height > 278) { doc.addPage(); y = 18; header(false); } };
  const section = (title: string) => { ensure(15); doc.setTextColor(18, 33, 58); doc.setFont("helvetica", "bold"); doc.setFontSize(12); doc.text(title, margin, y); y += 7; };
  const line = (left: string, right: string) => {
    ensure(8); doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(71, 85, 105); doc.text(left, margin, y);
    doc.setFont("helvetica", "bold"); doc.setTextColor(18, 33, 58); doc.text(right, pageWidth - margin, y, { align: "right" });
    doc.setDrawColor(226, 232, 240); doc.line(margin, y + 2, pageWidth - margin, y + 2); y += 8;
  };

  header();
  const stockValue = active.reduce((sum, row) => sum + Number(row.current_stock) * Number(row.purchase_price ?? 0), 0);
  const loans = active.flatMap((item) => outstandingLoans(item.id, effectiveTransactions).map((loan) => ({ ...loan, item })));
  section("Ringkasan");
  line("Barang aktif", String(active.length)); line("Nilai stok tersedia", formatRupiah(stockValue));
  line("Catatan aktif pada periode", String(period.length)); line("Pinjaman terbuka", String(loans.length));
  y += 4; section("Nilai stok per kategori");
  for (const category of ["Barang Habis Pakai", "Barang Tetap", "Konsumsi", "Lainnya"]) {
    const rows = active.filter((row) => row.category === category);
    line(`${category} (${rows.length} barang)`, formatRupiah(rows.reduce((sum, row) => sum + Number(row.current_stock) * Number(row.purchase_price ?? 0), 0)));
  }
  y += 4; section("Pergerakan per satuan");
  const unitMap = new Map<string, { incoming: number; outgoing: number }>();
  for (const row of period) {
    const value = unitMap.get(row.item_unit) ?? { incoming: 0, outgoing: 0 };
    if (["Masuk", "Kembali"].includes(row.type) || (row.type === "Penyesuaian" && row.quantity > 0)) value.incoming += Math.abs(Number(row.quantity));
    if (["Keluar", "Rusak", "Hilang"].includes(row.type) || (row.type === "Penyesuaian" && row.quantity < 0)) value.outgoing += Math.abs(Number(row.quantity));
    unitMap.set(row.item_unit, value);
  }
  if (!unitMap.size) line("Belum ada pergerakan", "-");
  else for (const [unit, value] of unitMap) line(unit, `Masuk ${value.incoming.toLocaleString("id-ID")} | Keluar ${value.outgoing.toLocaleString("id-ID")}`);
  y += 4;
  const follow = [
    { title: "Perlu restock", rows: active.filter(isLowStock).map((row) => `${row.code} - ${row.name}: ${row.current_stock} ${row.unit}`) },
    { title: "Mendekati kadaluarsa", rows: active.filter((row) => isExpiring(row, 30)).map((row) => `${row.code} - ${row.name}: ${formatDateID(row.expiry_date)}`) },
    { title: "Pinjaman belum kembali", rows: loans.map((row) => `${row.item.code} - ${row.item.name}: ${row.remaining} ${row.item.unit} (${row.handled_by || "peminjam tidak diketahui"})`) },
  ];
  for (const group of follow) {
    section(`${group.title} (${group.rows.length})`);
    if (!group.rows.length) line("Tidak ada tindak lanjut", "Aman");
    else for (const entry of group.rows.slice(0, 40)) { ensure(7); doc.setFont("helvetica", "normal"); doc.setFontSize(8.5); doc.setTextColor(51, 65, 85); const lines = doc.splitTextToSize(entry, pageWidth - margin * 2); doc.text(lines, margin, y); y += lines.length * 4.5; }
  }
  const pages = doc.getNumberOfPages();
  for (let page = 1; page <= pages; page++) { doc.setPage(page); doc.setFontSize(8); doc.setTextColor(148, 163, 184); doc.text(`Dibuat ${new Date().toLocaleString("id-ID")} | Halaman ${page}/${pages}`, pageWidth - margin, 291, { align: "right" }); }
  doc.save(filename);
}
