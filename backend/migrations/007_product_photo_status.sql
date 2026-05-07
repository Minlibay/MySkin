-- Product photos (BYTEA) + draft/publish workflow.
ALTER TABLE products
    ADD COLUMN photo BYTEA,
    ADD COLUMN photo_mime TEXT,
    ADD COLUMN status TEXT NOT NULL DEFAULT 'draft';

-- Existing seeded products go straight to published — they have no photos
-- but otherwise are usable.
UPDATE products SET status = 'published';

CREATE INDEX products_status_idx ON products (status);
