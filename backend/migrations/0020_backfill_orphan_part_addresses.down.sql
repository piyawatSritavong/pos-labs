-- Remove only untouched zero-stock rows created by the up migration. Preserve
-- any row that has subsequently received stock or been configured by a user.
DELETE FROM "address_master"
WHERE "remarks" = 'Automatically assigned by migration 0020'
  AND COALESCE("qty", 0) = 0
  AND COALESCE("rop", 0) = 0
  AND COALESCE("shelf", '') = '';
