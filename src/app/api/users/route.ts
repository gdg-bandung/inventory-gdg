import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";

const unauthorized=()=>NextResponse.json({error:"Unauthorized or expired session"},{status:401});
const denied=()=>NextResponse.json({error:"Hanya admin yang dapat mengelola pengguna"},{status:403});
export async function GET(request:Request){const auth=await requireApiAuth(request);if(!auth)return unauthorized();if(auth.user.role!=="admin")return denied();const{data,error}=await getSupabase().rpc("secure_get_app_users",{p_token:auth.token});return rpcError("users.list",error)??NextResponse.json({data});}
export async function POST(request:Request){const auth=await requireApiAuth(request);if(!auth)return unauthorized();if(auth.user.role!=="admin")return denied();const body=await request.json();const{data,error}=await getSupabase().rpc("secure_create_app_user",{p_token:auth.token,p_username:String(body.username??""),p_password:String(body.password??""),p_full_name:String(body.full_name??""),p_role:body.role});const failure=rpcError("users.create",error);if(failure)return failure;if(!data)return unauthorized();return NextResponse.json({id:data});}

export async function PUT(request:Request){
  const auth=await requireApiAuth(request);if(!auth)return unauthorized();if(auth.user.role!=="admin")return denied();
  const body=await request.json();let result;
  if(body.action==="reset_password")result=await getSupabase().rpc("secure_reset_app_user_password",{p_token:auth.token,p_id:body.id,p_password:String(body.password??"")});
  else if(body.action==="revoke_sessions")result=await getSupabase().rpc("secure_revoke_app_user_sessions",{p_token:auth.token,p_id:body.id});
  else result=await getSupabase().rpc("secure_update_app_user",{p_token:auth.token,p_id:body.id,p_full_name:String(body.full_name??""),p_role:body.role,p_is_active:Boolean(body.is_active)});
  const failure=rpcError("users.update",result.error);if(failure)return failure;if(!result.data)return unauthorized();return NextResponse.json({ok:true});
}
