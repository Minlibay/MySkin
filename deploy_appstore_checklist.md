# App Store submission checklist — Моя Кожа

Что **в коде** уже сделано (для контекста):
- `Info.plist`: `ITSAppUsesNonExemptEncryption=false`, осмысленные `NS*UsageDescription` для камеры/микрофона/фото/распознавания речи.
- `ios/Runner/PrivacyInfo.xcprivacy` — privacy-манифест (требование с мая 2024).
- `Permission_handler` + bulk-ask на первом запуске + полноэкранный «Открыть настройки» при отказе.
- `BackendApi.deleteAccount` — удаление аккаунта.
- Медицинский disclaimer-баннер в чате с Линой + `/legal/medical` документ в админке.
- Moderator-телефон `+70000000000` / код `1111` для ревью без реальной SMS.

Ниже — то, что **не делается кодом** и нужно ввести/загрузить руками в App Store Connect.

---

## 1. Privacy

### App Privacy (Privacy Nutrition Labels)
В App Store Connect → твой app → **App Privacy**. Должно совпадать с `PrivacyInfo.xcprivacy`:

| Категория | Поле | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info | Phone Number | Yes | No | App Functionality |
| User Content | Photos or Videos | Yes | No | App Functionality |
| User Content | Audio Data | Yes | No | App Functionality |
| User Content | Other User Content | Yes | No | App Functionality |
| Health & Fitness | Health | Yes | No | App Functionality |
| Diagnostics | Crash Data | No | No | App Functionality |
| Diagnostics | Performance Data | No | No | App Functionality |
| Diagnostics | Other Diagnostic Data | No | No | Analytics |

### Privacy Policy URL
- Поле «Privacy Policy URL» в App Store Connect — обязательно.
- У вас есть `/legal/privacy` через `LegalHandlers`. Нужен **публичный** URL: что-то вроде `https://myskin.app/legal/privacy` или хостинг текста на отдельной странице.
- Этот же URL покажите внутри приложения (уже есть — `LegalViewerScreen`).

### Terms of Service URL (необязательно, но желательно для апп с UGC и AI-выводом)
- Поле «Terms of Use» в App Store Connect — необязательное, но Apple рекомендует.
- Можно положить рядом с privacy: `https://myskin.app/legal/terms`.

---

## 2. Account & Content

### Account deletion (Guideline 5.1.1(v))
- Apple **вручную проверяет**, что в приложении есть кнопка «Удалить аккаунт», доступная без саппорт-обращения.
- Проверь, что в `/profile` есть видимый CTA «Удалить аккаунт» и что после нажатия:
  - удаляются сканы, чаты, профиль, кастомные продукты;
  - сессия инвалидируется;
  - показывается подтверждение.
- В Reviewer Notes напиши явный путь: «Профиль → Удалить аккаунт».

### Sign in with Apple (Guideline 4.8)
- Требуется, **если** есть third-party SSO (Google, Facebook, Twitter, …).
- У вас только phone-OTP — это first-party identifier, **исключение**.
- В Reviewer Notes напиши: «Authentication is phone OTP only. No third-party SSO is offered, so Sign in with Apple is not applicable per Guideline 4.8.»

### User-Generated Content (Guideline 1.2)
- В приложении пользователь видит контент только от себя и от Лины (AI). Между пользователями контент не шарится. Это формально **не UGC**.
- Но AI-вывод Apple последние месяцы рассматривает как «model-generated content». Безопасно:
  - оставить медицинский disclaimer в чате с Линой (уже есть);
  - в Reviewer Notes указать, что Лина — AI-ассистент, не врач.

---

## 3. Tracking

### App Tracking Transparency (ATT)
- ATT-prompt нужен, **только если** трекаешь юзера через сторонние сети для рекламы / атрибуции.
- Sentry в режиме crash + perf без отправки IDFA — **не** трекинг. ATT не нужен.
- Проверь `SentryFlutter.init` в `main.dart`: убедись, что `sendDefaultPii: false` и `beforeSend` фильтрует email/телефон, если они туда попадают.

