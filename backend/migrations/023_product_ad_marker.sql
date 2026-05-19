-- Russian advertising legislation (38-ФЗ "О рекламе" + 347-ФЗ amendments)
-- requires affiliate-link / sponsored product cards to carry a "Реклама. …
-- ИНН … erid: …" marker. The text differs per advertiser, so we store it
-- per product. The boolean lets admins keep a saved marker and toggle
-- visibility without re-typing.
ALTER TABLE products
    ADD COLUMN ad_marker_visible BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN ad_marker_text TEXT;
