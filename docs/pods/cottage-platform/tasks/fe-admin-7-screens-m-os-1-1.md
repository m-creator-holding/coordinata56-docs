# Бриф для frontend-head: батч «M-OS-1.1 Admin — 7 экранов»

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт», v1.6)
- **Батч-ID:** M-OS-1.1-admin-7-screens
- **Под-фаза:** M-OS-1.1 Foundation (pod: cottage-platform)
- **Зависит от:** закрытия батча `M-OS-1.1-fe-skeleton` (каркас роутинга, AdminLayout, AuthProvider, MSW, CI bundle-limit)
- **Статус брифа:** передан Координатором, ждёт прочтения Head'ом и распределения Worker'ам

---

## 0. Основание и источники

Этот батч наполняет каркас M-OS-1.1 реальным admin-UI. Работа ведётся напрямую по
text-based wireframes (решение Координатора: code-first, без Figma; Figma может быть
пересмотрена в M-OS-2+ если появится dedicated дизайнер).

**Обязательно к прочтению Head'ом до распределения задач:**

1. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` v1.0 — 7 экранов,
   все режимы, все Dialog'и, все поля, все состояния UI. Самодостаточный документ
   для frontend-dev.
2. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin-review.md` — ревью
   ux-head, «APPROVE with corrections» (все M-1/M-2/M-3 уже внесены в revision_round 2).
3. `docs/pods/cottage-platform/tasks/fe-skeleton-m-os-1-1.md` — предшествующий батч,
   его результаты (структура `/admin/*`, AdminLayout, AuthProvider, MSW, axios,
   TanStack Query) — фундамент для этой работы.
4. `docs/adr/0011-foundation-multi-company-rbac-audit.md` — multi-company модель,
   RBAC v2. Все формы и списки учитывают `company_id` из контекста.
5. `docs/design/design-system-initiative.md` v0.1 — черновик Design System. Для
   этого батча — reference для выбора semantic tokens, WCAG-паттернов и
   state-representation (цвет + иконка + текст).
6. `docs/agents/CODE_OF_LAWS.md` ст. 45а — запрет живых внешних интеграций.
   В Экране 6 (Integration Registry): Telegram активен, Сбербанк/1С/ОФД/Росреестр —
   статус «Недоступно», информационный Dialog без форм активации.
7. `backend/openapi.json` (commit `74a066e`) — zero-version OpenAPI stub. Все
   запросы на чтение/запись возвращают 501, но контракт для генерации TS-типов уже
   есть. Head обязан сверить список endpoint'ов из wireframes с имеющимся stub'ом —
   расхождения эскалируются Координатору для согласования с backend-director
   (подробности — §6 «Зависимости»).
8. `CLAUDE.md` (корневой) — секции «Процесс», «Код», «Git», «Engineering principles»
   (4 правила против over-engineering: думать перед кодом, сначала простота,
   хирургические правки, работать от цели).

---

## 1. Бизнес-цель батча

