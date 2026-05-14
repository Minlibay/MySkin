-- Optional user avatar — shown in the profile circle and on Лина's read of
-- the user. Same BYTEA-in-row pattern as products.photo.
ALTER TABLE users
    ADD COLUMN avatar BYTEA,
    ADD COLUMN avatar_mime TEXT;
