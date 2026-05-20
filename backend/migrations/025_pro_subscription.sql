-- Pro subscription flag. `pro_until` is the source of truth — when the
-- current timestamp is past pro_until (or the column is NULL), the user
-- is on the free tier. Storing an expiry instead of a boolean lets us
-- grant time-limited access (promo codes, beta access, paid month)
-- without a separate revoke job.
ALTER TABLE users
    ADD COLUMN pro_until TIMESTAMPTZ;

-- Helps the periodic "active pro users" admin counter and any future
-- cron that needs to find expiring subscriptions.
CREATE INDEX IF NOT EXISTS idx_users_pro_until
    ON users (pro_until)
    WHERE pro_until IS NOT NULL;