За 3–4 календарных недели (11–16 рабочих дней на одного frontend-dev, возможно
подключение `frontend-dev-2` в Волне 2 — решение Head'а) получить полностью
функциональный admin-UI M-OS-1.1: семь экранов, описанных в wireframes, с формами,
таблицами, диалогами, матрицей прав, настройками и интеграциями.

Результат батча — приложение, в котором Владелец холдинга может:
- завести юрлица холдинга (4 штуки для MVP посёлка) с реквизитами, банковскими счетами, сотрудниками, настройками;
- создать пользователей и назначить им роли в нужных компаниях (UserCompanyRole);
- просмотреть и отредактировать матрицу прав role × action × resource;
- настроить Telegram-бот для алертов;
- контролировать глобальные feature flags и статус audit-цепочки.

Все вызовы бэка — через MSW-handlers (возвращают фиктивные данные по контракту
stub'а). Переключение на реальные endpoint'ы произойдёт автоматически, когда
PR #2 (RBAC v2) закоммитится и бекенд начнёт отвечать 200/201 вместо 501.

---

## 2. Скоуп батча — 7 экранов в 3 волнах

Скоуп **закрытый**. Любое «заодно и X» — через Head Директору, Директор → Координатор.

### Волна 1 (P0) — 5–7 дней. Блокирующая последующие экраны.

Без готовых Экранов 1–3 невозможно ни заполнить матрицу прав (Экран 4), ни
протестировать Company Settings (Экран 5).

#### Экран 1. Companies (`/admin/companies`)

**Что сделать.** Четыре режима:
- 1.А Список компаний (`/admin/companies`) — таблица + поиск + фильтры «Тип» / «Статус».
- 1.Б Детальная карточка (`/admin/companies/:id`) — вкладки: Реквизиты / Сотрудники / Банк. реквизиты / Настройки.
- 1.В Форма создания (`/admin/companies/new`) — отдельный роут, 12+ полей, секции «Основные данные» / «Адрес и руководство» / «Прочее». Условная видимость КПП (скрыт для ИП). Динамическая метка «Ген. директор» / «Индивидуальный предприниматель».
- 1.Г Форма редактирования (`/admin/companies/:id/edit`) — идентична 1.В, поля предзаполнены, кнопка «История изменений» внизу.

**Ключевые компоненты.**
- Dialog добавления/редактирования банковского счёта (вкладка «Банк. реквизиты»): 6 полей, автозаполнение «Название банка» и «Корр. счёт» из справочника БИК, вшитого во фронтенд.
- Кнопки-заглушки «Загрузить файл» (Печати и подписи, Логотип) — при клике открывают информационный Dialog: «Файловое хранилище — M-OS-2».

**Acceptance.**
- Все 4 режима реализованы и навигация между ними работает.
- Все состояния UI из wireframes (Loading, Empty, Error, Success create/edit/deactivate/bank-add) покрыты.
- Валидация форм через react-hook-form + Zod: ИНН (10/12 цифр, Luhn для некоторых регионов — достаточно проверки длины и цифр), КПП (9 цифр), ОГРН (13/15 цифр), БИК (9 цифр), счёт (20 цифр).
- Хлебные крошки «← Юрлица» / «← Юрлица / ООО «Металл» / Редактировать» корректны.
- Playwright smoke: создать компанию → открыть карточку → открыть редактирование → открыть Dialog банк.счёта → сохранить → вернуться.

**Файлы (ориентир, Head уточняет):**
- `frontend/src/admin/pages/companies/CompaniesListPage.tsx`
- `frontend/src/admin/pages/companies/CompanyDetailsPage.tsx` (с вкладками)
- `frontend/src/admin/pages/companies/CompanyFormPage.tsx` (create + edit, переключается по режиму)
- `frontend/src/admin/pages/companies/BankAccountDialog.tsx`
- `frontend/src/admin/pages/companies/PlaceholderUploadDialog.tsx` (общий для «Загрузить» — можно реюзить)
- `frontend/src/shared/validation/companySchemas.ts` (Zod)
- `frontend/src/shared/data/bikCatalog.ts` (справочник БИК, вшитый во фронт, MVP — 10–20 записей)
- `frontend/src/shared/api/companies.ts` (расширяется — сейчас skeleton)
- `frontend/src/mocks/handlers/companies.ts` (расширяется)
- `frontend/src/mocks/fixtures/companies.ts` (4 компании холдинга + 1 банк.счёт на каждую)

#### Экран 2. Users (`/admin/users`)

**Что сделать.** Три режима:
- 2.А Список пользователей с поиском и фильтрами.
- 2.Б Детальная карточка (`/admin/users/:id`) с блоком «Роли по компаниям» (таблица UserCompanyRole с колонками Компания / Роль / Pod / Действия).
- 2.В Форма создания/редактирования пользователя (`/admin/users/new`, `/admin/users/:id/edit`) — 5 полей, пароль только при создании.

**Ключевые компоненты.**
- Dialog «Добавить/Изменить привязку роли»: 3 поля (Компания / Роль / Pod). Select'ы тянут данные из `/api/v1/companies` и `/api/v1/roles` через MSW.
- Dialog подтверждения «Сбросить пароль» → POST `/api/v1/users/:id/reset-password`.
- Dialog подтверждения «Деактивировать пользователя».

**Acceptance.**
- Все 3 режима + 3 Dialog'а реализованы.
- Валидация: email (формат + уникальность — MSW возвращает 409 Email занят и это мапится на ошибку под полем), пароль (≥8 символов), телефон (маска +7).
- Состояние «Email занят» — ошибка под полем (не toast).
- При редактировании поле «Пароль» отсутствует, вместо него кнопка «Сбросить пароль».
- Playwright smoke: создать пользователя → привязать к компании с ролью → изменить привязку → удалить привязку → сбросить пароль.

**Файлы:**
- `frontend/src/admin/pages/users/UsersListPage.tsx`
- `frontend/src/admin/pages/users/UserDetailsPage.tsx`
- `frontend/src/admin/pages/users/UserFormPage.tsx`
- `frontend/src/admin/pages/users/UserRoleBindingDialog.tsx`
- `frontend/src/admin/pages/users/ResetPasswordDialog.tsx`
- `frontend/src/shared/validation/userSchemas.ts`
- `frontend/src/shared/api/users.ts` (расширение)
- `frontend/src/mocks/handlers/users.ts`
- `frontend/src/mocks/fixtures/users.ts` (3–4 пользователя с разным количеством привязок)

#### Экран 3. Roles (`/admin/roles`)

**Что сделать.** Три режима:
- 3.А Список ролей — 4 системные роли из seed (владелец, бухгалтер, прораб, read-only) + возможность создать пользовательскую роль.
- 3.Б Детальная карточка (`/admin/roles/:id`) с вкладками «Общее» / «Права» (вкладка «Права» — навигационный переход в Экран 4 с предфильтром).
- 3.В Sheet создания/редактирования роли — 4 поля. При редактировании `role_code` — read-only.

**Ключевые компоненты.**
- Tooltip на названии роли в таблице (shadcn/ui Tooltip) — первые 80 символов описания (M-3 из ревью).
- Badge «Системная» — системные роли без кнопки «Удалить»; Tooltip на Badge объясняет причину.
- Sheet (shadcn/ui Sheet) — боковая панель для формы роли, 5 полей умещаются без прокрутки.

**Acceptance.**
- Все 3 режима реализованы, Sheet открывается/закрывается корректно.
- Переход на Экран 4 через `/admin/permissions?role=<code>` работает, query-param правильно пробрасывается.
- Попытка удалить системную роль — ошибка MSW 403, сообщение «Системная роль не может быть удалена».
- Playwright smoke: открыть роль «Бухгалтер» → вкладка «Права» → кнопка «Открыть матрицу прав» → переход на Экран 4 с предфильтром.

**Файлы:**
- `frontend/src/admin/pages/roles/RolesListPage.tsx`
- `frontend/src/admin/pages/roles/RoleDetailsPage.tsx`
- `frontend/src/admin/pages/roles/RoleFormSheet.tsx`
- `frontend/src/shared/validation/roleSchemas.ts`
- `frontend/src/shared/api/roles.ts` (расширение)
- `frontend/src/mocks/handlers/roles.ts`
- `frontend/src/mocks/fixtures/roles.ts` (4 системные роли)

### Волна 2 (P1) — 5–7 дней. После Волны 1.

#### Экран 4. Permissions Matrix (`/admin/permissions`)

**Что сделать.**
- Таблица role × action с вкладками по resource_type: `[contract] [payment] [project] [* (все)]`.
- Режим просмотра: чекбоксы отображаются как символы `[✓]` / `[✗]`, не интерактивны.
- Режим редактирования: кнопка «Редактировать» → появляются живые чекбоксы + кнопки «Сохранить» / «Отменить» (вверху и внизу).
- Системные права (owner + admin + `*`) — чекбокс disabled + иконка замка + Tooltip.
- Предфильтр по роли через `?role=<code>` — строка выделена (highlight), над таблицей banner «Показаны права роли: <name>. [Сбросить фильтр]».
- Пакетное сохранение — один PATCH-запрос с массивом изменений (дифф от исходного состояния).

**Критично:** это **кастомный компонент вне shadcn/ui**, требует `@tanstack/react-table` + ручной виртуализации (зафиксировано в Design System Initiative v0.1). При 4 ролях × 5 действий × 4 resource_type виртуализация пока не критична, но архитектура должна её поддерживать (BPM/отчёты в M-OS-1.2/1.3 могут добавить много ресурсов).

**Acceptance.**
- Переключение вкладок ресурсов работает, данные каждой вкладки подгружаются корректно.
- Режим редактирования изолирован: изменения не сохраняются до нажатия «Сохранить».
- При «Отменить» восстанавливается исходное состояние.
- banner-предупреждение «Вы в режиме редактирования» присутствует в режиме редактирования.
- Системные права действительно disabled, попытка клика не меняет состояние.
- PATCH-payload содержит только дифф (только изменённые комбинации role × action × resource).
- Playwright smoke: войти в матрицу → отфильтровать по роли → отредактировать → сохранить → изменения персистятся (в MSW).

**Файлы:**
- `frontend/src/admin/pages/permissions/PermissionsMatrixPage.tsx`
- `frontend/src/admin/pages/permissions/PermissionsTable.tsx` (кастомный компонент на базе @tanstack/react-table)
- `frontend/src/admin/pages/permissions/PermissionsTabs.tsx`
- `frontend/src/admin/pages/permissions/LockedCellIndicator.tsx`
- `frontend/src/shared/api/permissions.ts`
- `frontend/src/mocks/handlers/permissions.ts`
- `frontend/src/mocks/fixtures/permissions.ts` (все комбинации для 4 системных ролей)
- `frontend/package.json` — добавить `@tanstack/react-table` в dependencies

**Зависимость:** установка `@tanstack/react-table` — новая runtime-зависимость. Согласование ADR 0002 не требуется (taxonomy расширений shadcn/ui не ограничивает tanstack-стек), но Head обязан зафиксировать это в своём отчёте для документирования в `docs/agents/departments/frontend.md`.

#### Экран 5. Company Settings (`/admin/companies/:id/settings`)

**Что сделать.** Форма с 7 полями (per-company) в 3 секциях:
- Бухгалтерия: НДС-режим, Валюта
- Региональные настройки: Часовой пояс, Рабочая неделя (Пн–Вс), Единицы измерения
- Внешний вид: Логотип (placeholder), Цвет бренда (нативный `input[type=color]` + HEX-Input + превью-прямоугольник — решение Координатора Q2)

**Ключевые требования.**
- IANA-зоны **вшиваются во фронтенд** (список ~30–50 наиболее релевантных зон для холдинга в России + мира, минимум Europe/Moscow по умолчанию). Отдельный endpoint не создаётся.
- Dialog подтверждения при попытке уйти со страницы с несохранёнными изменениями.
- Ссылка «← ООО "Металл"» как breadcrumb → `/admin/companies/:id`.
- Ссылка «История изменений» (внизу формы) — пока placeholder (аудит-лог экран появится позже, M-OS-1.1 не включает).

**Acceptance.**
- Все 7 полей сохраняются через PATCH `/api/v1/companies/:id/settings`.
- HEX-Input валидирует формат `#RRGGBB`, при изменении обновляет превью и `input[type=color]` (двусторонняя синхронизация).
- Checkbox-группа «Рабочая неделя» — хотя бы один день обязателен, иначе ошибка валидации.
- Dialog «Несохранённые изменения» появляется при `navigate` с грязной формой.
- Playwright smoke: открыть настройки компании → изменить часовой пояс → попытаться уйти → Dialog → отменить → сохранить → успех.

**Файлы:**
- `frontend/src/admin/pages/companies/CompanySettingsPage.tsx`
- `frontend/src/admin/pages/companies/ColorBrandPicker.tsx` (native color + HEX)
- `frontend/src/shared/data/ianaTimezones.ts` (вшитый список)
- `frontend/src/shared/hooks/useUnsavedChangesGuard.ts`
- `frontend/src/shared/validation/companySettingsSchemas.ts`
- `frontend/src/shared/api/companySettings.ts`
- `frontend/src/mocks/handlers/companySettings.ts`

### Волна 3 (P2) — 3–4 дня. После Волны 2.

#### Экран 6. Integration Registry (`/admin/integrations`)

**Что сделать.** Каталог из 5 карточек:
- Telegram — живая карточка с кнопкой «Настроить» → Sheet с формой (Bot Token, Chat ID, Switch статуса, чекбоксы разрешённых событий, кнопка «Проверить подключение»).
- Сбербанк, 1С, ОФД, Росреестр — статус «Недоступно». Клик на карточку → информационный Dialog «Интеграция будет активирована после production-gate» (без форм активации — **строгое требование ст. 45а**).

**Acceptance.**
- Telegram Sheet открывается с формой, все 4 поля работают.
- Кнопка «Проверить подключение» отправляет POST `/api/v1/integrations/telegram/test`, MSW возвращает успех (зелёный текст) или ошибку (красный текст).
- Карточки «Недоступно» имеют disabled-стиль (приглушённый), но кликабельны (открывают Dialog).
- В production-сборке код форм активации для Сбербанк/1С/ОФД/Росреестр **физически отсутствует** (не просто скрыт) — проверяется grep'ом `dist/*.js` на отсутствие строк типа «sbercbank_token», «ofd_api_key».
- Playwright smoke: открыть реестр → Settings Telegram → ввести токен → Test → успех → сохранить.

**Файлы:**
- `frontend/src/admin/pages/integrations/IntegrationRegistryPage.tsx`
- `frontend/src/admin/pages/integrations/TelegramSettingsSheet.tsx`
- `frontend/src/admin/pages/integrations/UnavailableIntegrationDialog.tsx`
- `frontend/src/shared/validation/integrationSchemas.ts`
- `frontend/src/shared/api/integrations.ts`
- `frontend/src/mocks/handlers/integrations.ts`

#### Экран 7. System Config (`/admin/system`)

**Что сделать.**
- Guard: если `is_holding_owner=false` — экран 403 (не скрываем пункт в sidebar, показываем явное 403).
- Блок «Системная информация» (read-only): версия M-OS, дата деплоя, число компаний, статус audit-цепочки (с кнопкой «Подробнее» при нарушении → Dialog с broken_links).
- Блок «Глобальные настройки»: URL приложения, название системы, макс. размер файла (МБ), макс. время неактивности (мин).
- Блок «Флаги функций»: 5 Switch'ей с поиском по названию/коду (фильтрация в реальном времени).
- Кнопки «Сохранить» / «Отменить изменения». Dialog несохранённых изменений при навигации.

**Acceptance.**
- 403-экран показывается не-holding_owner.
- Блок audit-цепочки опрашивает `/api/v1/audit/verify`, обрабатывает оба состояния (OK / нарушение).
- Поиск по флагам работает (вводим «bpm» — видим только bpm_constructor_enabled).
- Валидация числовых полей (таймаут сессии 5–480 мин, размер файла 1–1024 МБ).
- Playwright smoke: войти как holding_owner → System Config → переключить feature flag → сохранить; войти как не-owner → 403.

**Файлы:**
- `frontend/src/admin/pages/system/SystemConfigPage.tsx`
- `frontend/src/admin/pages/system/SystemInfoBlock.tsx`
- `frontend/src/admin/pages/system/FeatureFlagsBlock.tsx`
- `frontend/src/admin/pages/system/AuditChainBrokenDialog.tsx`
- `frontend/src/admin/pages/system/ForbiddenPage.tsx` (403)
- `frontend/src/shared/validation/systemConfigSchemas.ts`
- `frontend/src/shared/api/systemConfig.ts`
- `frontend/src/mocks/handlers/systemConfig.ts`

---

## 3. Архитектурные требования (сквозные)

### 3.1 Типизация через openapi-typescript

- Скрипт `npm run codegen:api` уже настроен в батче skeleton.
- Все вызовы бэка используют типы из `frontend/src/shared/api/schema.ts`
  (сгенерированные из `backend/openapi.json`). Ручные `interface` для тел запросов/ответов **запрещены**.
- Если stub не содержит нужной схемы — Head эскалирует Координатору для координации с backend-director (см. §6 «Зависимости»).

### 3.2 MSW — единственный источник ответов в dev

- Все новые handler'ы — в `frontend/src/mocks/handlers/<domain>.ts`, регистрируются в `frontend/src/mocks/handlers/index.ts`.
- Handler'ы соблюдают контракт stub'а (статус-коды, формат ошибок ADR 0005, envelope пагинации ADR 0006).
- Fixtures — статические JSON в `frontend/src/mocks/fixtures/`. Минимальный объём для каждого экрана: 2–5 записей + edge-cases (неактивная компания, заблокированный пользователь, пользовательская не-системная роль).
- **Правило 2 недель:** handler живёт максимум 2 недели без реального backend-endpoint'а. После 2 недель — handler помечается `DEPRECATED`, задача на hold. Документируется Head'ом в отчёте батча.
- **Переключение на реальный бэк:** когда PR #2 (RBAC v2) закоммитится, MSW не удаляется — остаётся для тестов и dev-локально, но в `.env.development.local` появляется флаг `VITE_USE_REAL_API=true` (детали — Head проектирует в Волне 2).

### 3.3 Формы — RHF + Zod

- Все формы — `react-hook-form` + Zod-schemas в `frontend/src/shared/validation/`.
- Ошибки полей отображаются под полем (WCAG: aria-describedby).
- Серверные ошибки (409 Email занят, 422 Validation) маппятся на ошибки RHF через `setError`.
- Toast для серверных 500-ошибок (shadcn/ui Sonner или аналог из skeleton-набора).

### 3.4 TanStack Query + axios

- Все запросы через `useQuery` / `useMutation`.
- `axios`-instance из `frontend/src/shared/api/client.ts` (из skeleton) — имеет interceptor для JWT.
- QueryKey convention: `['companies']`, `['companies', id]`, `['users', id, 'roles']`.
- `invalidateQueries` после мутаций — обязательно, чтобы таблицы и карточки обновлялись.
- Optimistic updates — **только** для Dialog привязки роли (простой toggle) и Sheet Telegram (локальный Switch). Для форм create/edit — обычный flow с ожиданием 200.

### 3.5 Состояния UI — все пять покрыты на каждом экране

Для каждого экрана обязательны компоненты:
- `<PageLoadingSkeleton>` (shimmer)
- `<EmptyState>` с иллюстрацией и кнопкой CTA
- `<ErrorState>` с banner «Не удалось загрузить. [Повторить]»
- Toast при Success/Error мутаций
- Dialog подтверждения для destructive actions (Удалить, Деактивировать, Сбросить пароль)

Переиспользовать компоненты из skeleton-батча (`TableSkeleton`, `EmptyState`, `ErrorState`).

### 3.6 RBAC guards

- `<RequireRole roles={['owner']}>` — обёртка для всех admin-страниц, кроме `/admin/login`. В этом батче — реальная проверка по `useCurrentUser().is_holding_owner` для Экрана 7; для остальных — заглушка (вернётся при интеграции с реальным backend'ом RBAC).
- Для Экрана 4 (матрица прав) кнопка «Редактировать» видна только `is_holding_owner=true` — иначе disabled с Tooltip «Нет прав на изменение».

### 3.7 Навигация и breadcrumbs

- Все детальные экраны (карточки, формы) имеют breadcrumbs вида «← Родительский список».
- Хлебные крошки — `<Breadcrumbs items={...} />` (новый компонент в `frontend/src/shared/ui/Breadcrumbs.tsx`, если ещё нет).

### 3.8 WCAG-минимум

- Все interactive elements имеют видимый focus-ring.
- Все Dialog'и закрываются по Esc, возвращают фокус на trigger-элемент.
- Все ошибки — `aria-describedby`, `role="alert"` у toast'ов.
- Цвет никогда не единственный носитель смысла: статус «Неактивна» = Badge серый + иконка × + текст «Неактивна».
- Full WCAG-AA audit — M-OS-2, в этом батче — минимум выше.

### 3.9 Bundle budget

- Admin-chunk суммарно ≤ 300 KB gzipped (из skeleton).
- Добавление `@tanstack/react-table` (~30 KB gzipped) может сузить запас. Head контролирует в CI.
- При превышении 300 KB — первая итерация **не увеличение лимита**, а анализ: какой экран тащит больше всего. Типичные кандидаты — BankAccountDialog (справочник БИК — вынести в lazy-chunk если > 20 KB), IANA-зоны (аналогично).
- Эскалация Директору только если после оптимизации всё ещё ≥ 330 KB.

---

## 4. Волны и оценка

| Волна | Экраны | Рабочих дней (на 1 dev) | Может ли параллелиться |
|---|---|---|---|
| Волна 1 (P0) | 1, 2, 3 | 10–12 | Да: `frontend-dev` делает Экран 1 → Экран 2; `frontend-dev-2` (если активирован) параллельно Экран 3 |
| Волна 2 (P1) | 4, 5 | 6–8 | Нет, нужна Волна 1 |
| Волна 3 (P2) | 6, 7 | 3–4 | Да: 2 экрана независимы, можно на двух dev'ах |
| **Итого** | 7 | **19–24** | При одном dev — 4–5 календарных недель; при двух — 3–3.5 недели |

**Про `frontend-dev-2`.** Активация второго воркера — решение Координатора по
рекомендации Директора. Head в конце Волны 1 оценивает, упирается ли в скорость
одного воркера, и запрашивает через Директора активацию. До появления второго dev
Head планирует работу одного.

---

## 5. Что НЕ входит в этот батч

Прямой список, чтобы не расплыться:

- **Реальный логин** — остаётся mock, даже после PR #2. Реальный логин — отдельная задача после стабилизации RBAC-бэка.
- **BPM Constructor (Экран из M-OS-1.2)** — не трогаем, только feature flag на Экране 7.
- **Form Builder, Report Builder** — M-OS-1.3.
- **Service Worker custom strategies, offline queue** — в этом батче Service Worker остаётся с дефолтной Workbox-стратегией из skeleton. Offline-PWA — отдельный батч после 7 экранов.
- **PWA прораба (field/*)** — вне скоупа, только skeleton-страницы продолжают работать.
- **Аудит-лог экран** — ссылки «История изменений» ведут на placeholder «Скоро». Сам экран — отдельный батч.
- **i18n** — весь UI на русском, английский не тестируется.
- **Dark mode** — вне скоупа (решение по dark mode — через RFC-006, 20–21 апреля).
- **Brand-per-company runtime замена цвета** — поле «Цвет бренда» сохраняется в Company Settings, но живого применения цвета к UI ещё нет. Применение — в M-OS-1.2 (шаблоны документов).
- **WCAG-AA full audit** — M-OS-2.
- **Мобильная адаптация admin-UI** — admin работает за десктопом, min-width 1024px (из AdminLayout).

---

## 6. Зависимости и риски

| № | Риск / зависимость | Вероятность | Влияние | Митигация |
|---|---|---|---|---|
| R1 | OpenAPI stub не содержит всех endpoint'ов из wireframes (permissions matrix, integrations, system config, audit verify, bank accounts) | Высокая | Высокое (блокирует codegen TS-типов) | **До старта Волны 1** Head обязан сверить список endpoint'ов из wireframes с `backend/openapi.json`. Отсутствующие эндпоинты — Head эскалирует Директору; Директор через Координатора — backend-director для расширения stub'а. MSW-handler'ы пишутся только против согласованных схем |
| R2 | `@tanstack/react-table` конфликтует с существующим `@tanstack/react-query` | Низкая | Низкое | Оба пакета из одной экосистемы TanStack, совместимы. Head проверяет при первой установке |
| R3 | Permissions Matrix — кастомный компонент, риск over-engineering (попытка сделать «универсальный data-grid») | Средняя | Среднее | CLAUDE.md «Engineering principles»: сначала простота. Head ревьюит: сначала работает на 4 ролях × 5 действий × 4 resource, оптимизация только когда реально нужна |
| R4 | Bundle превышает 300 KB gzipped из-за shadcn/ui-компонентов + tanstack-table | Средняя | Среднее | Анализ в CI, lazy-chunks для справочников (БИК, IANA), tree-shaking shadcn/ui |
| R5 | frontend-dev пытается реализовать offline-логику сейчас, а не в отдельном батче | Средняя | Среднее | Head в задаче явно пишет: «offline/PWA custom strategies — вне скоупа». Ревью ловит |
| R6 | frontend-dev пытается реализовать настоящую интеграцию Telegram (живой вызов bot API) | Низкая | Критическое (нарушение ст. 45а) | Head в задаче явно: «Все интеграции — через MSW. Живых вызовов Telegram Bot API в этом батче нет». Ревью + reviewer ловят |
| R7 | MSW-handler'ы «живут» дольше 2 недель без backend-endpoint'а | Средняя | Низкое | Head ведёт список handler'ов и дат создания в отчёте батча, эскалирует Директору при приближении к 2 неделям |
| D1 | **OpenAPI stub расширен до покрытия всех endpoint'ов wireframes** (permissions, integrations, system, audit, bank accounts) | — | — | **Блокирующая зависимость** для Волны 1. Head эскалирует до старта через Директора → Координатора → backend-director |
| D2 | `@tanstack/react-table` добавлен в package.json | — | — | Head делает в ходе Волны 2 (перед Экраном 4) |
| D3 | Справочник БИК для автозаполнения банковских счетов | — | — | Вшивается во фронт. MVP-минимум: 10–20 крупнейших банков (Сбербанк, ВТБ, Альфа, Тинькофф, Газпромбанк, Россельхоз, ФК Открытие, Совкомбанк, Райффайзен, Промсвязьбанк). Head делает в ходе Волны 1 |
| D4 | Список IANA-зон | — | — | Вшивается во фронт. MVP-минимум: ~30 зон (Europe/Moscow обязательна, + регионы холдинга — Оренбург=Asia/Yekaterinburg, + крупные мировые Europe/London, America/New_York, Asia/Tokyo). Head делает в Волне 2 |
| D5 | `frontend-dev-2` (если требуется) | — | — | Head оценивает необходимость в конце Волны 1, эскалирует Директору |
| D6 | Design System Initiative v0.1 → v1.0 | — | — | Параллельный процесс design-director, не блокирует. Для этого батча используется v0.1 как reference |

---

## 7. Definition of Done батча

Батч считается закрытым, когда выполнены **все** пункты:

1. **Код.** Все 7 экранов реализованы. Файлы на месте, `npm run typecheck`, `npm run lint`, `npm run build` — зелёные.
2. **MSW-handlers.** Все endpoint'ы wireframes покрыты MSW-handler'ами, возвращающими реалистичные данные по контракту stub'а.
3. **Codegen.** `npm run codegen:api` работает, все вызовы бэка используют типы из `schema.ts`. Ручных interface'ов нет.
4. **Тесты.**
   - Vitest unit: минимум 20 smoke-тестов (по 2–3 на экран + на кастомные компоненты — BankAccountDialog, PermissionsTable, ColorBrandPicker).
   - Playwright E2E: минимум 7 сценариев (один основной happy-path на каждый экран).
5. **Bundle size.** Admin-chunk ≤ 300 KB gzipped. CI падает при превышении.
6. **Состояния UI.** Все пять (Loading / Empty / Error / Success / Dialog-confirm) покрыты на каждом экране.
7. **RBAC-guards.** Экран 7 реально защищён `<RequireRole>`, показывает 403 не-owner.
8. **Ст. 45а соблюдена.** В production-бандле нет кода форм активации Сбербанк/1С/ОФД/Росреестр (проверяется grep'ом dist).
9. **Reviewer-approve до коммита.** PR на reviewer (L4-advisory через Координатора). Reviewer работает на `git diff --staged`.
10. **Директор-вердикт.** Финальный approve от frontend-director.
11. **Отчёт Head'а.** Head в финальном отчёте документирует:
    - Список созданных файлов (для обновления `m-os-1-frontend-plan.md` §2.5).
    - Список MSW-handler'ов с датой создания (для правила 2 недель).
    - Новые runtime-зависимости (`@tanstack/react-table` + любые другие, согласованные в ходе работы).
    - Параметры bundle размера.
    - Открытые вопросы, требующие внимания Директора/Координатора в следующем батче.

---

## 8. Ревью-маршрут

```
frontend-dev (реализует Экран N, pushes to feature branch)
   ↓ self-review + локальные тесты
frontend-head (первичное ревью задачи → доработки dev'у → approve частичный — per screen)
   ↓ при закрытии волны
reviewer (L4-advisory, через Координатора) — полная волна целиком
   ↓
frontend-director (финальный approve-вердикт волны)
   ↓
Координатор (коммит волны)
```

Волны коммитятся **независимо** — не ждём закрытия всего батча, чтобы коммитить Волну 1. Это снижает риск больших PR и упрощает откат при проблемах.

**Параллелизма в рамках одной волны нет:** reviewer работает на `git diff --staged` после того, как Head собрал все экраны волны и прогнал smoke-тесты.

---

## 9. Документация

В ходе батча Head не делает сам, но в финальном отчёте указывает, что должно быть обновлено:

- `docs/pods/cottage-platform/m-os-1-frontend-plan.md` §2.5 — добавить пути всех файлов admin-UI. Обновляет Директор после закрытия батча.
- `docs/agents/departments/frontend.md` v0.1 → v1.0 — amendment через Governance-комиссию. В этом батче — первая реальная admin-работа, из неё выносятся конвенции: file layout `admin/pages/<domain>/`, Zod-schemas в `shared/validation/`, MSW-handler convention, RHF+Zod паттерн. Оформляет Директор.
- ADR 0011 — правки не планируются, но если в ходе батча найдутся неоднозначности RBAC v2 — эскалируются Координатору.

---

## 10. Эскалация по ходу

Head эскалирует Директору (через Координатора) в случаях:
- Обнаружил противоречие wireframes и stub OpenAPI, не разрешимое на уровне Head.
- Frontend-dev превышает оценку по волне больше чем на 30%.
- Bundle size не вмещается в 300 KB даже после оптимизации.
- frontend-dev просит выйти за скоуп (добавить экран, изменить поведение).
- Архитектурный выбор кастомного компонента требует обсуждения (например, виртуализация PermissionsTable способом, отличающимся от обычной tanstack-react-virtual).
- reviewer возвращает блокирующие замечания, которые требуют пересмотра архитектуры (например, «RHF+Zod не подходит для PermissionsTable, нужен другой паттерн» — это Директору).

Директор **не решает** за Head распределение задач между frontend-dev и frontend-dev-2 — это зона Head.

---

*Бриф подготовлен frontend-director (L2), 2026-04-18.*
*Передаётся Координатором на frontend-head (L3) через паттерн «Координатор-транспорт».*
*После прочтения Head формирует свой внутренний план распределения по Worker'ам и возвращает Координатору статус «принят, готов к старту Волны 1 после согласования D1 (расширение OpenAPI stub)».*
