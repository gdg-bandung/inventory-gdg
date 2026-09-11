"use client";

import { useEffect } from "react";
import { ACTIVITY_STORAGE_KEY, authHeaders, clearClientSession, isInactive, storedJwt } from "@/lib/clientAuth";

const LIMIT=30*60*1000;
export function InactivityGuard(){useEffect(()=>{let lastWrite=0;let ending=false;const logout=async()=>{if(ending)return;ending=true;const headers=authHeaders();clearClientSession();await fetch("/api/auth/logout",{method:"POST",headers});window.location.replace("/login?reason=inactive");};const touch=()=>{const now=Date.now();if(now-lastWrite>15_000){localStorage.setItem(ACTIVITY_STORAGE_KEY,String(now));lastWrite=now;}};const check=()=>{const last=Number(localStorage.getItem(ACTIVITY_STORAGE_KEY)||0);if(!storedJwt()||isInactive(last,Date.now(),LIMIT)){void logout();return false;}return true;};const events=["pointerdown","keydown","scroll","touchstart"] as const;events.forEach((event)=>window.addEventListener(event,touch,{passive:true}));window.addEventListener("storage",check);if(check())touch();const timer=window.setInterval(check,30_000);return()=>{events.forEach((event)=>window.removeEventListener(event,touch));window.removeEventListener("storage",check);window.clearInterval(timer);};},[]);return null;}
