import { describe,expect,it } from "vitest";
import { csvToItems,parseCsv } from "./csv";

describe("CSV inventory",()=>{it("membaca koma dan tanda kutip",()=>expect(parseCsv('Nama,Catatan\r\n"Lakban, Hitam","Ukuran ""besar"""')).toEqual([["Nama","Catatan"],["Lakban, Hitam",'Ukuran "besar"']]));it("memetakan template menjadi barang",()=>{const [item]=csvToItems("Nama,Kode,Kategori,Satuan,Stok Awal\nKursi,BT-1,Barang Tetap,unit,12");expect(item).toMatchObject({name:"Kursi",code:"BT-1",category:"Barang Tetap",unit:"unit",initial_stock:12});});it("menolak kategori tidak dikenal",()=>expect(()=>csvToItems("Nama,Kode,Kategori\nX,X-1,Elektronik")).toThrow(/Baris 2/));});
