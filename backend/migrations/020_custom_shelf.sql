-- Custom user-owned shelf products (own purchases, not part of catalog).
-- Kept fully separate from `products` so catalog/search/chat-rec queries
-- can never accidentally leak someone's personal items.
CREATE TABLE user_custom_products (
    id           UUID PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    brand        TEXT NOT NULL,
    name         TEXT NOT NULL,
    kind         TEXT NOT NULL,
    accent_color TEXT NOT NULL DEFAULT '#D98FA3',
    photo        BYTEA,
    photo_mime   TEXT,
    ingredients  JSONB NOT NULL DEFAULT '[]'::jsonb,
    status       TEXT NOT NULL DEFAULT 'have',  -- have | finished
    fill_level   TEXT,                          -- full | half | low | empty
    opened_at    DATE,
    expires_at   DATE,
    pao_months   INT,
    notes        TEXT,
    added_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX user_custom_products_user_idx ON user_custom_products (user_id);

-- Fill level and expiry for catalog products on a user's shelf as well.
ALTER TABLE user_products
    ADD COLUMN fill_level TEXT,
    ADD COLUMN opened_at  DATE,
    ADD COLUMN expires_at DATE,
    ADD COLUMN pao_months INT;
