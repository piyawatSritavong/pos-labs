CREATE TABLE "promotion_master" (
  "code" varchar(16),
  "details" text,
  "unit" varchar(50),
  "amount" decimal(10,2),
  PRIMARY KEY ("code")
);

CREATE TABLE "unit_master" (
  "id" varchar(8),
  "label" text,
  "label_th" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "category_master" (
  "id" varchar(8),
  "label" text,
  "label_th" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "part_master" (
  "code" varchar(16),
  "bar_code" text,
  "category_id" varchar(8),
  "unit_id" varchar(8),
  "name" text,
  "name_th" text,
  "details" text,
  "cost" decimal(10,2),
  "price" decimal(10,2),
  "image" text,
  "is_active" boolean,
  PRIMARY KEY ("code"),
  CONSTRAINT "FK_part_master_unit_id"
    FOREIGN KEY ("unit_id")
      REFERENCES "unit_master"("id"),
  CONSTRAINT "FK_part_master_category_id"
    FOREIGN KEY ("category_id")
      REFERENCES "category_master"("id")
);

CREATE INDEX "unique" ON "part_master" ("bar_code");

CREATE TABLE "store_master" (
  "id" varchar(8),
  "label" text,
  "label_th" text,
  "is_default" boolean,
  PRIMARY KEY ("id")
);

CREATE TABLE "address_master" (
  "code" varchar(16),
  "part_code" varchar(16),
  "store_id" varchar(8),
  "shelf" text,
  "qty" integer,
  "min" integer,
  "max" integer,
  "rop" integer,
  "remarks" text,
  PRIMARY KEY ("code"),
  CONSTRAINT "FK_address_master_part_code"
    FOREIGN KEY ("part_code")
      REFERENCES "part_master"("code"),
  CONSTRAINT "FK_address_master_store_id"
    FOREIGN KEY ("store_id")
      REFERENCES "store_master"("id")
);

CREATE INDEX "idx_address_master_part_code" ON "address_master" ("part_code");

CREATE TABLE "permission" (
  "id" text,
  "name" text,
  "action" text, -- create, read, update, delete
  "resource" text, -- parts, bills, users, roles, permissions
  "detail" text, -- description of the permission
  PRIMARY KEY ("id")
);

CREATE TABLE "role" (
  "id" varchar(16),
  "name" text,
  "detail" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "role_permission" (
  "role_id" varchar(16),
  "permission_id" varchar(16),
  PRIMARY KEY ("role_id", "permission_id"),
  CONSTRAINT "FK_role_permission_permission_id"
    FOREIGN KEY ("permission_id")
      REFERENCES "permission"("id"),
  CONSTRAINT "FK_role_permission_role_id"
    FOREIGN KEY ("role_id")
      REFERENCES "role"("id")
);

CREATE TABLE "bill_master" (
  "id" varchar(16),
  "purchase_amount" decimal(10,2),
  "total_discount" decimal(10,2),
  "total_amount" decimal(10,2),
  "vat_amount" decimal(10,2),
  "xvat_amount" decimal(10,2),
  PRIMARY KEY ("id")
);

CREATE TABLE "bill_details" (
  "bill_id" varchar(16),
  "part_code" varchar(16),
  "unit_id" varchar(8),
  "uni_label" text,
  "unit_label_th" text,
  "name" text,
  "cost" decimal(10,2),
  "price" decimal(10,2),
  "qty" integer,
  PRIMARY KEY ("bill_id", "part_code"),
  CONSTRAINT "FK_bill_details_part_code"
    FOREIGN KEY ("part_code")
      REFERENCES "part_master"("code"),
  CONSTRAINT "FK_bill_details_bill_id"
    FOREIGN KEY ("bill_id")
      REFERENCES "bill_master"("id")
);

CREATE TABLE "bill_discount_detail" (
  "bill_id" varchar(16),
  "promotion_code" varchar(16),
  "unit" varchar(50),
  "amount" decimal(10,2),
  PRIMARY KEY ("bill_id", "promotion_code"),
  CONSTRAINT "FK_bill_discount_detail_promotion_code"
    FOREIGN KEY ("promotion_code")
      REFERENCES "promotion_master"("code"),
  CONSTRAINT "FK_bill_discount_detail_bill_id"
    FOREIGN KEY ("bill_id")
      REFERENCES "bill_master"("id")
);

CREATE TABLE "user" (
  "id" text,
  "username" text UNIQUE,
  "role_id" varchar(16),
  "name" text,
  "password" text,
  "is_active" boolean,
  PRIMARY KEY ("id"),
  CONSTRAINT "FK_user_role_id"
    FOREIGN KEY ("role_id")
      REFERENCES "role"("id")
);

CREATE TABLE "session" (
  "id" text PRIMARY KEY,
  "user_id" text NOT NULL,
  "ip" text,
  "user_agent" text,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "expires_at" timestamptz NOT NULL,
  "last_seen_at" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "FK_session_user_id"
    FOREIGN KEY ("user_id")
      REFERENCES "user"("id")
      ON DELETE CASCADE
);

CREATE INDEX "idx_session_user_id" ON "session" ("user_id");
CREATE INDEX "idx_session_expires_at" ON "session" ("expires_at");

