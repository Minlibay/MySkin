-- Gender on user profile.
-- 'female' | 'male' | NULL (legacy users — treated as female for backward
-- compatibility, but the UI will ask if missing).
ALTER TABLE skin_profiles ADD COLUMN gender TEXT;

-- Seed default legal documents into app_settings if missing.
-- Admin can later overwrite these from the admin panel without changing code.
INSERT INTO app_settings (key, value) VALUES
    ('legal_terms', '# Пользовательское соглашение

Соглашение временно не настроено администратором приложения. Обратитесь в поддержку.'),
    ('legal_privacy', '# Политика конфиденциальности

Политика временно не настроена администратором приложения. Обратитесь в поддержку.'),
    ('legal_consent', '# Согласие на обработку персональных данных

Согласие временно не настроено администратором приложения. Обратитесь в поддержку.')
ON CONFLICT (key) DO NOTHING;
