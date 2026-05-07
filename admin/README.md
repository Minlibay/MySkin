# MySkin · Admin

Лёгкая админка для бэкенда MySkin. React + Vite + TypeScript + Tailwind.

Использует существующие эндпоинты `/admin/*` нашего backend'а.

## Локальная разработка

```bash
cd admin
cp .env.example .env       # выставь VITE_BACKEND_URL если нужно
npm install
npm run dev                # http://localhost:5173
```

Логин по умолчанию (после `dart run bin/seed_admin.dart` на бэке):
- логин: `admin`
- пароль: `admin`

## Production build

```bash
VITE_BACKEND_URL=https://api.example.com npm run build
# результат в admin/dist/ — статика, лей куда угодно
```

## Деплой на VPS

### Вариант A — через Docker (рекомендую)

В корне репо есть `admin/Dockerfile` и `admin/nginx.conf`. Билд:

```bash
docker build \
  --build-arg VITE_BACKEND_URL=https://api.your-domain.tld \
  -t myskin-admin:latest \
  ./admin
```

Запуск:

```bash
docker run -d --name myskin-admin --restart unless-stopped \
  -p 8090:80 myskin-admin:latest
```

Поверх ставится reverse-proxy (Caddy / Traefik / nginx) с SSL.

### Вариант B — напрямую через nginx

```bash
# Билд на любой машине
cd admin
VITE_BACKEND_URL=https://api.your-domain.tld npm install && npm run build
# Скопируй dist/ на VPS
scp -r dist/* user@vps:/var/www/admin/
```

На VPS в `/etc/nginx/sites-available/admin.conf`:

```nginx
server {
    listen 443 ssl http2;
    server_name admin.your-domain.tld;

    ssl_certificate     /etc/letsencrypt/live/admin.your-domain.tld/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.your-domain.tld/privkey.pem;

    root /var/www/admin;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
    location ~* \.(js|css|woff2?|svg|png|jpg|webp|ico)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}

server {
    listen 80;
    server_name admin.your-domain.tld;
    return 301 https://$server_name$request_uri;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/admin.conf /etc/nginx/sites-enabled/
sudo certbot --nginx -d admin.your-domain.tld
sudo systemctl reload nginx
```

### Backend на той же VPS

Подними docker-compose из корня (`db` + `myskin-backend` если есть Dockerfile —
или dart-приложение через systemd) и проксируй `api.your-domain.tld → backend:8080`.

## Безопасность перед прод-выкаткой

В `backend/lib/handlers.dart` сейчас CORS открыт `*`. Перед выкладкой:

```dart
const _corsHeaders = {
  'access-control-allow-origin': 'https://admin.your-domain.tld',
  ...
};
```

Если понадобится несколько origins — middleware с проверкой `req.headers['origin']`.

## Что сделано

- Login (логин+пароль через `/admin/login`, токен в localStorage)
- Sidebar layout с навигацией
- Дашборд: 4 stats-карточки (`/admin/stats`)
- Юзеры: таблица с поиском, пагинацией, кнопками block/unblock

## Что НЕ сделано (намеренно)

- Просмотр профиля / scan-history конкретного юзера — нужны новые admin endpoints
- Каталог продуктов (CRUD) — пока только клиент-readonly
- Модерация контента / логи действий админа
- Фильтры по дате/статусу
- Multi-admin (сейчас один сидится из `.env`)

Это закрывается, когда понадобится — каждое одной фичей.
