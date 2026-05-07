-- Users authenticate by phone via SMS OTP.
CREATE TABLE users (
    id UUID PRIMARY KEY,
    phone TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ,
    is_blocked BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX users_created_at_idx ON users (created_at DESC);

-- Long-lived bearer tokens issued after successful OTP verification.
CREATE TABLE sessions (
    token TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX sessions_user_idx ON sessions (user_id);

-- One pending OTP per phone. Code stored as sha256(pepper + phone + code).
CREATE TABLE otp_codes (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Admin operators. Separate auth — login/password, not phone.
CREATE TABLE admins (
    id UUID PRIMARY KEY,
    login TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ
);

CREATE TABLE admin_sessions (
    token TEXT PRIMARY KEY,
    admin_id UUID NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- Saved skin profiles from onboarding.
CREATE TABLE skin_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    skin_type TEXT,
    pores TEXT,
    concerns JSONB NOT NULL DEFAULT '[]'::jsonb,
    acne_type TEXT,
    sensitivity TEXT,
    sensitivity_reaction TEXT,
    budget TEXT,
    extras JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AI-generated routine snapshots. kind = 'standard' | 'derm2'.
CREATE TABLE routines (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    payload JSONB NOT NULL,
    confidence REAL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX routines_user_idx ON routines (user_id, created_at DESC);

-- Dermatologist 2.0 conversation transcripts.
CREATE TABLE derm_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile JSONB NOT NULL,
    history JSONB NOT NULL DEFAULT '[]'::jsonb,
    final_phase TEXT,
    confidence REAL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX derm_sessions_user_idx ON derm_sessions (user_id, created_at DESC);
