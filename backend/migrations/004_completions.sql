-- Per-day completion checkmarks for routine steps.
CREATE TABLE routine_completions (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    phase TEXT NOT NULL,           -- morning | evening
    step_index INT NOT NULL,
    step_title TEXT,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day, phase, step_index)
);
CREATE INDEX routine_completions_user_day_idx
    ON routine_completions (user_id, day DESC);
