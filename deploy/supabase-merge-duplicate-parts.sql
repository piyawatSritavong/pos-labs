-- Fold products that are the same thing entered twice down to one row each.
--
-- The shop reported it on the tyres first: "ยางนอกมีสามรุ่น แต่ละสต๊อกใช้ชื่อ
-- ไม่เหมือนกัน … แก้ 9 รายการนี้ให้เหลือ 3 รายการก็พอค่ะ". The catalog has grown
-- over several years and several import files, and the same product came back
-- each time under whatever spelling was to hand — "ตะปู 1*17" and "ตะปู 1×17",
-- "แบต TS8809" and "แบต TS-8809", "ท่อ 1 1/4" and "ท่อ 1-1/4"".
--
-- Two sources feed the merge:
--
--   1. An explicit list, for duplicates whose names do not look alike at all.
--      The three tyres are the only entries: the shop identified them by hand.
--
--   2. Names that are identical once spacing and punctuation are ignored AND
--      that carry the same selling price. The price is the safety catch. Names
--      alone would have swept up "ใบมีดโกนขนนก ฿400" with "ใบมีดโกน ขนนก ฿20"
--      and "สายเอ็น 50 ฿150" with "สายเอ็น 50 ฿15" — a pack and a single piece,
--      which are different products wearing the same name. Those groups are
--      left alone for someone who knows the goods to settle.
--
-- Nothing is deleted. Every duplicate is referenced by a bill, a transfer or a
-- stock count, and address_master cascades on delete, so a DELETE would throw
-- the vans' stock rows away — which is what the shop noticed
-- ("พอ แอดมิน ลบรายการออก รายการในคลัง pos2 ก็ออกด้วย"). Duplicates are archived
-- instead, their stock is carried to the survivor store by store so the count
-- on each van does not change, and merged_into is set so the labels already
-- stuck to goods keep scanning.
--
-- Re-running is harmless: the second pass finds no active duplicates to drain.
--
-- Usage:
--   psql "$DATABASE_URL" -f deploy/supabase-merge-duplicate-parts.sql

BEGIN;

-- Present from migration 0033. Created here too so the data fix can run before
-- that migration is deployed; both use IF NOT EXISTS, so whichever lands first
-- makes the other a no-op.
ALTER TABLE "part_master" ADD COLUMN IF NOT EXISTS "merged_into" text;

-- Spacing and punctuation only. Every word and digit still has to match, so
-- "แบต 8809" and "แบต TS8809" stay apart; only the separator styles collapse.
-- Vulgar fractions become their decimal, because the two vans were writing the
-- same nail as "ตะปู 2½ x 12" and "ตะปู 2.5*12"; then the digit-x-digit rule
-- folds "1 x 17", "1*17" and "1×17" together without touching an x inside a
-- word like "XB".
CREATE FUNCTION pg_temp.part_name_key(raw text) RETURNS text AS $fn$
  SELECT translate(
           lower(regexp_replace(
             regexp_replace(
               replace(replace(replace(replace(raw,
                 '½', '.5'), '¼', '.25'), '¾', '.75'), '⅓', '.33'),
               '([0-9])[[:space:]]*[x×✕*][[:space:]]*([0-9])', '\1*\2', 'g'),
             '[[:space:]]', '', 'g')),
           '×✕-._"''“”`', '**');
$fn$ LANGUAGE sql IMMUTABLE;

CREATE TEMP TABLE part_merge_map (old_code text PRIMARY KEY, new_code text NOT NULL)
ON COMMIT DROP;

-- 1. Named by hand: the three tyres.
INSERT INTO part_merge_map (old_code, new_code) VALUES
    ('P0584', 'P1348'),   -- ยางนอก 60/100      -> ยางนอก (DS) 60/100/17
    ('P1027', 'P1348'),   -- ยางนอก 60/100-17   -> ยางนอก (DS) 60/100/17
    ('P1026', 'P1349'),   -- ยางนอก 70/90-17    -> ยางนอก (DS) 70/90/17
    ('P0585', 'P1350'),   -- ยางนอก 80/90       -> ยางนอก (DS) 80/90/17
    ('P1025', 'P1350');   -- ยางนอก 80/90-17    -> ยางนอก (DS) 80/90/17

