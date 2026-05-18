# MySkin — Production Deploy

Полный стек (db + backend + admin) контейнеризован. Один `docker compose up -d`
поднимает всё. Caddy на фронте делает auto-HTTPS через Let's Encrypt.

## TL;DR

```bash
# на VPS
git clone <repo>
cd myskin
cp .env.example .env
nano .env             # выставить prod-секреты
nano Caddyfile        # заменить example.com на свой домен
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
docker compose exec backend /app/seed_admin
```

Готово. Через минуту-две Caddy получит SSL и приложение доступно по
`https://api.example.com` и `https://admin.example.com`.

---

## Локальный запуск (dev)

```bash
cp .env.example .env
docker compose up -d --build       # db + backend + admin + adminer
docker compose exec backend /app/seed_admin
```

Сервисы:
- backend → `http://localhost:8080`
- admin   → `http://localhost:8090`
- adminer → `http://localhost:8081` (system: PostgreSQL, server: `db`, user/pass из .env)
- db      → `localhost:15432` (хост экспонирован для разработки)

Логи:
```bash
docker compose logs -f backend
```

Вход в admin: `admin` / `admin` (по умолчанию из `.env`).

---

## Прод-деплой на VPS

### Что нужно

- VPS с Ubuntu 22.04+ (минимум **2 GB RAM**, иначе dart-build не пройдёт)
- Docker + docker-compose plugin
- Доменное имя с управлением DNS
- Открытые порты **80** и **443** наружу

### Шаг 1 — DNS

В личном кабинете регистратора создай A-записи на IP сервера:

| Имя                | Тип | Значение         |
|--------------------|-----|------------------|
| `api.example.com`  | A   | `<ip сервера>`   |
| `admin.example.com`| A   | `<ip сервера>`   |
| `app.example.com`  | A   | `<ip сервера>`   |

Подожди распространения DNS (`dig api.example.com` должен вернуть твой IP).

### Шаг 2 — Установка Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### Шаг 3 — Клонирование и настройка

```bash
git clone <ваш репо>
cd myskin
cp .env.example .env
```

В `.env` обязательно поменяй:
```env
POSTGRES_PASSWORD=<длинный_рандом>
OTP_PEPPER=<длинный_рандом>          # ВАЖНО: выбрать ОДИН раз и не менять
ADMIN_PASSWORD=<длинный_рандом>
CORS_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com
PUBLIC_BACKEND_URL=https://api.example.com
VOICEPASSWORD_API_KEY=<api_ключ_voicepassword>
# Legacy SMSC — оставлены пустыми, можно использовать как откат.
SMSC_LOGIN=
SMSC_PASSWORD=
GIGACHAT_AUTH_KEY=<ключ>
```

В `Caddyfile` замени все `example.com` на свой домен.

### Шаг 4 — Запуск

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Caddy запросит сертификаты автоматически (1-2 минуты).

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f caddy
```

### Шаг 5 — Сидим админа

```bash
docker compose exec backend /app/seed_admin
```

### Шаг 6 — Проверка

```bash
curl https://api.example.com/health
# {"ok":true}
```

Открой `https://admin.example.com` → залогинься.

---

## Обновление

```bash
git pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
# миграции накатываются автоматически при старте backend
```

## Бэкап БД

```bash
docker compose exec -T db pg_dump -U myskin myskin | gzip > backup-$(date +%F).sql.gz
```

Восстановление:
```bash
gunzip -c backup-2026-05-07.sql.gz | docker compose exec -T db psql -U myskin myskin
```

Кладите бэкапы в крон через `cron.daily`.

## Что нужно мониторить

- Свободное место (фото в `BYTEA` могут расти): `docker system df`
- Логи: `docker compose logs -f --tail 100 backend`
- Сертификаты Caddy продлеваются сами; если упали — `docker compose logs caddy`

## Безопасность — чек-лист перед публичным запуском

- [x] CORS whitelist (НЕ `*`)
- [x] `OTP_PEPPER` уникальный длинный
- [x] `ADMIN_PASSWORD` сменён, не `admin`
- [x] Postgres за docker network, не наружу (в prod overlay `ports: []`)
- [x] HTTPS через Caddy
- [x] Rate-limit на `/auth/send-code` (3 req/min, 20/hr per IP)
- [ ] Бэкапы БД настроены (cron)
- [ ] Мониторинг (Uptime Kuma / Healthchecks.io)
- [ ] Лимит размера загружаемого фото 6 MB (уже в коде)

## Проблемы

**Build падает с OOM на VPS с 1 GB RAM** — dart-compile тяжёлый. Минимум 2 GB
или собирай образ локально и заливай в registry.

**Caddy не может получить сертификат** — проверь что DNS уже распространился
и порты 80/443 не заняты другим nginx/apache. `sudo systemctl stop nginx`.

**voicepassword возвращает `not_enough_money`** — пополни баланс в ЛК
voicepassword.ru. При любой ошибке провайдера OTP всё равно сохраняется в БД
и виден в админке (Codes), плюс плейнтекст уходит в `stdout` контейнера
(`docker compose logs backend | grep DEV`).

**voicepassword возвращает `unknown_request` / `authorisation_failed`** —
проверь, что в ЛК активирован SMS-канал и API ключ правильный. Если
SMS-only запрос (`{"number","sms":{}}`) у них не поддерживается напрямую,
нужно либо переключить шаблон в ЛК, либо менять флоу на двухшаговый
(сначала голос, потом досылка по `id`).

**GigaChat OAuth timeout** — порт 9443 у Sber иногда режут провайдеры.
Проверь: `curl -v --max-time 10 https://ngw.devices.sberbank.ru:9443/api/v2/oauth`.
