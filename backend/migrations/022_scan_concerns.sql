-- Tags GigaChat Vision flags on a scan (acne / pih / redness / dehydration /
-- dullness / aging / sensitivity / oiliness / dryness). Persisted so the
-- product matcher can see what the photo revealed, not just what the user
-- ticked during onboarding.
ALTER TABLE scans
    ADD COLUMN concerns JSONB NOT NULL DEFAULT '[]'::jsonb;
