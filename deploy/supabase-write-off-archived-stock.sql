-- Write off the stock stranded on archived products.
--
-- Deleting a product that any document references archives it: part_master and
-- every one of its address_master rows are switched off. The quantity on those
-- rows is left behind, and because both the vehicle stock page and the sale
-- search read only active rows, the pieces stop existing as far as the shop is
-- concerned — which is what the van staff hit when goods they could see on the
-- shelf were not on the till ("สินค้ามีในระบบ แต่ข้อมูลขายไม่มี").
--
-- 26 rows across 24 products were sitting like that: 1,703 pieces on pos1,
-- 291 on pos2, and 212 in the warehouse belonging to two of the same archived
-- products. The shop went through them and chose to write them off rather than
-- put the products back on sale.
--
-- Zeroing matters beyond tidiness. Receiving a purchase order does
-- `qty = qty + n, is_active = true` on the address row, so a hidden quantity
-- would come back as real stock the first time one of these products was
-- ordered again.
--
-- Usage:
--   psql "$DATABASE_URL" -f deploy/supabase-write-off-archived-stock.sql

BEGIN;

-- Only archived rows. An active row holding stock is real stock and is not
-- touched here.
UPDATE address_master
SET qty = 0
WHERE qty > 0
  AND is_active = false;

COMMIT;

-- Undo. These are the quantities the rows held before the write-off, captured
-- from the live database on 2026-09-02.
--
--   BEGIN;
--   UPDATE address_master SET qty = 12 WHERE code = 'ADDR0213';
--   UPDATE address_master SET qty = 200 WHERE code = 'ADDR0515';
--   UPDATE address_master SET qty = 25 WHERE code = 'VEH14570923B63B38A67E0B';
--   UPDATE address_master SET qty = 2 WHERE code = 'VEH179C936A1827FA4DDEC5';
--   UPDATE address_master SET qty = 189 WHERE code = 'VEH1D60310365D93C019F44';
--   UPDATE address_master SET qty = 50 WHERE code = 'VEH31757E723D130EDF25B8';
--   UPDATE address_master SET qty = 10 WHERE code = 'VEH3CFCA6337EE6FC3C47F3';
--   UPDATE address_master SET qty = 30 WHERE code = 'VEH3FAE338F1C785C2C13A4';
--   UPDATE address_master SET qty = 60 WHERE code = 'VEH4F4E9D739D61E09DA892';
--   UPDATE address_master SET qty = 200 WHERE code = 'VEH4F5E672A2849C6E59907';
--   UPDATE address_master SET qty = 195 WHERE code = 'VEH5B278391E2F0ED92D231';
--   UPDATE address_master SET qty = 30 WHERE code = 'VEH60C7852E54998815B9E6';
--   UPDATE address_master SET qty = 282 WHERE code = 'VEH71A46A0B70E7126DAC82';
--   UPDATE address_master SET qty = 60 WHERE code = 'VEH72CF042AB2D41C6F269D';
--   UPDATE address_master SET qty = 50 WHERE code = 'VEH74ABE68A1E01345D0813';
--   UPDATE address_master SET qty = 100 WHERE code = 'VEH7A8B0595E11D49CAD161';
--   UPDATE address_master SET qty = 50 WHERE code = 'VEH7CF0ED6726BDED3C7409';
--   UPDATE address_master SET qty = 1 WHERE code = 'VEH81F9D6CB9ACC76D21C96';
--   UPDATE address_master SET qty = 125 WHERE code = 'VEH82BB1186F36EBE04DC44';
--   UPDATE address_master SET qty = 4 WHERE code = 'VEH87266E70ADD2A5B4BA1B';
--   UPDATE address_master SET qty = 96 WHERE code = 'VEH9775ADCF5FC3AB350F85';
--   UPDATE address_master SET qty = 32 WHERE code = 'VEH98460DF77563A79D194D';
--   UPDATE address_master SET qty = 175 WHERE code = 'VEHA9D9C0AA96F8A3A41586';
--   UPDATE address_master SET qty = 60 WHERE code = 'VEHB477ACA684DC92DB303F';
--   UPDATE address_master SET qty = 60 WHERE code = 'VEHC4A2F5B36595F35CA65F';
--   UPDATE address_master SET qty = 108 WHERE code = 'VEHDC4CC991456228172631';
--   COMMIT;
