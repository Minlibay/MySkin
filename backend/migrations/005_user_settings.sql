-- User-tunable settings: notification prefs, assistant name override, etc.
ALTER TABLE users
    ADD COLUMN settings JSONB NOT NULL DEFAULT '{}'::jsonb;
