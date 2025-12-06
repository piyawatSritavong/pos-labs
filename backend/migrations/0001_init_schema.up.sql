create table "company_setting"(
  tax_id text,
  company_name text not null,
  company_name_th text not null,
  company_address text not null,
  company_address_th text not null,
  phone text not null,
  email text,
  website text,
  logo_url text,
  tax_rate decimal(10,2) not null default 0.07,
  tax_type text not null default 'xvat', -- vat, xvat
  PRIMARY KEY ("tax_id")
);

create table "branch_setting"(
  branch_id text, -- 00000, 00001, 00002, ...
  company_id text not null,
  branch_name text not null,
  branch_name_th text not null,
  branch_address text not null,
  branch_address_th text not null,
  phone text not null,
  email text,
  PRIMARY KEY ("branch_id")
);

create table "pos_setting"(
  pos_id text,
  branch_id text not null,
  pos_name text not null,
  PRIMARY KEY ("pos_id"),
  CONSTRAINT "FK_pos_setting_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id")
);

CREATE TABLE "promotion_master" (
  "code" text,
  "details" text,
  "unit" text,
  "amount" decimal(10,2),
  PRIMARY KEY ("code")
);

CREATE TABLE "unit_master" (
  "id" text,
  "label" text,
  "label_th" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "category_master" (
  "id" text,
  "label" text,
  "label_th" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "part_master" (
  "code" text,
  "bar_code" text,
  "category_id" text,
  "unit_id" text,
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
  "id" text,
  "branch_id" text not null,
  "label" text,
  "label_th" text,
  "is_default" boolean,
  PRIMARY KEY ("id"),
  CONSTRAINT "FK_store_master_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id")
);

CREATE TABLE "address_master" (
  "code" text,
  "part_code" text,
  "store_id" text,
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
  "id" text,
  "name" text,
  "detail" text,
  PRIMARY KEY ("id")
);

CREATE TABLE "role_permission" (
  "role_id" text,
  "permission_id" text,
  PRIMARY KEY ("role_id", "permission_id"),
  CONSTRAINT "FK_role_permission_permission_id"
    FOREIGN KEY ("permission_id")
      REFERENCES "permission"("id"),
  CONSTRAINT "FK_role_permission_role_id"
    FOREIGN KEY ("role_id")
      REFERENCES "role"("id")
);

CREATE TABLE "member_master" (
  "id" text,
  "code" text, -- 000001, 000002,
  "name" text,
  "phone" text UNIQUE NOT NULL,
  "email" text,
  "points" integer not null default 0,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE "counter"(
 "key" text, --"member" (static), "20251204" (date-based for bills), etc.
 "value" integer, --1,2,3,4,5, ...
 PRIMARY KEY ("key")
);

CREATE TABLE "bill_master" (
  "id" text, --20251204000001, 20251204000002, ... generated from bill_counter
  "branch_id" text not null,
  "pos_id" text not null,
  "status" text not null default 'new', --new, hold, completed, cancelled
  "payment_method" text, --cash, bank, credit, debit, other
  "payment_ref" text, --payment reference number
  "member_id" text,
  "customer_name" text not null default 'ทั่วไป',
  "purchase_amount" decimal(10,2) not null default 0,
  "total_discount" decimal(10,2) not null default 0,
  "total_amount" decimal(10,2) not null default 0,
  "vat_amount" decimal(10,2) not null default 0,
  "xvat_amount" decimal(10,2) not null default 0,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "created_by" text,
  "updated_by" text,
  PRIMARY KEY ("id"),
  CONSTRAINT "FK_bill_master_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_bill_master_pos_id"
    FOREIGN KEY ("pos_id")
      REFERENCES "pos_setting"("pos_id"),
  CONSTRAINT "FK_bill_master_member_id"
    FOREIGN KEY ("member_id")
      REFERENCES "member_master"("id")
);

CREATE TABLE "bill_item_detail" (
  "bill_id" text,
  "part_code" text,
  "address_code" text,
  "unit_id" text,
  "uni_label" text,
  "unit_label_th" text,
  "name" text,
  "cost" decimal(10,2),
  "price" decimal(10,2),
  "qty" integer,
  PRIMARY KEY ("bill_id", "part_code", "address_code"),
  CONSTRAINT "FK_bill_item_detail_address_code"
    FOREIGN KEY ("address_code")
      REFERENCES "address_master"("code"),
  CONSTRAINT "FK_bill_item_detail_bill_id"
    FOREIGN KEY ("bill_id")
      REFERENCES "bill_master"("id"),
  CONSTRAINT "FK_bill_item_detail_part_code"
    FOREIGN KEY ("part_code")
      REFERENCES "part_master"("code")
);

CREATE TABLE "bill_discount_detail" (
  "bill_id" text,
  "promotion_code" text,
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
  "role_id" text,
  "name" text,
  "password" text,
  "is_active" boolean,
  "is_superuser" boolean not null default false, --access to all branches and cannot be deleted
  PRIMARY KEY ("id"),
  CONSTRAINT "FK_user_role_id"
    FOREIGN KEY ("role_id")
      REFERENCES "role"("id")
);

CREATE TABLE "user_branch" (
  "user_id" text,
  "branch_id" text,
  PRIMARY KEY ("user_id", "branch_id"),
  CONSTRAINT "FK_user_branch_user_id"
    FOREIGN KEY ("user_id")
      REFERENCES "user"("id"),
  CONSTRAINT "FK_user_branch_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id")
);

CREATE TABLE "session" (
  "id" text PRIMARY KEY,
  "user_id" text NOT NULL UNIQUE,
  "branch_id" text,
  "pos_id" text,
  "ip" text,
  "user_agent" text,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "expires_at" timestamptz NOT NULL,
  "last_seen_at" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "FK_session_user_id"
    FOREIGN KEY ("user_id")
      REFERENCES "user"("id")
      ON DELETE CASCADE,
  CONSTRAINT "FK_session_branch_id"
    FOREIGN KEY ("branch_id")
      REFERENCES "branch_setting"("branch_id"),
  CONSTRAINT "FK_session_pos_id"
    FOREIGN KEY ("pos_id")
      REFERENCES "pos_setting"("pos_id")
);

CREATE INDEX "idx_session_expires_at" ON "session" ("expires_at");

