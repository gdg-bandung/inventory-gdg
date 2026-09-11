import { describe,expect,it } from "vitest";
import { isInactive } from "./clientAuth";

describe("idle session",()=>{it("tetap aktif sebelum 30 menit",()=>expect(isInactive(1_000,1_000+29*60_000)).toBe(false));it("berakhir tepat setelah 30 menit",()=>expect(isInactive(1_000,1_000+30*60_000)).toBe(true));it("menolak timestamp kosong",()=>expect(isInactive(0,Date.now())).toBe(true));});
