-- Allow admins to see pending OTP codes when SMS delivery fails
-- (e.g. SMSC balance exhausted). Plaintext lives only as long as the
-- code itself (5 min) and is cleared once the code is used.

ALTER TABLE otp_codes
    ADD COLUMN code_plain TEXT,
    ADD COLUMN sms_sent BOOLEAN NOT NULL DEFAULT FALSE;
