-- External "Купить" URL — the partner's marketplace / store page for this
-- product. Nullable: legacy/admin-managed products without a partner won't
-- have one and just don't show the CTA in the app.
ALTER TABLE products
    ADD COLUMN buy_url TEXT;
