-- Long-form copy that partners fill in for each product. All nullable —
-- legacy/admin-created products without these stay empty and the mobile
-- app just hides the section.
--
-- Лина reads composition / precautions / usage in her catalog hint so she
-- can warn about contraindications and reference active ingredients.
ALTER TABLE products
    ADD COLUMN composition TEXT,
    ADD COLUMN precautions TEXT,
    ADD COLUMN usage_instructions TEXT,
    ADD COLUMN extra_info TEXT;
