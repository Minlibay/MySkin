-- Partner accounts (brand/manufacturer side of the marketplace).
-- Created by admin only — partners sign in with login + password and
-- manage their brands and products through partner.моякожа.рф.

CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE partners (
    id UUID PRIMARY KEY,
    login TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    company_name TEXT NOT NULL,
    contact_email TEXT,
    contact_phone TEXT,
    note TEXT,                         -- admin-only freeform notes
    is_blocked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ
);

CREATE TABLE partner_sessions (
    token TEXT PRIMARY KEY,
    partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX partner_sessions_partner_idx ON partner_sessions (partner_id);

-- Brand entity. Until now `products.brand` was just a free string and we
-- backfill it into rows here as part of this migration.
--
-- Name is CITEXT-unique so 'CeraVe' and 'cerave' collide — that's the
-- whole point of the "нельзя несколько раз создавать наименование" rule.
CREATE TABLE brands (
    id UUID PRIMARY KEY,
    name CITEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    -- Which partner currently owns this brand (their products, their stats).
    -- Null = unowned (legacy / admin-managed). One partner can own many brands.
    owner_partner_id UUID REFERENCES partners(id) ON DELETE SET NULL,
    -- Pending: created by partner, waiting for moderation.
    -- Approved: visible to mobile users.
    -- Rejected: hidden, reason in moderation_reason.
    status TEXT NOT NULL DEFAULT 'approved',
    moderation_reason TEXT,
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES admins(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX brands_owner_idx ON brands (owner_partner_id);
CREATE INDEX brands_status_idx ON brands (status);

-- Backfill: create a brand row for every distinct name currently in products,
-- then attach products to it. Whatever case appeared first wins (CITEXT
-- collapses the rest).
INSERT INTO brands (id, name, slug, status)
SELECT
    gen_random_uuid(),
    p.brand,
    lower(regexp_replace(p.brand, '[^a-zA-Z0-9]+', '-', 'g')),
    'approved'
FROM (
    SELECT DISTINCT ON (lower(brand)) brand
    FROM products
    ORDER BY lower(brand), created_at
) p
WHERE NOT EXISTS (SELECT 1 FROM brands b WHERE b.name = p.brand);

ALTER TABLE products
    ADD COLUMN brand_id UUID REFERENCES brands(id) ON DELETE RESTRICT,
    ADD COLUMN submitted_by_partner_id UUID
        REFERENCES partners(id) ON DELETE SET NULL,
    -- approved: live in the catalog (legacy products start here).
    -- pending: partner created/edited, waiting for review.
    -- rejected: hidden, reason kept for partner to see.
    ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'approved',
    ADD COLUMN moderation_reason TEXT,
    ADD COLUMN submitted_at TIMESTAMPTZ,
    ADD COLUMN reviewed_at TIMESTAMPTZ,
    ADD COLUMN reviewed_by UUID REFERENCES admins(id) ON DELETE SET NULL;

UPDATE products p
SET brand_id = b.id
FROM brands b
WHERE b.name = p.brand;

ALTER TABLE products ALTER COLUMN brand_id SET NOT NULL;
CREATE INDEX products_brand_id_idx ON products (brand_id);
CREATE INDEX products_moderation_status_idx ON products (moderation_status);
CREATE INDEX products_partner_idx ON products (submitted_by_partner_id);

-- Raw telemetry events from the mobile app. We keep them granular so the
-- partner sees actual numbers, not aggregates we can't audit later. Daily
-- rollup view sits on top.
--
-- kind:
--   impression — card scrolled into view (≥50% visible for ≥0.5s)
--   open       — user tapped the card / opened detail
--   buy_click  — user tapped the "Купить" CTA
--
-- surface:
--   catalog | recommendation | chat | shelf | scan_result
--
-- session_key is the mobile session id — used for impression dedup so
-- scrolling the same card past the viewport 5 times in one session
-- counts as one impression.
CREATE TABLE product_events (
    id BIGSERIAL PRIMARY KEY,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    kind TEXT NOT NULL,
    surface TEXT NOT NULL,
    session_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX product_events_product_idx
    ON product_events (product_id, created_at DESC);
CREATE INDEX product_events_kind_idx ON product_events (kind, created_at DESC);
-- Dedup impressions per (product, session) — used by INSERT ON CONFLICT
-- when the kind is 'impression'.
CREATE UNIQUE INDEX product_events_impression_unique
    ON product_events (product_id, session_key, kind)
    WHERE kind = 'impression' AND session_key IS NOT NULL;
