# Бриф для frontend-head: батч «M-OS-1.1 FE-skeleton»

- **Версия:** 1.0
- **Дата:** 2026-04-17
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), поднят из dormant 2026-04-16, статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт», v1.6 — Директор не вызывает Head напрямую)
- **Батч-ID:** M-OS-1.1-fe-skeleton
- **Под-фаза:** M-OS-1.1 Foundation (pod: cottage-platform)
- **Статус брифа:** утверждено направлением, ждёт одобрения Координатора для передачи Head

---

## 0. Основание и источники

Этот батч — первая фронтенд-работа в M-OS. Он готовит каркас, против которого
дальше будут писаться все admin-UI разделы под-фаз 1.1 → 1.3 и PWA прораба (1.3).

Источники, по которым построен бриф — читать Head'у обязательно до распределения задач:

1. `docs/pods/cottage-platform/m-os-1-plan.md` v1.3 — план фазы M-OS-1, раздел M-OS-1.1 Foundation
2. `docs/pods/cottage-platform/m-os-1-frontend-plan.md` v1.0 — фронтенд-план фазы, §§2.3, 2.4, 2.5, 4.1, 4.3, 4.4
3. `docs/reviews/external-audit-2026-04-17-frontend.md` v1.0 — ответ Директора внешнему аудиту, §2 «Последствия Варианта A» (именно этот раздел — операционный скелет батча)
4. `docs/adr/0002-tech-stack.md` — утверждённый стек (React 18 + TS + Vite + Tailwind + shadcn/ui); **не меняем**
5. `docs/adr/0011-foundation-multi-company-rbac-audit.md` — multi-company модель, `Company`, `UserCompanyRole`, `is_holding_owner`, RBAC «роль + объект + действие». Фронт обязан корректно работать с этой моделью на уровне AuthProvider/guards
6. `docs/CONSTITUTION.md` + `docs/agents/CODE_OF_LAWS.md` ст. 45а — запрет живых внешних интеграций (для нас это значит: **только MSW/моки**, ни одного реального вызова стороннего API)
7. `CLAUDE.md` (корневой) — секции «Процесс», «Код», «Git», а также правило msg 1099 «No live external integrations»

Статус других документов:
- `docs/agents/departments/frontend.md` сейчас v0.1 «СКЕЛЕТ dormant». Перевод в v1.0 —
  **отдельная задача** фронтенд-директора в Governance-комиссию, параллельно
  этому батчу (см. §4.5 frontend-plan). Head к ней не привлекается, но обязан
  знать: после одобрения v1.0 правила этого регламента становятся обязательными
  для всех задач отдела.

## 1. Бизнес-цель батча

За 5–7 рабочих дней получить рабочий каркас фронтенда, из которого в
последующих батчах M-OS-1.1 можно без архитектурных правок вырастить все
6 admin-разделов (Companies, Users, Roles, Company Settings, Integration
Registry, System Config), а в M-OS-1.3 — PWA прораба.

Ни одной бизнес-функции в этом батче не закрывается. Это целенаправленный
инвестиционный вкус — затраченное время окупается скоростью 9–10 недель
последующей admin-работы + 5.5 недель PWA.

## 2. Скоуп батча — семь пунктов

Скоуп **закрытый**. Любое «заодно и X» запрещено и эскалируется через Head
Директору. Основание — Риск 4 из m-os-1-plan.md v1.3.

### Пункт 1. Разделение роутинга на `/admin/*` и `/field/*` с lazy-chunks

**Что сделать.** Отрефакторить `frontend/src/routes.tsx`: вместо плоских
маршрутов из фазы 2–3 сделать двухтрековую структуру.

- `/admin/*` — грузит `AdminApp` через `React.lazy(() => import('./admin/AdminApp'))`.
- `/field/*` — грузит `FieldApp` через `React.lazy(() => import('./field/FieldApp'))`.
- Корень `/` — редиректит по роли пользователя (см. Пункт 3).
- Общий корневой `<Suspense fallback={<AppLoader />}>` вокруг обоих треков.
- Текущие страницы фазы 2–3 (Dashboard/Houses/Finance/Schedule) **переезжают
  внутрь** `/admin/*` как временные, их никто в этом батче не переделывает.
  Они остаются работать — не роняем то, что было.

