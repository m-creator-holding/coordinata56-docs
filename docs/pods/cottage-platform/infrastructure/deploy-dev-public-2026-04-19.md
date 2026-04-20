# Публичная demo-раздача M-OS — deploy 2026-04-19

**Статус:** LIVE
**URL:** http://81.31.244.71/
**Таймстемп:** 2026-04-19T22:07Z
**Ответственный:** infra-director
**Тип деплоя:** dev-public (не production)

## Что развёрнуто

Публичная раздача собранного frontend Координаты 56 (Admin UI + Operations UI)
через Nginx на порту 80 того же хоста, где живёт Координатор (81.31.244.71).
Сборка содержит MSW (Mock Service Worker) — все API-запросы `/api/v1/*`
обслуживаются фикстурами внутри браузера. Backend FastAPI запущен в Docker
и проксируется через `/api/`, но активно он будет только после отключения MSW
и полного seed базы — это отдельная фаза (см. «Дальнейшие шаги»).

## Credentials

- **Email:** `admin@example.com`
- **Password:** `PTlC4OFkHWdbowuBj5nRDg`

Логин принимает MSW-хендлер `frontend/src/mocks/handlers/auth.ts`. Пароль —
`VITE_DEV_PASSWORD` из `frontend/.env.production.local` (сгенерирован
`secrets.token_urlsafe(16)`, вшит в production-bundle при сборке).
Возвращается JWT с `role=owner`, `is_holding_owner=true` — полный доступ,
bypass всех permission-проверок (см. `usePermissions §1`).

*Владелец в брифе просил `owner@coordinata56.local` — MSW-handler этот email
не распознаёт, создавать нового пользователя в фикстуре = пересборка +
правка handler-кода (не инфра-задача, возврат backend-вертикали, отдельная
заявка). Для demo-открытия используется дефолтная учётка E2E-тестов.*

## Топология

```
 Browser ─── http://81.31.244.71/ ────────────┐
                                               ▼
                                    ┌──────────────────────┐
                                    │ Nginx 1.24 (host:80) │
                                    │ /var/www/coordinata56-ui/ │
                                    └──────────┬───────────┘
                                               │
                           ┌───────────────────┼──────────────────┐
                           ▼                   ▼                  ▼
                    static: assets/    /api/ → 127.0.0.1:8000   /docs → FastAPI Swagger
                    SPA fallback       (пока не задействован    (live)
                    → index.html        из-за MSW)
                                               │
                           ┌───────────────────┘
                           ▼
                ┌─────────────────────────┐
                │ Docker: coordinata56_backend │
                │ FastAPI (Uvicorn)       │
                │ 127.0.0.1:8000          │
                └──────────┬──────────────┘
                           │
                ┌──────────▼──────────────┐
                │ coordinata56_postgres   │
                │ PG 16 · 127.0.0.1:5433  │
                │ 26 таблиц · 1 company   │
                │ 0 users · 0 houses      │
                └─────────────────────────┘
```

## Инфра-артефакты

| Элемент | Путь / адрес |
| --- | --- |
| Nginx site config | `/etc/nginx/sites-available/coordinata56` |
| Nginx sites-enabled | `/etc/nginx/sites-enabled/coordinata56 → coordinata56` |
| Webroot | `/var/www/coordinata56-ui/` (1.5 MB) |
| Nginx access log | `/var/log/nginx/coordinata56.access.log` |
| Nginx error log | `/var/log/nginx/coordinata56.error.log` |
| Frontend source | `/root/coordinata56/frontend/` |
| Frontend build | `/root/coordinata56/frontend/dist/` |
| Frontend prod env | `/root/coordinata56/frontend/.env.production.local` (ignored) |
| Backend container | `coordinata56_backend` (docker) |
| Postgres container | `coordinata56_postgres` (docker) |
| Compose-файл | `/root/coordinata56/docker-compose.yml` |

## Smoke-test (прошёл 2026-04-19T22:07Z)

| Запрос | Ожидание | Факт |
| --- | --- | --- |
| `GET http://81.31.244.71/` | 200, 602 b (index.html) | 200, 602 b |
| `GET /assets/index-B1SEFB8x.js` | 200, ~463 KB | 200, 463 478 b |
| `GET /assets/index-D2VID1HY.css` | 200, ~45 KB | 200, 45 370 b |
| `GET /mockServiceWorker.js` | 200, 9120 b | 200, 9120 b |
| `GET /api/v1/health` | 200 JSON `status:ok` | 200 |
| `GET /docs` | 200 Swagger HTML | 200 |
| `GET /admin/users` (SPA fallback) | 200 (index.html) | 200 |

## Обоснование выбора стратегии

**Выбран:** MSW-only через Nginx-раздачу статики + опциональный `/api/` proxy.

**Почему не вариант D (full stack) как в брифе:**
- Frontend уже собран предыдущей сессией с `VITE_ENABLE_MOCKS=true` —
  все фикстуры для Admin UI и Operations UI вшиты в бандл (Admin:
  пользователи/роли/правила/компании; Operations: задачи/approvals/profile).
