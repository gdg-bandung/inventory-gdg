-- 004_seed.sql (OPSIONAL)
-- Ganti password contoh sebelum dipakai di lingkungan yang dapat diakses orang lain.

insert into public.app_users(username, password_hash, full_name)
values ('admin', crypt('ganti-password-ini', gen_salt('bf')), 'Admin Inventaris')
on conflict ((lower(username))) do nothing;

insert into public.inventory_items
  (name, category, code, unit, initial_stock, min_stock, condition, location, purchase_price, purchase_date, owner_division, penanggung_jawab, notes)
values
  ('Kursi Lipat', 'Barang Tetap', 'BT-001', 'unit', 20, 5, 'Baik', 'Gudang Sekretariat', 185000, current_date - 240, 'Operasional', 'Koordinator Logistik', 'Periksa engsel setiap tiga bulan'),
  ('Lakban Hitam', 'Barang Habis Pakai', 'BHP-001', 'roll', 12, 5, null, 'Rak A2', 18000, current_date - 30, 'Operasional', 'Koordinator Logistik', null),
  ('Air Mineral 330ml', 'Konsumsi', 'KSM-001', 'karton', 8, 3, null, 'Pantry', 52000, current_date - 10, 'Acara', 'Koordinator Acara', null),
  ('Kabel HDMI 5m', 'Lainnya', 'LNY-001', 'pcs', 6, 2, null, 'Lemari Media', 95000, current_date - 150, 'Media', 'Koordinator Media', null)
on conflict ((lower(code))) do nothing;

-- Akun tambahan dapat dibuat manual dengan pola berikut:
-- insert into public.app_users(username, password_hash, full_name)
-- values ('nama-user', crypt('password-kuat', gen_salt('bf')), 'Nama Lengkap');
