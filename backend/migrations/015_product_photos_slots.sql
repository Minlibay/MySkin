-- Up to 4 photo slots per product. Old single-blob photo on products.photo
-- becomes slot 1 in the new table; existing endpoints will keep working
-- because the repository reads slot 1 by default.
CREATE TABLE product_photos (
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    slot        SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 4),
    bytes       BYTEA NOT NULL,
    mime        TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (product_id, slot)
);

-- Migrate every existing single photo to slot 1.
INSERT INTO product_photos (product_id, slot, bytes, mime)
SELECT id, 1, photo, COALESCE(photo_mime, 'image/jpeg')
FROM products
WHERE photo IS NOT NULL;

-- Keep products.photo + products.photo_mime columns for one release as a
-- write-through so older backend builds rolled back to don't lose photos.
-- A later migration can DROP them once we're confident.