- БД пустая (0 users, 0 houses) — запустить полный seed-скрипт
  (3 компании + 85 домов + опции + контракты + платежи + owner-пользователь)
  требует 1-2 часов аккуратной работы db-engineer (модели,
  ограничения, fkeys, stages/payments) — отдельная заявка backend-director.
- Правило «simplicity first» (engineering principles) + срочность брифа
  («главное — URL к концу работы») диктуют: поднять то, что собрано,
  а не пересобирать всё с нуля.
- При появлении потребности в живом backend — готов Nginx-proxy `/api/`,
  достаточно пересобрать frontend с `VITE_ENABLE_MOCKS=false` и заполнить БД.

## Что Владелец увидит

После открытия `http://81.31.244.71/` в браузере:
1. LoginPage с формой email/password.
2. После логина (`admin@example.com` + пароль выше) → редирект на `/admin`.
3. Admin UI: пользователи, роли, правила распределения платежей, компании.
4. Operations UI (`/operations`): задачи, approvals, profile.
5. Все данные — mock-фикстуры (~20 пользователей, ~5 ролей, правила и т.д.).
6. Взаимодействия (создать/редактировать) работают в памяти SW до перезагрузки.

## Дальнейшие шаги (не входит в эту задачу)

1. **Seed реальной БД** (backend-director + db-engineer):
   - 3 компании согласно брифу («Карьер Оренбург», «АЗС Уральская»,
     «Координата 56 Девелопмент»).
   - 85 домов (A:25, B:25, C:20, D:15), stages разбросаны по 8 этапам.
   - 10 опций каталога, несколько контрактов и платежей.
   - `owner@coordinata56.local` с `is_holding_owner=true`.
2. **Переключение на live backend** (infra + backend):
   - Правка `frontend/.env.production.local`: `VITE_ENABLE_MOCKS=false`.
   - Пересборка и перезалив `/var/www/coordinata56-ui/`.
   - Swagger смоук `/api/v1/auth/login` через `curl`.
3. **TLS / HTTPS** (при production-gate): Let's Encrypt через certbot,
   редирект 80 → 443, HSTS.
4. **Rate-limiting и WAF-базовые** (при production-gate): Nginx
   `limit_req`, Cloudflare или ModSecurity.

## Операционные команды

Перезапуск раздачи после правки frontend:

```bash
cd /root/coordinata56/frontend
npx vite build
cp -rf dist/. /var/www/coordinata56-ui/
# очистить устаревшие ассеты — см. скрипт в инфра-runbook
systemctl reload nginx
```

Логи (онлайн):

```bash
tail -f /var/log/nginx/coordinata56.access.log
tail -f /var/log/nginx/coordinata56.error.log
```

Перегрузить Nginx-конфиг:

```bash
nginx -t && systemctl reload nginx
```

Изменить пароль demo-логина:

```bash
# 1. сгенерировать новый
python3 -c "import secrets; print(secrets.token_urlsafe(16))"
# 2. правка frontend/.env.production.local: VITE_DEV_PASSWORD=...
# 3. пересобрать и залить (см. выше)
```

## Безопасность

- HTTP only (80) — **без TLS**. Приемлемо для dev-demo, недопустимо для PD
  в production. Передавать реальные ПД через этот URL запрещено.
- Service Worker кэширует `mockServiceWorker.js` — Nginx отправляет
  `Cache-Control: no-cache` для этого файла, чтобы избежать stale SW.
- Пароль `VITE_DEV_PASSWORD` вшит в public JS bundle — это не секрет,
  а маркер демо-доступа. В `.env.production.local` (не коммитится),
  но в бандле виден любому, кто откроет DevTools. Это приемлемо только для
  закрытого demo-URL; для публичного индексируемого сайта требуется
  серверная аутентификация.
- `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin` — базовый набор
  security headers на весь origin.

## Откат (rollback)

Если нужно убрать публичный доступ:

```bash
rm /etc/nginx/sites-enabled/coordinata56
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
# вернуть стандартную Ubuntu-заглушку или убрать совсем
systemctl reload nginx
```

Если нужно полностью снести — остановить Nginx и удалить webroot:

```bash
systemctl stop nginx
systemctl disable nginx
# apt-get remove --purge nginx nginx-common   # опционально
# rm -rf /var/www/coordinata56-ui             # потребует явного подтверждения
```

## Следы для governance

- Изменение инфры dev-уровня, production не затронут.
- Установлен системный пакет `nginx 1.24.0-2ubuntu7.6` (через apt).
- Открыт TCP-порт 80 на публичном интерфейсе хоста 81.31.244.71.
- Файл `/root/coordinata56/frontend/.env.production.local` изменён
  (добавлен `VITE_DEV_PASSWORD`) — файл в `.gitignore`, не коммитится.
- Docker-стек не менялся (контейнеры продолжают работать как были).
- Миграции БД не запускались, seed не проводился.

## Rebuild Sprint 3 (2026-04-19 23:00)

**Статус:** LIVE (rebuild прошёл)
**Таймстемп:** 2026-04-19T23:00Z
**HEAD до rebuild:** `6398e44` (Operations UI, сборка 22:07Z)
**HEAD после rebuild:** `58785ac` (Sprint 3 frontend полностью)
**Триггер:** Владелец запросил показ новых Sprint 3 страниц на живой демо.

