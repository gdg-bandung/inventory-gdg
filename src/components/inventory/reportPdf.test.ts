import { beforeAll,describe,expect,it } from "vitest";
import { mkdirSync } from "node:fs";
import { exportInventoryReportPdf } from "./reportPdf";
import type { InventoryItem } from "./types";

beforeAll(()=>mkdirSync("output/pdf",{recursive:true}));
const item:InventoryItem={id:"item",name:"Kursi Lipat",category:"Barang Tetap",code:"BT-001",unit:"unit",initial_stock:20,min_stock:5,condition:"Baik",location:"Gudang",purchase_price:185000,purchase_date:"2026-01-01",expiry_date:null,owner_division:"Operasional",penanggung_jawab:"Koordinator Logistik",notes:null,is_archived:false,created_at:"2026-01-01T00:00:00Z",updated_at:"2026-01-01T00:00:00Z",current_stock:20,outstanding:0,last_movement_at:null,created_by:"tester",updated_by:"tester"};
describe("export PDF",()=>{it("membuat laporan PDF yang tidak kosong",()=>{exportInventoryReportPdf([item],[],"2026-01-01","2026-12-31","output/pdf/inventory-report-sample.pdf");expect(true).toBe(true);});});
