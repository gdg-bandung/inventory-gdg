export const JWT_STORAGE_KEY="inv_jwt";
export const ACTIVITY_STORAGE_KEY="inv_last_activity";
export function storedJwt(){return typeof window==="undefined"?null:localStorage.getItem(JWT_STORAGE_KEY);}
export function decodeStoredJwt(){const token=storedJwt();if(!token)return null;try{const raw=token.split('.')[1].replaceAll('-','+').replaceAll('_','/');const padded=raw.padEnd(Math.ceil(raw.length/4)*4,'=');const bytes=Uint8Array.from(atob(padded),(char)=>char.charCodeAt(0));return JSON.parse(new TextDecoder().decode(bytes)) as {username:string;full_name:string|null;role:"admin"|"member";exp:number};}catch{return null;}}
export function authHeaders(existing?:HeadersInit){const headers=new Headers(existing);const token=storedJwt();if(token)headers.set("Authorization",`Bearer ${token}`);return headers;}
export function clearClientSession(){localStorage.removeItem(JWT_STORAGE_KEY);localStorage.removeItem(ACTIVITY_STORAGE_KEY);}
export function isInactive(lastActivity:number,now=Date.now(),limit=30*60*1000){return !Number.isFinite(lastActivity)||lastActivity<=0||now-lastActivity>=limit;}
