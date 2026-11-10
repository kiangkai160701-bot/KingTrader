-- DRAFT ONLY — DO NOT APPLY TO PRODUCTION YET
-- KingStock POS additive schema proposal.
-- This file is intentionally not applied. Tenant/session mapping and safe stock mutation
-- must be completed and reviewed before any production DDL or RPC rollout.

begin;

create table if not exists private.pos_tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null default 'active'
    check (status in ('active','suspended','expired')),
  plan_code text not null default 'basic',
  created_at timestamptz not null default now()
);

-- A branch belongs to exactly one tenant. Existing branches are NOT auto-assigned:
-- the current system has no verified tenant ownership metadata.
create table if not exists private.pos_tenant_branches (
  tenant_id uuid not null references private.pos_tenants(id) on delete restrict,
  branch_id uuid not null references private.inventory_branches(id) on delete restrict,
  primary key (tenant_id, branch_id),
  unique (branch_id)
);

-- POS sale prices are kept separately from the legacy JSONB inventory state.
-- product_key must be mapped to the existing product object's stable id by a reviewed RPC.
create table if not exists private.pos_catalog (
  tenant_id uuid not null,
  branch_id uuid not null,
  product_key text not null,
  sale_price numeric(12,2) not null check (sale_price >= 0),
  barcode text,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, branch_id, product_key),
  foreign key (tenant_id, branch_id)
    references private.pos_tenant_branches(tenant_id, branch_id)
    on delete restrict
);

create table if not exists private.pos_sales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  branch_id uuid not null,
  receipt_no bigint generated always as identity,
  cashier_username text not null,
  payment_method text not null check (payment_method in ('cash','qr')),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null check (total >= 0),
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, branch_id, idempotency_key),
  unique (tenant_id, branch_id, receipt_no),
  foreign key (tenant_id, branch_id)
    references private.pos_tenant_branches(tenant_id, branch_id)
    on delete restrict
);

create table if not exists private.pos_sale_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  branch_id uuid not null,
  sale_id uuid not null,
  product_key text not null,
  product_name_snapshot text not null,
  unit_price_snapshot numeric(12,2) not null check (unit_price_snapshot >= 0),
  quantity numeric(12,3) not null check (quantity > 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, branch_id, sale_id)
    references private.pos_sales(tenant_id, branch_id, id)
    on delete restrict
);

create index if not exists pos_sales_tenant_branch_created_idx
  on private.pos_sales(tenant_id, branch_id, created_at desc);
create index if not exists pos_sale_items_sale_idx
  on private.pos_sale_items(tenant_id, branch_id, sale_id);

-- Private schema tables are intended to be accessed only through reviewed SECURITY DEFINER RPCs.
-- Do not grant direct client access. RPCs must validate the custom session token hash,
-- resolve tenant through pos_tenant_branches, verify branch active status and user permissions,
-- lock inventory_state FOR UPDATE, validate stock/price server-side, and perform sale+stock
-- mutation atomically. RLS/grants are deliberately not modified in this draft.

commit;