---

## 4. Метаданные в App Store Connect

### Скриншоты
Обязательны минимум:
- 6.7" Display (iPhone 15 Pro Max) — 1290×2796
- 6.5" Display (iPhone XS Max) — 1242×2688 или эквивалент

Сделать ~5-10 скриншотов основных экранов:
1. Главная (индекс кожи + кнопки)
2. Сканер (превью с круговой подсказкой)
3. Результат скана (карта улучшений с точками)
4. Чат с Линой
5. Каталог
6. Ритуал (утро/вечер)
7. Профиль

### App Preview (видео) — необязательно
30-сек ролик сильно поднимает конверсию из листинга, но не блокер.

### Иконка
- 1024×1024 без альфа-канала, без скруглений (Apple сам скруглит).
- В `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — проверь, что все слоты заполнены.

### Описание / keywords
- Description — на русском (если запускаемся в РФ store) и/или английском.
- Subtitle — до 30 символов, кратко: «Уход за кожей с AI-ассистентом».
- Keywords — до 100 символов, разделённые запятыми. Пример: `кожа,уход,скинкер,SPF,ниацинамид,анализ,селфи,дерматолог,ритуал,Лина`.

### Age Rating
- На опросе указать: «Frequent/Intense Medical/Treatment Information» = **None** (мы не диагностируем).
- «Unrestricted Web Access» = No (URL launcher только на доверенные легал-страницы).
- Финально получится **12+** (типично для health-adjacent без NSFW).

### Category
- Primary: **Health & Fitness**
- Secondary: **Lifestyle**

### Localization
- Минимум одна локаль (Russian) — UI уже на русском. Добавить English только если планируете релиз вне РФ.

---

## 5. Submission

### Reviewer Notes (App Review Information)
Скопируй и заполни:

```
Account login:
  Phone: +7 000 000 0000
  OTP code: 1111
  (This is a reserved demo phone that bypasses the SMS gateway — no
  real SMS is sent. The code is hardcoded for App Review only.)

Notes:
  - Authentication: phone OTP only. No third-party SSO is offered,
    so Sign in with Apple (Guideline 4.8) is not applicable.
  - Лина (Lina) is an AI assistant, not a medical professional. The
    in-app banner and medical disclaimer screen explicitly state this.
  - Skin analysis is computed server-side and is for informational
    purposes only; the app does not claim to diagnose, treat, or cure.
  - Account deletion: Profile → "Удалить аккаунт" wipes all user
    data (scans, chats, profile, custom shelf).
  - Phone uploads selfie photos for skin analysis. Photos are stored
    only on our server and never shared with other users.
```

### Demo Account
- Не нужен (есть moderator phone выше).

### Encryption export compliance
- Включено в Info.plist (`ITSAppUsesNonExemptEncryption=false`). В App Store Connect → Version → Encryption: «No / Standard encryption only».

### TestFlight
- Прокатить через **external TestFlight** хотя бы с 1-2 тестерами за 2-3 дня до submit.
- Это снижает риск отказа на стабильности.

---

## 6. Перед submit — финальный smoke-test

- [ ] Установить через TestFlight на чистый iPhone (не тот, на котором разрабатывал).
- [ ] Логин с moderator-телефоном — пройти от splash до home.
- [ ] Сделать скан, увидеть карту улучшений с точками на лице.
- [ ] Открыть зону, прочитать рекомендации Лины.
- [ ] Свернуть и открыть приложение — состояние сохранилось.
- [ ] Удалить аккаунт через Профиль, логин снова → онбординг с нуля.
- [ ] Отозвать разрешение камеры в Настройках iOS → войти в сканер → должен показаться полноэкранный «Открыть настройки».
- [ ] Отозвать notifications → попробовать включить напоминания в Профиле → должен открыться settings screen.
- [ ] Проверить, что в Sentry/Crashlytics нет PII (телефон, имя) в недавних событиях.

Когда всё прошло — **Submit for Review**. Обычно ответ за 24-48ч.
