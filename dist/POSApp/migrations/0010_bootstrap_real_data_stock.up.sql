UPDATE "address_master" a
   SET "qty" = 100
 WHERE a."code" ~ '^ADDR[0-9]+$'
   AND a."store_id" = 'main'
   AND COALESCE(a."qty", 0) = 0
   AND NOT EXISTS (
       SELECT 1
         FROM "bill_item_detail" bid
        WHERE bid."address_code" = a."code"
   );
