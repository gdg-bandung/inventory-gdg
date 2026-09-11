import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";

const unauthorized=()=>NextResponse.json({error:"Unauthorized or expired session"},{status:401});
const denied=()=>NextResponse.json({error:"Tindakan ini hanya dapat dilakukan admin"},{status:403});

export async function GET(request:Request){
  const auth=await requireApiAuth(request);if(!auth)return unauthorized();
  const id=new URL(request.url).searchParams.get("id");
  const result=id
    ?await getSupabase().rpc("secure_get_inventory_stocktake_lines",{p_token:auth.token,p_stocktake_id:id})
    :await getSupabase().rpc("secure_get_inventory_stocktakes",{p_token:auth.token});
  return rpcError("stocktakes.list",result.error)??NextResponse.json({data:result.data});
}

export async function POST(request:Request){
  const auth=await requireApiAuth(request);if(!auth)return unauthorized();if(auth.user.role!=="admin")return denied();
  const body=await request.json();
  const{data,error}=await getSupabase().rpc("secure_create_inventory_stocktake",{p_token:auth.token,p_title:String(body.title??""),p_notes:String(body.notes??"")});
  const failure=rpcError("stocktakes.create",error);if(failure)return failure;if(!data)return unauthorized();return NextResponse.json({id:data});
}

export async function PUT(request:Request){
  const auth=await requireApiAuth(request);if(!auth)return unauthorized();const body=await request.json();let result;
  if(body.action==="complete"){if(auth.user.role!=="admin")return denied();result=await getSupabase().rpc("secure_complete_inventory_stocktake",{p_token:auth.token,p_id:body.id});}
  else if(body.action==="cancel"){if(auth.user.role!=="admin")return denied();result=await getSupabase().rpc("secure_cancel_inventory_stocktake",{p_token:auth.token,p_id:body.id});}
  else if(body.action==="save_lines")result=await getSupabase().rpc("secure_update_inventory_stocktake_lines",{p_token:auth.token,p_stocktake_id:body.id,p_lines:body.lines});
  else result=await getSupabase().rpc("secure_update_inventory_stocktake_line",{p_token:auth.token,p_stocktake_id:body.id,p_item_id:body.item_id,p_counted_stock:body.counted_stock});
  const failure=rpcError("stocktakes.update",result.error);if(failure)return failure;if(!result.data)return unauthorized();return NextResponse.json({ok:true});
}

export async function DELETE(request:Request){
  const auth=await requireApiAuth(request);if(!auth)return unauthorized();if(auth.user.role!=="admin")return denied();
  return NextResponse.json({error:"Riwayat stock opname tidak dapat dihapus"},{status:405});
}
