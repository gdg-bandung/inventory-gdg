-- Jalankan manual setelah migration 001-009 dan saat tidak ada stock opname draft.
-- Seluruh data uji dibatalkan pada akhir transaksi.
begin;

do $test$
declare v_schema text;
begin
  select n.nspname into v_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  execute format('insert into public.app_users(username,password_hash,full_name,role) values (%L,%I.crypt(%L,%I.gen_salt(%L)),%L,%L)',
    '__stocktake_admin__',v_schema,'test-password',v_schema,'bf','Stocktake Admin','admin');
end $test$;

create temporary table stocktake_test_state(token text,item_id uuid,stocktake_id uuid,member_id uuid);
insert into stocktake_test_state(token) select token from public.secure_login('__stocktake_admin__','test-password');
update stocktake_test_state set item_id=public.secure_save_inventory_item(token,null,'Barang Opname Uji','Barang Tetap','STOCKTAKE-TEST-001','unit',10,2,'Baik','Gudang',null,current_date,null,'QA','Tester',null,false);
update stocktake_test_state set member_id=public.secure_create_app_user(token,'__stocktake_member__','test-password','Stocktake Member','member');
update stocktake_test_state set stocktake_id=public.secure_create_inventory_stocktake(token,'Stock opname regresi',null);
select public.secure_update_inventory_stocktake_lines(token,stocktake_id,jsonb_build_array(jsonb_build_object('item_id',item_id,'counted_stock',7))) from stocktake_test_state;
select public.secure_complete_inventory_stocktake(token,stocktake_id) from stocktake_test_state;

do $assert$
declare v_stock numeric; v_adjustments integer; v_status text;
begin
  select current_stock into v_stock from public.secure_get_inventory_items((select token from stocktake_test_state)) where code='STOCKTAKE-TEST-001';
  if v_stock<>7 then raise exception 'FAIL: stok setelah opname harus 7, didapat %',v_stock; end if;
  select count(*) into v_adjustments from public.inventory_transactions where item_id=(select item_id from stocktake_test_state) and type='Penyesuaian' and quantity=-3;
  if v_adjustments<>1 then raise exception 'FAIL: transaksi penyesuaian -3 tidak ditemukan'; end if;
  select status into v_status from public.inventory_stocktakes where id=(select stocktake_id from stocktake_test_state);
  if v_status<>'completed' then raise exception 'FAIL: status stock opname harus completed'; end if;
end $assert$;

rollback;
