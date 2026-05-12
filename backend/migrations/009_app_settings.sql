-- Small key-value bag for runtime-tweakable settings (GigaChat model
-- selection etc). Stays separate from per-user / per-product config so
-- admin overrides don't clash with domain tables.
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
