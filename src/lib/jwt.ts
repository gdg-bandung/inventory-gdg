import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";
import type { SessionUser } from "@/components/inventory/types";

export type AppJwtPayload={sub:string;username:string;full_name:string|null;role:"admin"|"member";iat:number;exp:number;iss:"inventory-gdg-bandung"};
const encode=(value:string|Buffer)=>Buffer.from(value).toString("base64url");
function secret(){const value=process.env.APP_JWT_SECRET;if(!value||value.length<32)throw new Error("APP_JWT_SECRET minimal 32 karakter belum dikonfigurasi");return value;}
export function signAppJwt(user:SessionUser){const now=Math.floor(Date.now()/1000);const payload:AppJwtPayload={sub:user.username,username:user.username,full_name:user.full_name,role:user.role,iat:now,exp:now+60*60*24*7,iss:"inventory-gdg-bandung"};const head=encode(JSON.stringify({alg:"HS256",typ:"JWT"}));const body=encode(JSON.stringify(payload));const signature=createHmac("sha256",secret()).update(`${head}.${body}`).digest("base64url");return `${head}.${body}.${signature}`;}
export function verifyAppJwt(token:string):AppJwtPayload{const parts=token.split(".");if(parts.length!==3)throw new Error("JWT tidak valid");const expected=createHmac("sha256",secret()).update(`${parts[0]}.${parts[1]}`).digest();const actual=Buffer.from(parts[2],"base64url");if(actual.length!==expected.length||!timingSafeEqual(actual,expected))throw new Error("JWT tidak valid");const payload=JSON.parse(Buffer.from(parts[1],"base64url").toString("utf8")) as AppJwtPayload;if(payload.iss!=="inventory-gdg-bandung"||payload.exp<=Math.floor(Date.now()/1000)||!['admin','member'].includes(payload.role))throw new Error("JWT kedaluwarsa atau tidak valid");return payload;}
export function jwtFromRequest(request:Request){const header=request.headers.get("authorization");if(!header?.startsWith("Bearer "))throw new Error("JWT diperlukan");return verifyAppJwt(header.slice(7));}
