import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/session";
import { UserManagement } from "./UserManagement";

export default async function UsersPage(){const user=await getSessionUser();if(!user||user.role!=="admin")redirect("/inventory");return <UserManagement/>;}
