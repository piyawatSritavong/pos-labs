-- One stock balance per product and store is a core inventory invariant. The
-- application selects one address when it sells; allowing a second active row
-- makes the stock page sum both while checkout can debit only one of them.
--
-- Do not guess how to merge existing duplicates: address codes may be
-- referenced by open bills. Fail the migration visibly so the deployment can
-- reconcile those rows without losing or double-counting stock.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "address_master"
    WHERE "is_active" = true
    GROUP BY "part_code", "store_id"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION
      'duplicate active stock locations found for the same part/store; reconcile them before migration 0034';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "uq_address_master_active_part_store"
  ON "address_master" ("part_code", "store_id")
  WHERE "is_active" = true;
