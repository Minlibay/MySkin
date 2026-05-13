-- Persisted chat history with Лина.
-- Stored as a flat append-only log per user; latest N are loaded on app open
-- so the conversation survives restarts and device changes.
CREATE TABLE chat_messages (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content    TEXT NOT NULL,
    -- For assistant turns where Лина flagged show_products: the array of
    -- product cards she pinned to that turn (slugs + brand + name + reasons).
    -- NULL for plain text turns and all user messages.
    products   JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX chat_messages_user_idx
    ON chat_messages (user_id, created_at);
