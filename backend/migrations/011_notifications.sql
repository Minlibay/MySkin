-- In-app notifications inbox. Each row is one card in the bell-screen.
-- `kind` drives icon / accent / deep-link target on the client.
-- `payload` carries kind-specific data (e.g. {"scan_id":"..."} for 'scan_ready').
CREATE TABLE notifications (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       TEXT NOT NULL,
    title      TEXT NOT NULL,
    body       TEXT,
    payload    JSONB NOT NULL DEFAULT '{}'::jsonb,
    read_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx
    ON notifications (user_id, created_at DESC);

-- Partial index makes the unread-count query O(unread count), not O(history).
CREATE INDEX notifications_user_unread_idx
    ON notifications (user_id) WHERE read_at IS NULL;
