-- Jalankan manual setelah migration 001-010 dan saat tidak ada stock opname draft.
-- Seluruh data uji dibatalkan pada akhir transaksi.
begin;

do $test$
declare v_schema text;
begin
  select n.nspname into v_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  execute format('insert into public.app_users(username,password_hash,full_name,role) values (%L,%I.crypt(%L,%I.gen_salt(%L)),%L,%L)',
    '__integrity_admin__',v_schema,'test-password',v_schema,'bf','Integrity Admin','admin');
end $test$;

create temporary table integrity_state(admin_token text,member_token text,item_id uuid,member_id uuid,loan_id uuid,stocktake_id uuid);
insert into integrity_state(admin_token) select token from public.secure_login('__integrity_admin__','test-password');
update integrity_state set item_id=public.secure_save_inventory_item(admin_token,null,'Barang Integritas Uji','Barang Tetap','INTEGRITY-TEST-001','unit',10,2,'Baik','Gudang',null,current_date,null,'QA','Tester',null,false);
update integrity_state set member_id=public.secure_create_app_user(admin_token,'__integrity_member__','test-password','Integrity Member','member');
update integrity_state set member_token=(select token from public.secure_login('__integrity_member__','test-password'));

do $assert$
begin
  begin
    perform public.secure_save_inventory_item((select member_token from integrity_state),(select item_id from integrity_state),'Barang Integritas Uji','Barang Tetap','INTEGRITY-TEST-001','unit',10,2,'Baik','Gudang',null,current_date,null,'QA','Tester',null,false);
    raise exception 'FAIL: member seharusnya tidak dapat mengubah master';
  exception when others then if sqlerrm not like '%Hanya admin%' then raise; end if; end;
  begin
    perform public.secure_save_inventory_transaction((select member_token from integrity_state),null,(select item_id from integrity_state),'Penyesuaian',1,current_date,false,null,'Uji',null,null,null,null);
    raise exception 'FAIL: member seharusnya tidak dapat membuat penyesuaian';
  exception when others then if sqlerrm not like '%hanya dapat dibuat admin%' then raise; end if; end;
  begin
    perform public.secure_save_inventory_transaction((select admin_token from integrity_state),null,(select item_id from integrity_state),'Keluar',1,current_date,true,null,'Uji tanggal',null,null,(select member_id from integrity_state),null);
    raise exception 'FAIL: pinjaman tanpa tanggal kembali seharusnya ditolak';
  exception when others then if sqlerrm not like '%Tanggal rencana kembali%' then raise; end if; end;
end $assert$;

update integrity_state set loan_id=public.secure_save_inventory_transaction(member_token,null,item_id,'Keluar',2,current_date,true,current_date+7,'Uji pinjam',null,null,member_id,null);

do $assert$
begin
  begin
    perform public.secure_save_inventory_transaction((select member_token from integrity_state),(select loan_id from integrity_state),(select item_id from integrity_state),'Keluar',3,current_date,true,current_date+7,'Uji edit',null,null,(select member_id from integrity_state),null);
    raise exception 'FAIL: member seharusnya tidak dapat mengubah transaksi lama';
  exception when others then if sqlerrm not like '%Hanya admin%' then raise; end if; end;
  begin
    perform public.secure_delete_inventory_item((select admin_token from integrity_state),(select item_id from integrity_state));
    raise exception 'FAIL: barang dengan histori seharusnya tidak dapat dihapus';
  exception when others then if sqlerrm not like '%memiliki riwayat%' then raise; end if; end;
end $assert$;

update integrity_state set stocktake_id=public.secure_create_inventory_stocktake(admin_token,'Uji freeze integritas',null);
do $assert$
begin
  begin
    perform public.secure_save_inventory_transaction((select member_token from integrity_state),null,(select item_id from integrity_state),'Masuk',1,current_date,false,null,'Uji freeze',null,null,null,null);
    raise exception 'FAIL: transaksi selama stock opname seharusnya ditolak';
  exception when others then if sqlerrm not like '%dibekukan%' then raise; end if; end;
end $assert$;
select public.secure_cancel_inventory_stocktake(admin_token,stocktake_id) from integrity_state;
select public.secure_reverse_inventory_transaction(admin_token,loan_id,'Data uji reversal') from integrity_state;

do $assert$
declare v_stock numeric; v_outstanding numeric; v_tx integer; v_reversal integer;
begin
  select current_stock,outstanding into v_stock,v_outstanding from public.secure_get_inventory_items((select admin_token from integrity_state)) where id=(select item_id from integrity_state);
  if v_stock<>10 or v_outstanding<>0 then raise exception 'FAIL: reversal harus memulihkan stok/outstanding menjadi 10/0, didapat %/%',v_stock,v_outstanding; end if;
  select count(*) into v_tx from public.inventory_transactions where id=(select loan_id from integrity_state);
  select count(*) into v_reversal from public.inventory_transaction_reversals where transaction_id=(select loan_id from integrity_state);
  if v_tx<>1 or v_reversal<>1 then raise exception 'FAIL: transaksi asli dan reversal harus sama-sama tersimpan'; end if;
end $assert$;

rollback;
