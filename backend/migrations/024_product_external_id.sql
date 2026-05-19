-- External-source tracking for products imported from feeds (advcake,
-- partner price-lists, etc). external_id is whatever id the source uses
-- (Golden Apple's 19000XXXXX for advcake), external_source identifies
-- which feed produced this row ("advcake_ee4fe7…" — first 8 chars of the
-- feed handle is enough to disambiguate). Composite uniq lets us re-run
-- the importer idempotently: same offer in same feed → UPDATE, not
-- duplicate INSERT.
--
-- external_picture_url stores the first picture URL from the feed so the
-- admin can pull the photo lazily without re-fetching the whole feed.
ALTER TABLE products
    ADD COLUMN external_id TEXT,
    ADD COLUMN external_source TEXT,
    ADD COLUMN external_picture_url TEXT;

CREATE UNIQUE INDEX products_external_uniq_idx
    ON products (external_source, external_id)
    WHERE external_id IS NOT NULL;
