-- Skincare product catalog.
CREATE TABLE products (
    id UUID PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    brand TEXT NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,             -- cleanser | toner | essence | serum | moisturizer | spf | mask | eye_cream
    description TEXT NOT NULL,
    price_rub INT NOT NULL,
    accent_color TEXT NOT NULL,     -- hex like '#D98FA3' for bottle gradient
    ingredients JSONB NOT NULL DEFAULT '[]'::jsonb,  -- top INCI names
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,         -- concerns it addresses (acne, pih, aging, ...)
    skin_types JSONB NOT NULL DEFAULT '[]'::jsonb,   -- skin types it suits
    is_active_ingredient BOOLEAN NOT NULL DEFAULT FALSE,
    gentle BOOLEAN NOT NULL DEFAULT FALSE,
    routine_phase TEXT NOT NULL DEFAULT 'any',       -- morning | evening | any
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX products_kind_idx ON products (kind);
CREATE INDEX products_brand_idx ON products (brand);

-- User's shelf — products they own / want / finished.
CREATE TABLE user_products (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    status TEXT NOT NULL,            -- have | wishlist | finished
    notes TEXT,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);
CREATE INDEX user_products_user_idx ON user_products (user_id);
