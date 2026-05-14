-- User favourites — a separate concept from "shelf" (which tracks owned /
-- want / archived state). Favouriting is the lightweight "bookmark" you can
-- toggle freely from the product detail screen.
CREATE TABLE user_favorites (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);

CREATE INDEX user_favorites_user_idx
    ON user_favorites (user_id, added_at DESC);
