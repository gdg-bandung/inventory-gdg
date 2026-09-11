import "server-only";

import type { SessionUser } from "@/components/inventory/types";
import { jwtFromRequest, type AppJwtPayload } from "@/lib/jwt";
import { getSessionToken, getSessionUser } from "@/lib/session";

export type ApiAuth = {
  token: string;
  jwt: AppJwtPayload;
  user: SessionUser;
};

/** Require both the signed bearer JWT and the revocable httpOnly DB session. */
export async function requireApiAuth(request: Request): Promise<ApiAuth | null> {
  try {
    const token = await getSessionToken();
    if (!token) return null;
    const jwt = jwtFromRequest(request);
    const user = await getSessionUser();
    if (!user || user.username !== jwt.username || user.role !== jwt.role) return null;
    return { token, jwt, user };
  } catch {
    return null;
  }
}