**Acceptance.**
- `npm run build` проходит.
- В prod-бандле `vite-bundle-visualizer` (или `rollup-plugin-visualizer`)
  показывает два независимых chunk'а: `admin-*.js` и `field-*.js`, они не
  шарят между собой кода из `admin/` и `field/`.
- При запросе `/field/login` код из `admin/` в сетевой панели не скачивается.
- Существующие страницы Dashboard/Houses/Finance/Schedule по пути
  `/admin/houses`, `/admin/finance`, `/admin/schedule` продолжают открываться
  без регрессов.

**Файлы (ориентир, Head уточняет конкретный список в задаче dev'у):**
- `frontend/src/routes.tsx`
- `frontend/src/admin/AdminApp.tsx` (новый)
- `frontend/src/field/FieldApp.tsx` (новый)
- `frontend/src/app/AppLoader.tsx` (новый, общий)

### Пункт 2. AdminLayout и FieldLayout

**Что сделать.** Два раздельных лэйаута, оба на shadcn/ui + Tailwind,
без своей дизайн-системы.

**AdminLayout.**
- Левая вертикальная навигация: логотип M-OS, список разделов (в этом
  батче — три пункта-скелета: Companies, Users, Roles), collapse-кнопка.
- Верхняя шапка: переключатель текущей компании (см. Пункт 3 — берётся
  из `useCurrentCompany`), имя пользователя справа, dropdown с
  выходом.
- Content-area — `<Outlet />` от react-router.
- Desktop-first, min-width 1024px (админы работают за ПК).

**FieldLayout.**
- Нижняя навигация с крупными кнопками (Tasks / Approvals / Profile) —
  в этом батче три пустых-плейсхолдер-страницы.
- Sticky-хедер: имя пользователя, индикатор сети (online/offline —
  базовая реализация через `navigator.onLine`, без Workbox-интеграции —
  она позже).
- Mobile-first, viewport `width=device-width, initial-scale=1, maximum-scale=1`.
- Крупные кнопки (минимум 44×44 px, Apple HIG).

**Acceptance.**
- Оба лэйаута рендерятся с пустыми страницами-плейсхолдерами внутри.
- В AdminLayout переключение компании через `useCurrentCompany().set(id)`
  меняет отображаемое имя компании в шапке.
- Playwright-smoke: при визите `/admin/companies` видна левая навигация,
  при визите `/field/tasks` — нижняя навигация.

**Файлы:**
- `frontend/src/admin/layout/AdminLayout.tsx`
- `frontend/src/admin/layout/AdminSidebar.tsx`
- `frontend/src/admin/layout/AdminTopbar.tsx`
- `frontend/src/field/layout/FieldLayout.tsx`
- `frontend/src/field/layout/FieldBottomNav.tsx`
- `frontend/src/field/layout/FieldHeader.tsx`

### Пункт 3. Auth-каркас под multi-company (ADR 0011)

**Что сделать.** Полный авторизационный скелет без настоящего логина —
только структура, которую в следующих батчах подключим к backend.

- `AuthProvider` — React Context, хранит `accessToken`, `user`, `companies`,
  `currentCompanyId`, `isHoldingOwner`. Persist в `localStorage` (только
  токен + `currentCompanyId`, ничего больше, без PII).
- `useCurrentUser()` — возвращает объект пользователя из JWT payload.
  В JWT ждём поля: `sub` (user_id), `email`, `full_name`, `company_ids`
  (массив int), `is_holding_owner` (bool), `exp`. Decoding — через
  `jwt-decode` (добавить в dependencies, это 1.8KB gzip; это единственная
  новая runtime-зависимость, которую мы ставим в этом батче, и она
  согласована с ADR 0002 — он не перечисляет jwt-decode явно, но и не
  запрещает точечные утилиты).
- `useCurrentCompany()` — возвращает `{ id, setId }`, значение берётся
  из Zustand-store (persist в localStorage), начальное значение — первая
  компания из `company_ids`. Если `is_holding_owner=true` — возможно
  значение `null`, означающее «bypass company filter» (ст. 1.3 ADR 0011).
- `<RequireAuth>` — guard-обёртка для защищённых маршрутов. Нет
  accessToken → редирект на `/admin/login` (или `/field/login` в
  зависимости от трека).
- `<RequireRole roles={['owner','accountant']}>` — guard по RBAC. В этом
  батче роли хардкодим **только как тип в TS**, реальная проверка —
  в следующих батчах, когда backend отдаст permission-матрицу. В этом
  батче компонент уже должен быть, чтобы в 1.1-batch-2 (Companies CRUD)
  его уже использовать.
- Mock-логин: страница `/admin/login` с формой (email + password, RHF +
  zod), при submit — вызов MSW-handler'а `POST /api/v1/auth/login`,
  возвращает фиктивный JWT. Это не настоящий логин, это тестовый
  маршрут, чтобы E2E-smoke прошли.

**Acceptance.**
- Переход на `/admin/companies` без токена — редирект на `/admin/login`.
- После mock-логина в localStorage появляется `access_token` и
  `current_company_id`.
- `useCurrentUser()` в dev-tools возвращает декодированные поля JWT.
- Переключение компании в топбаре обновляет все подписанные на
  `useCurrentCompany()` компоненты.
- `<RequireRole>` компилируется и принимает массив строк; runtime-логика —
  заглушка `return children` (вернётся в 1.1-batch-2).

**Файлы:**
- `frontend/src/shared/auth/AuthProvider.tsx`
- `frontend/src/shared/auth/useCurrentUser.ts`
- `frontend/src/shared/auth/useCurrentCompany.ts`
- `frontend/src/shared/auth/RequireAuth.tsx`
- `frontend/src/shared/auth/RequireRole.tsx`
- `frontend/src/shared/auth/jwt.ts` (decode utility)
- `frontend/src/admin/pages/LoginPage.tsx`
- `frontend/src/field/pages/LoginPage.tsx`

### Пункт 4. vite-plugin-pwa с пустым manifest

**Что сделать.**
- Установить `vite-plugin-pwa` (dev-dependency, ~80KB, но только в dev;
  runtime service worker — отдельный bundle <10KB).
- В `vite.config.ts` подключить с минимальной конфигурацией:
  - `registerType: 'autoUpdate'`
  - `manifest`: name «M-OS», short_name «M-OS», theme_color `#0f172a`,
    `display: standalone`, `start_url: /field/` (PWA нацелено на прораба).
  - Пустой массив иконок — реальные подтянем в M-OS-1.3. Оставить
    TODO-коммент с ссылкой на фазу.
  - Workbox runtime caching strategy — пока только дефолтная, без
    кастомных стратегий. Кастомные стратегии (app shell, task list cache,
    pending mutations queue) — это уже M-OS-1.3.

**Acceptance.**
- `npm run build` генерирует `dist/manifest.webmanifest` и
  `dist/registerSW.js`.
- В Chrome DevTools → Application → Manifest видно заполненные поля.
- Service worker регистрируется (в dev-режиме через `devOptions.enabled:
  true`) и переходит в `activated`.
- Существующая функциональность не ломается — при отсутствии SW
  (в старых браузерах) приложение работает как обычное SPA.

**Файлы:**
- `frontend/vite.config.ts` (правка)
- `frontend/package.json` (добавить `vite-plugin-pwa` в devDependencies)

### Пункт 5. MSW (Mock Service Worker)

**Критический пункт батча.** Без MSW следующие батчи 1.1 остановятся
в ожидании backend-эндпоинтов. Риск 3 плана закрывается именно здесь.

**Что сделать.**
- Установить `msw` (latest 2.x, работает с Service Workers) и
  `@mswjs/data` (для моделирования mock-БД — опционально, можно обойтись
  статическими массивами, решает frontend-head).
- Настроить worker в `frontend/src/mocks/browser.ts` + handlers в
  `frontend/src/mocks/handlers/`.
- В dev-режиме (`import.meta.env.DEV`) автозапуск worker'а в `main.tsx`.
- В production — **не запускать** MSW, он нужен только локально и в
  CI-тестах. Финальная prod-сборка должна быть чиста от моков.
- Handler'ы в этом батче — только под авторизационный flow (Пункт 3):
  - `POST /api/v1/auth/login` — возвращает JWT с фиктивным user'ом,
    принадлежащим к двум компаниям (для демонстрации переключателя
    компании).
  - `GET /api/v1/auth/me` — возвращает того же пользователя.
  - `GET /api/v1/companies` — возвращает статический список из двух
    компаний (под моковый переключатель).
- Зерновые fixtures — в `frontend/src/mocks/fixtures/`. Никаких
  `faker`-генераций в этом батче (в следующих — по усмотрению).

**Зависимость от backend-director.** До старта реализации Head обязан
получить от Координатора подтверждение: backend-director согласовал
**zero-version OpenAPI** для авторизационных эндпоинтов (`/auth/login`,
`/auth/me`, `/companies` в объёме, нужном для mock-логина). Контракт без
реализации — достаточно. Если такого подтверждения нет — Head не
запускает Worker'а, эскалирует Координатору блокер.

**Правило жизни MSW-handler'а** (из §2 ответа аудитору): handler живёт
**максимум 2 недели** без эталонного backend-endpoint'а. После 2 недель
handler удаляется, задача ставится на hold. Это документируется в
соответствующей задаче Head'ом.

**Acceptance.**
- В dev-режиме в консоли при старте dev-server'а виден лог
  `[MSW] Mocking enabled`.
- MSW не включается в production-бандл (проверяется
  `rollup-plugin-visualizer` или grep `dist/*.js` на отсутствие
  `msw`).
- Smoke-тест: `vitest` юнит-тест, который через `fetch('/api/v1/auth/me')`
  получает ответ от handler'а.
- Playwright smoke прошёл mock-login → попадает на `/admin/companies`.

**Файлы:**
- `frontend/src/mocks/browser.ts`
- `frontend/src/mocks/handlers/auth.ts`
- `frontend/src/mocks/handlers/companies.ts`
- `frontend/src/mocks/handlers/index.ts`
- `frontend/src/mocks/fixtures/users.ts`
- `frontend/src/mocks/fixtures/companies.ts`
- `frontend/src/main.tsx` (правка — автозапуск MSW в dev)
- `frontend/public/mockServiceWorker.js` (генерируется `msw init`)

### Пункт 6. Skeleton-страницы Companies, Users, Roles

**Что сделать.** Три страницы в `/admin/*`, каждая — таблица с mock-данными
из MSW. Никакой реальной бизнес-логики, никаких форм создания-редактирования,
никаких детальных карточек. Цель — убедиться, что «маршрут → лэйаут →
guard → TanStack Query → MSW → таблица» — работает целиком.

**Companies (`/admin/companies`).**
- `useQuery(['companies'], () => api.companies.list())` — TanStack Query,
  axios под капотом (`axios` уже в стеке).
- Таблица из shadcn/ui (`@radix-ui/react-scroll-area`, shadcn `Table`):
  колонки ИД, ИНН, краткое название, тип, активна-ли.
- Fallback'ы: `<TableSkeleton>` на время загрузки, `<EmptyState>` для
  пустого списка, `<ErrorState>` для ошибок.
- Поиска, пагинации и фильтров — нет в этом батче. Они в 1.1-batch-2.

**Users (`/admin/users`).** Аналогично: колонки ИД, email, имя, статус.
MSW-handler `GET /api/v1/users` пока возвращает пустой envelope `{items: [],
total: 0, offset: 0, limit: 25}` — это правильный формат по ADR 0006,
корректный Empty-State демонстрируется. Для иллюстрации можно вернуть
2–3 статические записи.

**Roles (`/admin/roles`).** Колонки ИД, код роли, название, scope (global/
company). 2–3 статические записи из fixtures.

**Acceptance.**
- Все три страницы открываются, видна таблица (или Empty-State).
- Playwright smoke: для каждой страницы — скриншот + проверка, что
  отрендерилась либо таблица, либо EmptyState.
- Vitest: smoke-юнит-тест для каждого page-компонента, который проверяет,
  что компонент рендерится без падения.

**Файлы:**
- `frontend/src/admin/pages/CompaniesPage.tsx`
- `frontend/src/admin/pages/UsersPage.tsx`
- `frontend/src/admin/pages/RolesPage.tsx`
- `frontend/src/shared/ui/TableSkeleton.tsx` (если ещё нет)
- `frontend/src/shared/ui/EmptyState.tsx` (если ещё нет)
- `frontend/src/shared/ui/ErrorState.tsx` (если ещё нет)
- `frontend/src/shared/api/client.ts` (axios instance с interceptor'ом
  подставляющим JWT из AuthProvider)
- `frontend/src/shared/api/companies.ts`
- `frontend/src/shared/api/users.ts`
- `frontend/src/shared/api/roles.ts`

### Пункт 7. openapi-typescript в CI

**Что сделать.**
- Установить `openapi-typescript` (dev-dependency).
- Добавить скрипт `npm run codegen:api` в `package.json`:
  `openapi-typescript <path-to-openapi.json> --output src/shared/api/schema.ts`.
- Путь к OpenAPI — через env-переменную (в dev — локальный файл
  `openapi/zero-version.json` в корне репо; в CI — указанный URL
  backend'а).
- В этом батче реального `schema.ts` не будет — backend ещё не выкатил
  стабильную OpenAPI. Вместо него — ручной `schema.ts` с пятью типами
  (`User`, `Company`, `Role`, `PaginatedResponse<T>`, `ApiError`),
  который заменится сгенерированным в batch-2.
- В `tsconfig` пути импорта через `@/shared/api/schema`.
- Документировать в `docs/pods/cottage-platform/m-os-1-frontend-plan.md`
  §2.5 (обновление): «типы — из `schema.ts`, сгенерированные из OpenAPI;
  ручные interface-описания запрещены». Это правка плана v1.0 → v1.1 —
  оформляется Директором параллельно и не является работой Head'а.
- CI-интеграция (`.github/workflows/frontend-ci.yml` или аналог — сейчас
  CI настраивает infra-director, но у нас CI уже был в Phase 3):
  - шаг `npm run codegen:api` (в этом батче — просто no-op, т.к.
    `schema.ts` ручной)
  - шаг `npm run typecheck`
  - шаг `npm run lint`
  - шаг `npm run build`
  - **размер bundle**: проверка через `rollup-plugin-visualizer` или
    простой `du -sh dist/assets/*.js`, **суммарный лимит — 500KB
    gzipped**. Admin-chunk — до 300KB gzipped, field-chunk — до
    200KB gzipped. При превышении — CI падает.

**Acceptance.**
- Скрипт `npm run codegen:api` прописан в `package.json`, при наличии
  файла `openapi/zero-version.json` работает (в этом батче можно
  положить минимальный валидный OpenAPI 3.1 с одним endpoint'ом для
  smoke-проверки).
- `schema.ts` импортируется и используется во всех `shared/api/*.ts`
  через `schema['Company']` и т.п. (или через `components['schemas']
  ['Company']` в зависимости от версии openapi-typescript).
- CI-пайплайн (если уже существует) — собирает фронт и валит сборку
  при превышении bundle-лимита.

**Файлы:**
- `frontend/package.json` (scripts)
- `frontend/src/shared/api/schema.ts` (ручной временный)
- `frontend/openapi/zero-version.json` (минимальный заглушечный OpenAPI,
  если Head не получит от backend'а)
- `.github/workflows/frontend-ci.yml` или равное (Head согласует с
  infra-director через Координатора, если такого workflow ещё нет)

## 3. Что НЕ входит в этот батч

Прямой перечень — чтобы не расплыться. Всё перечисленное — следующие батчи
1.1 и поздние под-фазы.

- Реальные формы создания/редактирования Company/User/Role
- Реальная аутентификация против backend (это 1.1-batch-2)
- Настоящая Permission Matrix с серверной проверкой прав
- Company Settings, Integration Registry, System Config (1.1-batch-3)
- BPM Constructor, Form Builder, Report Builder (1.2, 1.3)
- Иконки PWA и кастомные Workbox-стратегии (1.3)
- Offline-очередь IndexedDB и background sync (1.3, PWA прораба)
- Telegram deep-link через JWT (1.3, PWA прораба)
- i18n (M-OS-5+, см. frontend-plan §4.3)
- WCAG-AA audit (M-OS-2)

## 4. Оценка и состав исполнителей

**Исполнитель:** один `frontend-dev` (первый воркер направления, активируется
одновременно с этим батчем).

**Оценка:** 5–7 рабочих дней. В календарном выражении — 1 неделя при full-time
загрузке одного воркера. Если frontend-dev ещё не создан в конфигурации
субагентов — Head эскалирует Координатору до начала работы.

**Разбивка по дням (ориентир для Head'а, он может перепланировать):**

| День | Работа |
|---|---|
| 1 | Пункт 1 (роутинг), Пункт 4 (PWA конфиг) — оба независимы, быстрые |
| 2 | Пункт 2 (AdminLayout + FieldLayout) без auth-интеграции |
| 3 | Пункт 5 (MSW setup + первые handler'ы) |
| 4 | Пункт 3 (AuthProvider, хуки, guards, mock-логин) |
| 5 | Пункт 6 (три skeleton-страницы) + интеграция с AdminLayout |
| 6 | Пункт 7 (openapi-typescript, CI bundle-limit) + smoke-тесты |
| 7 | Буфер: фиксы после self-review, подготовка PR |

**Активация `frontend-dev-2` в этом батче не требуется.** Решение о втором
воркере принимается Координатором в конце M-OS-1.1 (§4.4 frontend-plan).

## 5. Риски и зависимости

| № | Риск / зависимость | Вероятность | Влияние | Митигация |
|---|---|---|---|---|
| R1 | backend-director не согласовал zero-version OpenAPI на auth-эндпоинты до старта | Средняя | Критическое (блокирует Пункт 5) | Head эскалирует Координатору **до** раздачи задачи dev'у. Если OpenAPI нет — ждём; в заглушечный OpenAPI для CI (`openapi/zero-version.json`) Head может положить минимальный валидный пример, но handler'ы MSW пишутся только против согласованного контракта |
| R2 | dev пытается реализовать «настоящий» логин с хешированием паролей и т.д. | Низкая | Среднее (скоуп раздувается) | Head в задаче явно пишет: «logic is mock-only, real auth — next batch». Код-ревью ловит |
| R3 | Bundle-лимит 500KB gzipped оказывается тесным для admin-chunk из-за shadcn/ui-компонентов | Средняя | Среднее | Если админ-chunk превышает 300KB — первая итерация с увеличением до 400KB (с пометкой в CI-config). Эскалация Директору, не самостоятельное увеличение выше 400KB |
| R4 | vite-plugin-pwa конфликтует с нашей текущей конфигурацией Vite 5 / React 18 | Низкая | Низкое | В dev-режиме можно отключить через `devOptions.enabled: false`, если мешает. Проверяется сразу после установки плагина |
| R5 | MSW не запускается в Chrome DevTools из-за особенностей регистрации SW | Низкая | Низкое | Стандартные траблшутинги MSW (корректный `start({ onUnhandledRequest: 'bypass' })`, корректный путь до `mockServiceWorker.js`). Head проверяет в ревью |
| D1 | **backend-director zero-version OpenAPI для auth + companies + users + roles** | — | — | Head через Координатора запрашивает и ждёт. Без этого Пункты 3, 5, 6 не стартуют |
| D2 | `designer` (L4) советует по mobile UX FieldLayout | — | — | **Не в этом батче.** FieldLayout в скоупе — минимальный (нижняя навигация, хедер). Детальная UX-проработка мобильных экранов — в M-OS-1.3, с консультацией designer'а через Координатора |
| D3 | `frontend-dev` как субагент в Claude Code | — | — | Если ещё не создан/не активирован — Head эскалирует Координатору до начала работы |
| D4 | CI-workflow для фронта существует | — | — | Head проверяет `.github/workflows/`. Если нет — согласует с infra-director через Координатора. Минимальный pipeline (typecheck + lint + build + bundle-size) Head готовит сам в рамках Пункта 7, если infra-director занят |

## 6. Definition of Done батча

Батч считается закрытым, когда выполнены **все** восемь пунктов. Частичное
закрытие — не закрытие.

1. **Код.** Все 7 пунктов скоупа реализованы. Файлы на месте, компилируются,
   линтеруются, типизируются (`npm run typecheck`, `npm run lint`, `npm run
   build` — все зелёные).
2. **Тесты.**
   - Vitest unit: минимум 6 smoke-тестов (по одному на каждую skeleton-
     страницу + на AuthProvider + на jwt-decode).
   - Playwright E2E: минимум 3 smoke-сценария:
     - «Unauthenticated user tries /admin/companies → redirected to /admin/login»
     - «Mock-login → /admin/companies → видна таблица»
     - «/field/tasks открывается, видна нижняя навигация»
3. **Bundle size.** Суммарный gzipped admin-chunk + field-chunk ≤ 500KB.
   Отдельно admin-chunk ≤ 300KB, field-chunk ≤ 200KB. Проверяется в CI.
4. **Lazy-loading работает.** При заходе на `/field/login` в Network-панели
   отсутствуют файлы с префиксом `admin-` (и наоборот).
5. **MSW ведёт себя правильно.** В dev — mock-ответы идут; в production-сборке
   (`npm run build && npm run preview` c переменной `NODE_ENV=production`) —
   MSW не стартует, запросы идут на реальный URL (который для этого батча
   не существует — и это ожидаемо).
6. **Документация.**
   - Обновлён `docs/pods/cottage-platform/m-os-1-frontend-plan.md` §2.5 —
     добавлены конкретные пути файлов (этот пункт делает **Директор**,
     не Head, после закрытия батча). Head в своём отчёте дает список
     созданных файлов — Директор переносит в план.
   - Создан раздел «Каркас M-OS-1.1» в `docs/agents/departments/frontend.md`.
     Пункт оформляется как amendment v0.1 → v1.0 (по §4.5 frontend-plan).
     Head **не делает** эту правку сам — она идёт через Governance-
     комиссию заявкой Директора. В отчёте Head'а — только список того,
     что должно быть документировано.
7. **Reviewer-approve до коммита.** Обязательное правило CLAUDE.md. После
   самоpеview Head'а pull request идёт на reviewer'а (L4-advisory через
   Координатора). Coverage отзывов: вся работа dev'а, без «заодно
   докоммитил».
8. **Директор-вердикт.** Финальный approve делает frontend-director
   после reviewer'а. В вердикте — либо «готово к коммиту», либо
   конкретный список доработок (не «мне не нравится» — а «Пункт N
   не соответствует Acceptance, причина ...»).

## 7. Ревью-маршрут

```
frontend-dev (реализует)
   ↓ self-review + локальные тесты
frontend-head (первичное ревью задачи → доработки dev'у → approve)
   ↓ PR
reviewer (L4-advisory, через Координатора)
   ↓
frontend-director (финальный approve-вердикт)
   ↓
Координатор (коммит)
```

Параллелизма нет: reviewer работает на `git diff --staged` по правилу
CLAUDE.md «Reviewer — до `git commit`, не после».

Не пропускать reviewer'а. Не делать `git add -A` — только конкретный
список файлов (правило CLAUDE.md «Git» от 2026-04-15).

## 8. Что Head возвращает Директору на финальное ревью

При передаче результата обратно Директору (через Координатора) Head
обязан приложить:

1. **Список созданных / изменённых файлов** — полный, с абсолютными
   путями. Не скриншоты дерева — именно текстовый список. Директор
   переносит его в `m-os-1-frontend-plan.md` §2.5.
2. **Отчёт о тестах:**
   - Число и список vitest-тестов, все зелёные.
   - Число и список Playwright-сценариев, все зелёные.
   - Скриншоты от Playwright (по одному на сценарий, выгружаются в
     `docs/pods/cottage-platform/evidence/fe-skeleton-m-os-1-1/`).
3. **Отчёт о bundle size:** вывод `du -sh dist/assets/*.js` + вывод
   bundle visualizer (если использовали) — скриншот или текстом.
4. **Лог reviewer'а:** вердикт reviewer'а текстом (что было замечено,
   что исправлено, итоговый approve).
5. **Список отклонений от брифа** — если были. Для каждого отклонения:
   пункт брифа, причина отклонения, кто согласовал (Head? Координатор?
   Директор?). Если отклонений нет — явно написать «отклонений нет».
6. **Список вопросов/предложений на следующий батч (1.1-batch-2):**
   что Head увидел в процессе и что стоит учесть в следующих задачах.
   Это не обязательный пункт, но сильно помогает преемственности.

## 9. Жёсткие ограничения (повторение, чтобы не забыть)

- **ADR 0002 не трогать.** Стек фиксирован. Никакого «давайте попробуем
  Mantine» или «может лучше tRPC». Если Head или dev видят жёсткую
  необходимость — эскалация Директору через Координатора; сам Head
  решений о смене стека не принимает. Единственное добавление новых
  runtime-зависимостей в этом батче: `jwt-decode` и `msw` — оба в
  брифе явно согласованы.
- **Живых внешних интеграций нет** (ст. 45а CODE_OF_LAWS, правило
  CLAUDE.md «No live external integrations»). Всё — через MSW. Никаких
  Supabase, Auth0, Firebase, никаких прямых HTTP к сторонним сервисам.
  Telegram — тоже не в этом батче (он в M-OS-1.3 PWA-прораба).
- **Secrets через env.** Никаких hardcoded токенов/паролей в коде и
  тестах. Fake-пароль в mock-login handler — допустим **только в
  fixtures**, помечен комментарием `// MOCK: not a real password`.
- **Цепочка делегирования.** Head не обращается к designer'у напрямую,
  не обращается к backend-director'у напрямую. Все вопросы — через
  Координатора. Директор (я) — тоже: если Head спрашивает «а что
  backend ответил про OpenAPI?» — Head эскалирует Координатору, я
  отвечаю через Координатора.
- **TypeScript strict.** `strict: true`, `noUncheckedIndexedAccess: true`,
  запрет `any` через ESLint — уже должно работать (см. `tsconfig.json`
  и `eslint` конфиг фронта). Если не работает — Head включает и исправляет
  упавшее, это часть Пункта 7.

## 10. Вопросы к Координатору (от frontend-director)

Ниже — пункты, по которым я не могу принять решение сам. Без ответов на
них бриф остаётся корректным, но Head начнёт работу не полностью
информированным.

1. **Существует ли субагент `frontend-dev` в `~/.claude/agents/`, или его
   надо создавать?** В MEMORY.md упомянут `frontend-head` ACTIVE-SUPERVISING
   c 2026-04-16, про `frontend-dev` конкретной записи нет. Если агент ещё
   не создан — это блокер **Дня 1** батча, и задача «создать frontend-dev»
   выходит за пределы моих полномочий (это зона Governance / Координатора).

2. **Есть ли согласованный backend-director'ом zero-version OpenAPI для
   auth/companies/users/roles эндпоинтов?** Если нет — первый шаг Координатора
   после приёма этого брифа должен быть не «отдай Head'у», а «согласуй
   с backend-director zero-version OpenAPI». Иначе Пункт 5 (MSW) и Пункт 6
   (skeleton-страницы) стартуют вслепую.

3. **CI для фронтенда уже настроен?** В `docs/pods/cottage-platform/phases/`
   я не увидел упоминания frontend CI-pipeline. Если нет — мне нужно
   подтверждение, что в рамках Пункта 7 Head имеет полномочия создавать
   `.github/workflows/frontend-ci.yml`, или же это должен делать
   infra-director.

4. **Bundle-лимит 500KB gzipped — устраивает Координатора?** Я выбрал эту
   цифру исходя из shadcn/ui + TanStack Query + react-router + zustand +
   RHF + zod + axios — в сумме это около 180–220KB gzipped на admin-
   chunk даже без нашего кода. Лимит 500KB даёт запас ~280KB на наш
   код в обоих chunk'ах. Если Координатор хочет более жёсткий лимит
   (например, 300KB суммарно) — мне нужно знать сейчас, чтобы Head
   закладывал агрессивную tree-shaking стратегию с первого дня.

5. **Какую из страниц — Dashboard/Houses/Finance/Schedule из фаз 2–3 —
   нужно сохранить работающей, а какие можно «заморозить» (пусть лежат,
   но не тестируем)?** Они написаны до multi-company и сейчас **не**
   фильтруются по `company_id` — это баг безопасности, который будет
   исправлен в 1.1-batch-2. Пока я предлагаю их оставить рабочими под
   `/admin/*`, но исключить из Playwright-smoke этого батча. Подтверждение
   Координатора нужно.

---

## Подпись

*Бриф подготовлен frontend-director'ом (L2) 2026-04-17 по задаче Координатора.
Формат — регламент директор→head, принятый в проекте. После ответа Координатора
на 5 вопросов §10 — бриф передаётся frontend-head для декомпозиции на задачи
frontend-dev.*

*Связанные документы: `docs/reviews/external-audit-2026-04-17-frontend.md`,
`docs/pods/cottage-platform/m-os-1-frontend-plan.md`,
`docs/pods/cottage-platform/m-os-1-plan.md`, ADR 0002, ADR 0011,
CODE_OF_LAWS v2.1 ст. 45а, CLAUDE.md.*