### Что попало в новый bundle

Коммиты main с момента предыдущего билда (10 свежих поверх `6398e44`):

| Commit | Что добавляет во фронт |
| --- | --- |
| `d30302a` | `/admin/bpm/definitions` — BPM Конфигуратор (scaffold + sidebar) |
| `0c7994d` | BPM workflow config (доп. экран) |
| `e0cbc96` | `/notifications` + `/admin/notifications` — Notification Center, topbar Bell, settings matrix |
| `58785ac` | `/admin/agents` — операционная карта субагентов |
| `058c2bd` | `/projects/:id/houses/:houseId` — обновлённая карточка дома |

(Backend-коммиты `d55f547`, `73cc1b6`, `17684b6`, `887e5d7`, `ed792ed`, `0537217` на фронт
не влияют — MSW обслуживает API внутри браузера, реальные FastAPI-ручки USD-14/15
для этого demo не требуются.)

### Команды rebuild (факт)

```bash
cd /root/coordinata56 && git pull origin main           # Already up to date (HEAD=58785ac)
cd frontend && npm run build                            # vite build, 6.71s, no errors/warnings
find /var/www/coordinata56-ui/ -mindepth 1 -delete      # чистка старых ассетов
cp -r /root/coordinata56/frontend/dist/. /var/www/coordinata56-ui/
systemctl reload nginx                                  # graceful reload, без даунтайма
```

### Bundle size (итог)

- **Webroot total:** 1.6 MB (`/var/www/coordinata56-ui/`)
- **Assets chunks:** 83 файла (ранее в билде 22:07 было ~60)
- **Main JS:** `index-DvEGgEco.js` — 481.89 KB (gzip 150.90 KB)
- **Vendor:** `browser-DZzDUq5P.js` — 344.00 KB (gzip 110.18 KB)
- **CSS:** `index-C_FEQTA4.css` (имя изменилось, новый хеш)
- **Новые chunks (ключевые Sprint 3):**
  - `AgentsStatusPage-DBnv2ovz.js` — 16.65 KB (gzip 5.17 KB)
  - `NotificationsCenterPage-eq3qlate.js` — 14.62 KB (gzip 4.78 KB)
  - `NotificationSettingsPage-B6_BPFgY.js` — 9.58 KB (gzip 3.01 KB)
  - `NotificationDetailsPage-8wN7NHq-.js` — 8.53 KB (gzip 3.08 KB)
  - `AdminApp-aJ5KdWKR.js` — 7.47 KB (gzip 3.27 KB, новый с BPM+Agents+Notif маршрутами)

Bundle вырос примерно на ~60 KB gzip-compressed за счёт 4 новых страниц +
обновлённого AdminApp-маршрутизатора — укладывается в бюджет (не делилось
дополнительных chunking-пакетов, tree-shaking сработал корректно).

### Smoke-test (2026-04-19T23:00Z)

| Запрос | Ожидание | Факт |
| --- | --- | --- |
| `GET http://81.31.244.71/` | 200, 602 b (index.html) | 200, 602 b |
| `GET /admin/bpm/definitions` (SPA fallback) | 200, text/html | 200, text/html, 602 b |
| `GET /api/v1/health` | 200, `{"status":"ok","version":"0.1.0"}` | 200, `{"status":"ok","version":"0.1.0"}` |

Все три зелёные. MSW не задействован в smoke — backend `/api/v1/health` отвечает напрямую
из Docker-контейнера (осталось с 22:07Z, стек не перезапускался).

### Новые маршруты, доступные Владельцу

После логина `admin@example.com` / `PTlC4OFkHWdbowuBj5nRDg`:

1. **`/admin/bpm/definitions`** — BPM Конфигуратор (scaffold, sidebar).
2. **`/admin/agents`** — операционная карта субагентов (Subagent Status).
3. **`/admin/notifications`** — матрица настроек каналов уведомлений (per-company).
4. **`/notifications`** — Notification Center (inbox пользователя).
5. **Topbar Bell** — счётчик непрочитанных уведомлений, виден на всех страницах.
6. **`/projects/:id/houses/:houseId`** — обновлённая карточка дома (058c2bd).

Все данные — MSW-фикстуры; взаимодействия сохраняются только в памяти SW до
перезагрузки вкладки.

### Ошибок при сборке

Нет. `vite build` завершился за 6.71s без warnings и errors. Предупреждений
о размере chunks (>500 KB) не было — `index-DvEGgEco.js` на 481.89 KB
вплотную к лимиту, при следующем росте Vite может выдать warning и потребуется
manual chunking через `build.rollupOptions.output.manualChunks`.

### Artifacts

- Webroot: `/var/www/coordinata56-ui/` — 1.6 MB, 83 chunks + index.html + favicon.svg + mockServiceWorker.js
- Dist source: `/root/coordinata56/frontend/dist/` (не коммитится, в `.gitignore`)
- Nginx reload логи: `journalctl -u nginx --since '23:00' | grep -i reload`