-- 2. Same name, same price. The survivor is the row already carrying the most
--    stock, so the smallest correction is made to what is on the shelves; ties
--    go to the oldest code, which is the one whose labels have been in
--    circulation longest.
WITH candidate AS (
    SELECT p.code, p.price, pg_temp.part_name_key(p.name_th) AS key,
           COALESCE((
               SELECT SUM(a.qty) FROM address_master a
               WHERE a.part_code = p.code AND a.is_active
           ), 0) AS stock
    FROM part_master p
    WHERE p.is_active
),
duplicate_group AS (
    SELECT key,
           (array_agg(code ORDER BY stock DESC, code))[1] AS survivor
    FROM candidate
    GROUP BY key
    HAVING count(*) > 1 AND count(DISTINCT price) = 1
)
INSERT INTO part_merge_map (old_code, new_code)
SELECT c.code, d.survivor
FROM candidate c
JOIN duplicate_group d ON d.key = c.key
WHERE c.code <> d.survivor
ON CONFLICT (old_code) DO NOTHING;

-- A survivor must not itself be scheduled for archiving.
DO $$
DECLARE
    bad text;
BEGIN
    SELECT string_agg(DISTINCT new_code, ', ') INTO bad
    FROM part_merge_map m
    WHERE EXISTS (SELECT 1 FROM part_merge_map o WHERE o.old_code = m.new_code);
    IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'these survivors are also being merged away: %', bad;
    END IF;
END $$;

-- What has to move, per surviving product and store, before anything changes.
CREATE TEMP TABLE part_merge_moves ON COMMIT DROP AS
SELECT m.new_code, a.store_id, SUM(a.qty)::int AS moved_qty
FROM address_master a
JOIN part_merge_map m ON m.old_code = a.part_code
WHERE a.is_active AND a.qty <> 0
GROUP BY m.new_code, a.store_id;

-- 3. The survivor needs a stock row in every store the stock lands in. The code
--    is built the way the app builds it (repository.vehicleAddressCode:
--    sha1("<store>:<part>")), so a later restock reuses this row instead of
--    creating a second one beside it.
INSERT INTO address_master (code, part_code, store_id, shelf, qty, rop, remarks, is_active)
SELECT
    CASE WHEN v.store_id = 'main'
         THEN 'ADDR-' || v.new_code || '-main'
         ELSE 'VEH' || upper(substring(
                  encode(extensions.digest(v.store_id || ':' || v.new_code, 'sha1'), 'hex')
                  from 1 for 20))
    END,
    v.new_code,
    v.store_id,
    CASE WHEN v.store_id = 'main' THEN '' ELSE 'รถ' END,
    0,
    0,
    'รวมรายการสินค้าที่ซ้ำกัน',
    true
FROM part_merge_moves v
WHERE NOT EXISTS (
    SELECT 1 FROM address_master a
    WHERE a.part_code = v.new_code AND a.store_id = v.store_id
);

-- 4. Carry the duplicates' stock over to the survivor, store by store.
UPDATE address_master a
SET qty = a.qty + v.moved_qty,
    is_active = true
FROM part_merge_moves v
WHERE a.part_code = v.new_code
  AND a.store_id = v.store_id;

-- 5. Empty and archive the duplicates' stock rows. They are kept rather than
--    deleted because bill_item_detail.address_code points at some of them.
UPDATE address_master a
SET qty = 0,
    is_active = false
FROM part_merge_map m
WHERE a.part_code = m.old_code
  AND a.is_active;

-- 6. Take the duplicates out of the catalog and record where they went, so an
--    old printed label still rings up the surviving product.
UPDATE part_master p
SET is_active = false,
    merged_into = m.new_code
FROM part_merge_map m
WHERE p.code = m.old_code;

COMMIT;
