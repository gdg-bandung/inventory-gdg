-- Jalankan manual setelah migration 001-008. Semua data uji di-ROLLBACK.
begin;

do $test$
declare v_schema text;
begin
  select n.nspname into v_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  execute format('insert into public.app_users(username,password_hash,full_name,role) values (%L,%I.crypt(%L,%I.gen_salt(%L)),%L,%L)',
    '__inventory_test__',v_schema,'test-password',v_schema,'bf','Inventory Test','admin');
end $test$;

create temporary table inventory_test_state(token text,item_id uuid,loan_id uuid);
insert into inventory_test_state(token) select token from public.secure_login('__inventory_test__','test-password');
update inventory_test_state set item_id=public.secure_save_inventory_item(token,null,'Kursi Uji','Barang Tetap','TEST-001','unit',10,2,'Baik','Gudang',100000,current_date,null,'QA','Tester',null,false);
update inventory_test_state set loan_id=public.secure_save_inventory_transaction(token,null,item_id,'Keluar',2,current_date,true,current_date+7,'Test Pinjam',null,null,null,'Tester Eksternal');
select public.secure_save_inventory_transaction(token,null,item_id,'Hilang',1,current_date,false,null,'Test Pinjam','Hilang saat dipinjam',loan_id,null,null) from inventory_test_state;

do $assert$
declare v_stock numeric; v_outstanding numeric;
begin
  select current_stock,outstanding into v_stock,v_outstanding from public.secure_get_inventory_items((select token from inventory_test_state)) where code='TEST-001';
  if v_stock<>8 then raise exception 'FAIL: stok harus 8, didapat %',v_stock; end if;
  if v_outstanding<>1 then raise exception 'FAIL: outstanding harus 1, didapat %',v_outstanding; end if;
  begin
    perform public.secure_save_inventory_item((select token from inventory_test_state),(select item_id from inventory_test_state),'Kursi Uji','Barang Tetap','TEST-001','unit',10,2,'Baik','Gudang',100000,current_date,null,'QA','Tester',null,true);
    raise exception 'FAIL: arsip seharusnya ditolak';
  exception when others then
    if sqlerrm not like '%masih dipinjam%' then raise; end if;
  end;
end $assert$;

rollback;
