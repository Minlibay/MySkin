-- Skin scan: photo bytes + computed metrics + zone heatmap scores.
CREATE TABLE scans (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    photo BYTEA,
    photo_mime TEXT,
    score INT NOT NULL,            -- overall skin index 0..100
    hydration INT NOT NULL,
    sebum INT NOT NULL,
    tone INT NOT NULL,
    pores INT NOT NULL,
    zones JSONB NOT NULL DEFAULT '{}'::jsonb,  -- {forehead:int, tzone:int, cheeks:int, chin:int}
    insight TEXT,                  -- short Лина line
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX scans_user_idx ON scans (user_id, created_at DESC);
