# Бриф для frontend-head: батч FE-W1-3 Roles

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6 — Директор
  не вызывает Head напрямую)
- **Батч-ID:** FE-W1-3-roles
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-2 Users (закоммичен `bfb7041`) — shared auth-
  инфраструктура готова и закладывает паттерн для этого батча
- **Блокеры сняты:** FE-INFRA-1 lint gate (`a98d41a`), shared/auth (`bfb7041`)
- **Статус брифа:** утверждён направлением, ждёт одобрения Координатора
  для передачи Head

---

## 0. Основание и источники

Третий admin-экран Волны 1. Применяет паттерн FE-W1-1/FE-W1-2 к
справочнику ролей. В отличие от Users, этот экран **не содержит
вложенного ресурса** (Permissions матрица — отдельный Экран 4 / батч
FE-W1-4, этот экран только ссылается на неё). Отличия от предыдущих
двух батчей:

1. **UI-паттерн Sheet вместо отдельного роута для формы** — wireframes
   Экрана 3 (строка 700) явно указывают «Решение: Sheet (боковая
   панель)». Новый shadcn-компонент — отсылка к §8 Вопрос 2.
2. **Tooltip на названии роли в таблице** (wireframes §3.А, M-3 строка
   643) — новый shadcn-компонент Tooltip.
3. **Read-only CRUD для системных ролей** — 4 роли из seed помечены
   `is_system=true`, для них недоступны «Редактировать» и «Удалить».
   Это RBAC-подобный паттерн «доступно действие или нет», но без
   permissions — по флагу `is_system`.
4. **Вкладка «Права» — навигационная точка входа в Экран 4** (не
   реализует матрицу, только `<Link>` на `/admin/permissions?role=<code>`).

Источники, обязательные к прочтению Head'ом до распределения работы
dev'у:

1. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` —
   **Экран 3. Roles**, строки 605–790 (3 режима 3.А/3.Б/3.В, Sheet
   создания, вкладка «Права» с навигацией, Tooltip на названии роли,
   состояния UI, ссылка на OpenAPI)
2. `docs/pods/cottage-platform/specs/m-os-1-1-sync-contract.md` — статус
   `FE-W1-3 Roles` **WIREFRAME PENDING** → переходит в **IN PROGRESS**
   при согласовании этого брифа. **Важно:** sync-contract упоминает,
   что wireframe нуждается в review 2 с consent-модалкой. Consent-
   инфраструктура уже готова в FE-W1-2 (ConsentGuard) — этот батч
   её переиспользует, отдельного дизайна не требуется (см. §9).
3. `docs/agents/departments/frontend.md` **v1.1** — 4 обязательных
   стандарта retrospective FE-W1-1 (те же, что в FE-W1-2):
   - §5.1 Query Key Factory (`roleKeys` — уже есть в
     `shared/api/roles.ts`, расширить для CRUD)
   - §5.2 Controlled Select + RHF (`value=` вместо `defaultValue=`)
   - §5.2 `<Button asChild><Link>` для навигационных действий
   - §6.2 data-testid матрица
   - §6.3 матрица 5 состояний UI как обязательная
   - §6.4 bundle baseline FE-W1-2
4. **Эталон FE-W1-2 Users** — Head должен прочитать эти файлы и
   перенять структуру 1-в-1:
   - `frontend/src/pages/admin/users/*` — структура List / Details /
     Form / sections / dialogs
   - `frontend/src/shared/api/users.ts` — `userKeys`-фабрика, хуки
     TanStack Query, optimistic updates, pattern `TODO-fields`
   - `frontend/src/shared/auth/*` — готовая инфраструктура Can /
     usePermissions (этот батч её **использует, но не расширяет**)
   - `frontend/src/shared/validation/userSchemas.ts` — паттерн Zod-
     схем + `FormValues`-тип + `LABELS`-константы
   - `frontend/src/mocks/handlers/users.ts` и
     `frontend/src/mocks/fixtures/users.ts` — паттерн in-memory
     хранилища с CRUD
   - `frontend/e2e/admin-users.spec.ts` — паттерн smoke-тестов
5. `docs/pods/cottage-platform/tasks/fe-w1-2-users.md` — родительский
   бриф-эталон (сверять структуру этого брифа 1-в-1)
6. `docs/pods/cottage-platform/tasks/pr2-wave1-rbac-v2-pd-consent.md` —
   **§5.4 seed матрица ролей** (4 системные роли: owner, accountant,
   construction_manager, read_only + поля `code`, `name`, `is_system`,
   `description`). **§3 Пункт 7** (`GET /roles`, `PATCH
   /roles/{id}/permissions`) — контракт, на который закладываются MSW-
   моки. После merge PR#2 — sync-gate (см. §9).
7. `docs/adr/0011-foundation-multi-company-rbac-audit.md` — **Часть 2
   §2.2** (роли и permissions, список системных ролей)
8. `backend/openapi.json` — **ВАЖНО: расхождение** (см. §8 Вопрос 1):
   - Текущий stub `/api/v1/roles/*` моделирует **UserCompanyRole
     привязки** (строки 11700–11940), а **не справочник ролей-
     шаблонов**. Схемы `RoleRead / RoleCreate / RoleUpdate` для
     полноценного справочника в stub'е отсутствуют.
   - `PaginatedRoleResponse` (строки 4176–4210) содержит массив
     `UserCompanyRoleRead`, **не** `RoleRead` — это семантическая
     путаница в stub'е, которая разрешится в PR#2.
   - `PermissionsMatrixRead` / `PermissionsMatrixUpdate` (строки 4693–
     4750) — для Экрана 4 Permissions, **не используется в этом батче**,
     только ссылка из вкладки «Права».
   - `/api/v1/roles/permissions` (GET/PATCH) — **не трогаем в FE-W1-3**,
     это FE-W1-4 Permissions Matrix.
9. `frontend/src/shared/api/roles.ts` — уже содержит заготовку
   `roleKeys`, `useRoles()`, `useRole(id)` и тип `RoleRead` с TODO-
   комментарием. **Этот файл — стартовая точка**, расширить до CRUD.
10. `frontend/src/mocks/handlers/roles.ts` — уже содержит read-only
    handlers (GET list, GET detail). **Расширить до полного CRUD** с
    учётом `is_system`-гарантии.
11. `frontend/src/mocks/fixtures/roles.ts` — **переписать**: текущая
    фикстура содержит 3 абстрактные роли (admin/manager/viewer) без
    полей `code`/`is_system`/`scope`, нужна по wireframes и PR#2 seed.
12. `CLAUDE.md` корневой — секции «API», «Код», «Git», правило
    строгой цепочки делегирования, паттерн Координатор-транспорт v1.6

## 1. Бизнес-цель батча

Дать Владельцу возможность увидеть **справочник ролей холдинга**: 4
системные роли из seed (Владелец, Бухгалтер, Прораб, Только просмотр),
их коды, области действия, описания. При необходимости — создать
пользовательскую роль (будущая возможность после MVP), отредактировать
название и описание существующей. Также — навигационная точка
перехода в матрицу прав для детального редактирования permissions
конкретной роли.

Техническая цель — подтвердить, что паттерн FE-W1-1/FE-W1-2
масштабируется на **простой справочник** (без вложенного ресурса и
без собственной инфраструктуры permissions/consent) и ввести два новых
UI-паттерна: **Sheet для компактных форм** и **Tooltip для hover-
информации**. Эти паттерны повторно используются в Экранах 5 и 6
(Company Settings — Sheet для sub-настроек, Integration Registry —
Tooltip для краткого статуса интеграции).

## 2. Скоуп батча — закрытый список

Любое «заодно и X» запрещено — эскалация через Head Директору. Причина:
этот батч вводит 2 новых shadcn-компонента (Sheet, Tooltip), ошибки
в них каскадом попадут в следующие 3 экрана.

### Пункт 1. Роуты Roles

Расширить `frontend/src/routes.tsx` admin-секцию `/admin/roles/*`
(сейчас один placeholder-роут `/admin/roles` → `RolesPage.tsx`):

- `/admin/roles` — список (режим 3.А)
- `/admin/roles/:id` — детальная карточка с 2 вкладками (режим 3.Б)

**Формы создания/редактирования НЕ имеют собственных роутов** — они
открываются как Sheet (боковая панель) поверх текущей страницы. Это
отличие от Companies/Users, где форма — отдельный роут. Обоснование
(wireframes строка 700): полей у роли всего 4, Sheet компактнее
полноэкранной формы.

Вкладки карточки («Общее» / «Права») — через query-param `?tab=`
(тот же паттерн, что Companies vertical tabs). Вкладка «Права» —
навигационная, содержит только `<Link>` на Экран 4.

**Acceptance:** оба роута открываются, back-navigation по хлебным
крошкам работает, прямой deep-link `/admin/roles/:id?tab=permissions`
возвращает карточку с активной вкладкой «Права». Sheet создания
открывается по `?create=true` query-param (deep-link для тестов
и поддержка shareable URL).

### Пункт 2. Структура файлов

Существующий `src/pages/admin/RolesPage.tsx` (placeholder) удалить.
Развернуть в многофайловую структуру по паттерну Users, адаптированную
под отсутствие формы-роута:

```
src/pages/admin/roles/
  index.ts                         — re-export всех страниц
  RolesListPage.tsx                — режим 3.А (таблица + Sheet создания)
  RoleDetailsPage.tsx              — режим 3.Б (карточка с 2 вкладками + Sheet редактирования)
  tabs/RoleGeneralTab.tsx          — вкладка «Общее» карточки
  tabs/RolePermissionsTab.tsx      — вкладка «Права» (навигация в Экран 4)
  sheets/RoleFormSheet.tsx         — Sheet создания/редактирования роли (mode="create"|"edit")
  dialogs/DeleteRoleDialog.tsx     — AlertDialog подтверждения удаления (только для non-system)
```

**Обоснование отказа от отдельных `RoleFormPage` / `RoleFormWrappers`:**
Sheet встраивается в родительскую страницу через state (`useState`
для open/close), не требует собственного роута. Query-param
`?create=true` на `/admin/roles` открывает Sheet на списке; на
`RoleDetailsPage` кнопка «Редактировать» открывает Sheet inline.

**Секции внутри карточки НЕ выносятся в `sections/`** — в отличие от
Users, где секции логически независимы (Basic / Roles / System info),
здесь карточка содержит одну секцию «Общее» с 4 полями readonly и
вкладку «Права» как навигационную ссылку. Разбиение избыточно.

### Пункт 3. Переиспользование shared infrastructure (без расширения)

**Критично — отличие от FE-W1-2.** FE-W1-2 вводил shared/auth/*. Этот
батч **только потребляет** существующую инфраструктуру:

1. **`<Can action="role.admin">{children}</Can>`** — скрывает кнопку
   «+ Создать роль» и «Редактировать» у пользователей без права
   `role.admin`.
2. **`usePermissions()`** — если dev нужна программная проверка
   (например, редирект с `/admin/roles/new` при отсутствии прав).
3. **ConsentGuard** — уже работает на уровне `AdminApp`, этот батч
   защищён автоматически.
4. **AuthProvider / usePermissions** — не меняется.

**Запрещено:**
- Расширять `AuthUser` (id, permissions, consent_required уже в
  нужном формате)
- Создавать новые файлы в `shared/auth/*`
- Менять логику `usePermissions()`

Если Head видит, что нужна новая shared-инфраструктура — **эскалация
Директору** (это признак scope-creep или архитектурного просчёта в
FE-W1-2, требующего ретроспективного пересмотра).

### Пункт 4. API-слой

Файл `src/shared/api/roles.ts` — **расширить существующую заготовку**
до полного CRUD (паттерн 1-в-1 `users.ts`):

1. **Расширить тип `RoleRead`** (forward-compat до merge PR#2 —
   аналогично Вопросу 2 FE-W1-2):
   ```ts
   // TODO: после merge PR#2 — заменить на components['schemas']['RoleRead']
   export interface RoleRead {
     id: number
     code: string                  // новое, системный идентификатор (snake_case)
     name: string                  // отображаемое название
     description?: string | null
     scope: 'global' | 'company'   // новое, область действия
     is_system: boolean            // новое, системные не удаляются
     created_at?: string | null
     updated_at?: string | null
     // permissions НЕ включены — они в Экране 4 Permissions Matrix
   }
   ```

2. **Фильтры `RoleFilters`:** `search` (по `name`/`code`),
   `is_system` (true/false/null), `scope` (global/company/null).
   Пагинация — на клиенте (список всего 4–10 ролей), но envelope
   `PaginatedRoleResponse` всё равно используется для консистентности
   с ADR 0006.

3. **Query Key Factory `roleKeys`** — уже есть, расширить:
   ```ts
   export const roleKeys = {
     all: ['roles'] as const,
     lists: () => [...roleKeys.all, 'list'] as const,
     list: (filters: RoleFilters) => [...roleKeys.lists(), filters] as const,
     details: () => [...roleKeys.all, 'detail'] as const,
     detail: (id: number) => [...roleKeys.details(), id] as const,
   }
   ```
   **Не забыть мигрировать `useRole(id)`** со старого
   `[...roleKeys.all, 'detail', id]` на новый
   `roleKeys.detail(id)` — иначе кеш дублируется.

4. **Хуки:**
   - `useRoles(filters)` — уже есть, расширить с фильтрами
   - `useRole(id)` — уже есть, мигрировать на новый ключ
   - `useCreateRole()` — POST, invalidate `roleKeys.lists()`
   - `useUpdateRole(id)` — PATCH, invalidate `roleKeys.detail(id)` и lists
   - `useDeleteRole()` — DELETE, **только для non-system** (UI прячет
     кнопку; MSW возвращает 422 `SYSTEM_ROLE_PROTECTED` при попытке
     удалить системную — защита на случай bypass через devtools)

   Все типизированы через `RoleRead`. После PR#2 merge — через
   сгенерированный `components['schemas']['RoleRead']`.

5. **Отдельный endpoint `GET /api/v1/permissions`** — **не в этом
   батче**. Для вкладки «Права» (Экран 3 режим 3.Б) мы **не
   загружаем** permissions роли, просто рендерим ссылку на Экран 4.

### Пункт 5. Zod-схемы

`src/shared/validation/roleSchemas.ts` (новый файл), паттерн 1-в-1
`userSchemas.ts`:

- `codeSchema` — `z.string().regex(/^[a-z][a-z0-9_]*$/)` (snake_case,
  первый символ — буква, не цифра); `.min(3).max(64)`
- `nameSchema` — `z.string().min(1).max(128)`; поле обязательное
- `descriptionSchema` — `z.string().max(512).nullable().optional()`
  (до 512 символов по wireframes §Форма роли)
- `scopeSchema` — `z.enum(['global', 'company'])`
- `roleCreateSchema` — объединение выше (code + name + description +
  scope)
- `roleUpdateSchema` — `roleCreateSchema.partial().omit({ code: true })`
  — код роли **нельзя** менять после создания (wireframes: read-only
  input при редактировании)
- `LABELS_ROLE_FIELDS` — константы для отображения лейблов в Sheet

**Нет RBAC-схем для permissions** — это Экран 4.

### Пункт 6. MSW-хэндлеры и фикстуры

**Существующие `src/mocks/fixtures/roles.ts` и `src/mocks/handlers/roles.ts`
полностью переписать.** Текущие фикстуры содержат 3 абстрактные роли
(admin/manager/viewer) и не содержат полей `code`/`is_system`/`scope`.
PR#2 seed-матрица §5.4 требует 4 системные роли с корректными полями.

Паттерн 1-в-1 `handlers/users.ts`:

1. **`src/mocks/fixtures/roles.ts`** — 4 системные роли по PR#2
   §5.4 (плюс опционально 1 пользовательская для полноты CRUD-
   тестов):
   ```ts
   const INITIAL_ROLES: RoleFixture[] = [
     { id: 1, code: 'owner', name: 'Владелец',
       description: 'Полный доступ ко всем ресурсам холдинга',
       scope: 'global', is_system: true },
     { id: 2, code: 'accountant', name: 'Бухгалтер',
       description: 'Ввод платёжных данных, согласование расходов...',
       scope: 'company', is_system: true },
     { id: 3, code: 'construction_manager', name: 'Прораб',
       description: 'Контроль выполнения строительных работ...',
       scope: 'company', is_system: true },
     { id: 4, code: 'read_only', name: 'Только просмотр',
       description: 'Доступ к просмотру данных без редактирования',
       scope: 'company', is_system: true },
     // опционально — для тестирования create/update/delete
     { id: 5, code: 'senior_manager', name: 'Старший менеджер',
       description: 'Пользовательская роль для тестов',
       scope: 'company', is_system: false },
   ]
   ```
   Поле `permissions` из текущих фикстур **удалить** — это поле
   Экрана 4, не этого.

   **Важно — консистентность с fixtures/users.ts.** Пользователи в
   `makeUserFixtures()` (FE-W1-2) ссылаются на роли через `role:
   'owner' | 'accountant' | ...`. После переписывания фикстур ролей
   проверить, что `code`-значения совпадают с существующими
   пользовательскими ссылками; иначе `usersHandlers` сломаются на
   JOIN.

2. **`src/mocks/handlers/roles.ts` — полный CRUD:**
   - GET list — с фильтрами `search`, `is_system`, `scope`; envelope
     `PaginatedRoleResponse` (items/total/offset/limit)
   - GET detail — возвращает `RoleRead`
   - POST create — валидирует уникальность `code` (409
     `DUPLICATE_CODE`), генерирует `id = max + 1`, `is_system: false`
     по умолчанию, возвращает 201 + RoleRead
   - PATCH update — валидирует, **запрещает** менять `code` (422
     `CODE_IMMUTABLE` если передан в body), **запрещает** менять
     системные роли целиком? (см. §8 Вопрос 3) — для MVP разрешаем
     менять `name`/`description`/`scope` у системных ролей, но не
     `is_system`
   - DELETE — **422 `SYSTEM_ROLE_PROTECTED`** при попытке удалить
     системную; soft-delete не применяется (роли — справочник, либо
     есть, либо нет), возвращает 204

3. **`src/mocks/__tests__/handlers.test.ts`** — новые тест-кейсы:
   - GET list без фильтров возвращает 4–5 ролей
   - POST create с duplicate code → 409
   - POST create с невалидным code (uppercase, цифра в начале) → 422
   - PATCH system role → OK для name/description, 422 для code
   - DELETE system role → 422 SYSTEM_ROLE_PROTECTED
   - DELETE non-system role → 204

**In-memory + сбрасывается на перезагрузку** — как в Companies/Users.

### Пункт 7. UI-компоненты: 5 состояний (обязательно)

По §6.3 регламента v1.1 — все 5 состояний на каждом экране:

| Состояние | Где применяется | Реализация |
|---|---|---|
| loading | List (таблица) / Details / Sheet(edit preload) | Skeleton-строки/поля, `aria-busy="true"` |
| empty | List (0 ролей — теоретически невозможно при наличии seed, но обрабатывается) | Иллюстрация lucide-icon + CTA: «Роли не найдены. Проверьте, что seed-скрипт выполнен» (wireframes §Состояния) |
| error | List / Details / mutation-fail | Banner с `role="alert"` + «Повторить»; для mutation — toast sonner |
| success | Create/Update/Delete | Toast sonner; для create/update — Sheet закрывается и строка появляется/обновляется в таблице; для delete — строка исчезает |
| dialog-confirm | Удаление роли (только non-system) | AlertDialog, destructive-вариант |

**Новое относительно Users: is_system-aware состояние.** Когда роль —
системная:
- Кнопка «Удалить» в карточке → **не рендерится** (не просто disabled,
  а скрыта)
- Tooltip на Badge «Системная»: «Системные роли созданы автоматически
  и не могут быть удалены» (wireframes строка 763)
- Поле `code` в Sheet редактирования — `<Input disabled>` с help-
  текстом «Код роли нельзя изменять после создания»
- Остальные поля (`name`, `description`, `scope`) — редактируемы

**Permission-aware состояние (через `<Can>`):** когда
`!usePermissions().has('role.admin')`:
- Кнопка «+ Создать роль» → скрыта
- Кнопка «Редактировать» → скрыта
- Кнопка «Удалить» → скрыта
- Прямой URL `/admin/roles?create=true` → игнорируется (Sheet не
  открывается, но страница остаётся функциональной — список виден)

Компоненты shadcn — **нужны 2 новых** (эскалация §8 Вопрос 2):

- **Sheet** (Radix Dialog side-variant) — форма создания/редактирования
- **Tooltip** (Radix Tooltip) — hover-описание на названии роли и
  на Badge «Системная»

Добавляются через `npx shadcn@latest add sheet tooltip`. Обоснование
исключения из §7.2 регламента:
- Оба — часть shadcn registry (не сторонние библиотеки)
- Оба — необходимы по wireframes, альтернативы нет (Dialog вместо
  Sheet нарушит UX-паттерн; title-атрибут вместо Tooltip не
  поддерживает кастомный рендер)
- Оба — переиспользуются в Экранах 5, 6 (уже запланированы)

### Пункт 8. Accessibility и testid

**data-testid конвенция §6.2 регламента v1.1 — обязательна. Testid
матрица для Roles:**

- Страницы: `page-roles-list`, `page-role-details`
- Секции: `roles-table`, `role-general-tab`, `role-permissions-tab`
- Sheet: `sheet-role-form`, `sheet-role-form-title`
- Поля формы (Sheet): `field-role-code`, `field-role-name`,
  `field-role-description`, `field-role-scope`
- Кнопки: `btn-role-create`, `btn-role-save`, `btn-role-edit`,
  `btn-role-delete`, `btn-role-open-permissions`
- Диалоги: `dialog-delete-role`
- Строки таблицы: `row-role-{id}`
- Badges: `badge-role-is-system-{id}`, `badge-role-scope-{id}`
- Tooltip: `tooltip-role-description-{id}`, `tooltip-role-system`

**ARIA:**
- Все кнопки-иконки — `aria-label` (например, «Открыть матрицу прав
  для роли Бухгалтер»)
- Sheet — `role="dialog"` + `aria-labelledby="sheet-role-form-title"`
  (Radix даёт из коробки, проверить)
- Tooltip — `role="tooltip"`, связан с триггером через
  `aria-describedby` (Radix даёт)
- Badge «Системная» — `aria-label="Системная роль"` (не просто
  визуальный стиль)
- Таблица — `<caption>` или `aria-label="Список ролей холдинга"`

### Пункт 9. Playwright E2E — минимум 10 тестов

`frontend/e2e/admin-roles.spec.ts` — по аналогии с
`admin-users.spec.ts`. Минимум 10 тестов (требование Координатора,
унаследованное от FE-W1-2):

**Given/When/Then acceptance criteria:**

1. **E2E-1: Список ролей отображается.**
   - Given: пользователь авторизован (admin@example.com) и имеет право
     `role.admin`
   - When: открывает `/admin/roles`
   - Then: видна таблица из 4+ строк, в каждой — колонки Название,
     Код, Область, Статус; у всех системных ролей — Badge «Системная»

2. **E2E-2: Tooltip на названии роли.**
   - Given: открыт список ролей
   - When: наводит курсор на название роли «Бухгалтер»
   - Then: появляется Tooltip с первыми 80 символами описания

3. **E2E-3: Открытие карточки роли.**
   - Given: открыт список
   - When: кликает по строке «Бухгалтер»
   - Then: переход на `/admin/roles/2?tab=general`, видны поля Код,
     Название, Описание, Область, Статус; кнопка «Редактировать»
     видна (есть право)

4. **E2E-4: Создание пользовательской роли — happy path.**
   - Given: открыт список ролей
   - When: кликает «+ Создать роль» → открывается Sheet; вводит
     `code=senior_manager`, `name=Старший менеджер`,
     `description=...`, `scope=company`; нажимает «Создать роль»
   - Then: Sheet закрывается, toast «Роль создана», новая строка
     появляется в таблице; URL не изменился (Sheet — inline на
     списке)

5. **E2E-5: Валидация code при создании.**
   - Given: Sheet создания открыт
   - When: вводит `code=SeniorManager` (camelCase) → «Создать роль»
   - Then: inline-ошибка под полем «Только латинские буквы нижнего
     регистра, цифры и подчёркивание; первый символ — буква»; Sheet
     не закрывается; запрос не отправляется

6. **E2E-6: Duplicate code при создании.**
   - Given: Sheet создания открыт
   - When: вводит `code=owner` (уже существует) → «Создать роль»
   - Then: серверная ошибка 409, inline-ошибка под полем «Роль с
     таким кодом уже существует» (через RHF `setError`); Sheet
     остаётся открытым

7. **E2E-7: Редактирование роли — happy path.**
   - Given: открыта карточка роли `owner`
   - When: кликает «Редактировать» → Sheet с предзаполненными
     значениями; меняет `description`; нажимает «Сохранить»
   - Then: Sheet закрывается, toast «Изменения сохранены», новое
     описание видно в карточке

8. **E2E-8: Поле code в Sheet редактирования — readonly.**
   - Given: Sheet редактирования открыт (роль owner)
   - When: пытается кликнуть в поле `code`
   - Then: поле disabled, курсор не фокусируется; рядом help-текст
     «Код роли нельзя изменять после создания»

9. **E2E-9: Удаление системной роли запрещено.**
   - Given: открыта карточка роли `owner` (is_system=true)
   - Then: кнопка «Удалить» **не видна в DOM** (через is_system check
     в UI); Tooltip на Badge «Системная»: «Системные роли созданы
     автоматически и не могут быть удалены»

10. **E2E-10: Permission guard — без role.admin.**
    - Given: логин как пользователь без права `role.admin`
    - When: открывает `/admin/roles`
    - Then: список виден (read разрешён), но кнопки «+ Создать»,
      «Редактировать», «Удалить» **не видны в DOM** (через `<Can>`);
      прямой URL `?create=true` → Sheet не открывается

11. **E2E-11 (опционально, 11-й тест для запаса):** Навигация «Открыть
    матрицу прав» с карточки роли → переход на
    `/admin/permissions?role=accountant` (Экран 4 placeholder в этом
    батче — если ещё не реализован, тест проверяет только факт
    перехода по URL).

Все тесты — против MSW-моков, без живого backend (правило
`apiClient` в dev/test режиме).

## 3. Жёсткие ограничения (red zones)

- Статья 45а CODE_OF_LAWS — **никаких живых HTTP-запросов**. Только
  MSW.
- **Не трогать** существующие страницы: `DashboardPage`, `HousesPage`,
  `FinancePage`, `SchedulePage`, `LoginPage`, **весь
  `pages/admin/companies/**`, `pages/admin/users/**`**. Регрессий быть
  не должно.
- **Не трогать `shared/auth/*`** — он закреплён в FE-W1-2 и
  используется 6 будущими экранами. Любые правки — эскалация.
- **Backend — FORBIDDEN**. Любые `.py` в PR → reject.
- **Экран 4 Permissions Matrix — FORBIDDEN.** Вкладка «Права» — только
  `<Link>`, никакой матрицы, никаких permissions-запросов.
  `/api/v1/roles/permissions` не вызывается из UI этого батча.
- **Живые интеграции (LDAP / SCIM / auto-sync ролей из внешних систем) —
  запрещены.** Роли — in-memory MSW-фикстура.
- **Forbidden files под FE-W1-3:**
  - `src/pages/admin/companies/**` (FE-W1-1 зона)
  - `src/pages/admin/users/**` (FE-W1-2 зона)
  - `src/pages/admin/PermissionsPage.tsx` (FE-W1-4 зона)
  - `src/shared/api/companies.ts`, `src/shared/api/users.ts`,
    `src/shared/api/auth.ts` (чужие зоны)
  - `src/shared/auth/**` (FE-W1-2 infrastructure, frozen)
  - `src/shared/validation/companySchemas.ts`,
    `src/shared/validation/userSchemas.ts` (чужие зоны)
  - `src/mocks/handlers/companies.ts`, `src/mocks/handlers/users.ts`,
    `src/mocks/handlers/auth.ts` (чужие зоны)
  - `backend/**`, `docs/adr/**`, `.github/workflows/**`

## 4. Стандарты исполнения (из departments/frontend.md v1.1)

Head проверяет в review по чек-листу §5.3. Базовые — те же, что в
FE-W1-2:

1. **openapi-typescript** — типы из `backend/openapi.json`. **Nota
   bene:** после merge PR#2 — перегенерация обязательна, см. §9
   sync-gate
2. **RHF + Zod** — Sheet-форма использует RHF `useForm` с
   `zodResolver(roleCreateSchema | roleUpdateSchema)`
3. **TanStack Query** — все запросы через хуки из `roles.ts`
4. **Query Key Factory `roleKeys`** — обязательно (§5.1), миграция
   существующих ключей на factory
5. **Controlled Select + RHF** — Select «Область действия» в Sheet
   использует `value=` (§5.2)
6. **`<Button asChild><Link>`** — «Открыть матрицу прав» — обязательно
   через Link, не `onClick={navigate}` (§5.2). Навигация «Назад к
   списку» через Breadcrumb — тоже Link
7. **5 состояний UI** — все 5 на каждом экране (§6.3)
8. **data-testid матрица** — §6.2, см. Пункт 8
9. **WCAG 2.2 AA** — aria-label на кнопках-иконках, Tooltip связан
   через aria-describedby, Badge «Системная» — не просто цвет
10. **Bundle budget** — +20 KB gzip (меньше чем Users +30, т.к.
    переиспользуем shadcn + shared/auth). **Исключение:** Sheet +
    Tooltip сами по себе добавляют ~5–8 KB, укладываемся в 20. Если
    превышение — профилировать
11. **Lint / typecheck / build** — `npm run lint && npm run typecheck
    && npm run build` — **0 warnings**. FE-INFRA-1 gate.
12. **Unit-тесты** — для `roleSchemas` (валидация code regex), MSW-
    handlers (новые кейсы)

## 5. Структура работы для Head

### 5.1 Разделение на dev-задачи (рекомендация Директора)

Head распределяет сам. Рекомендация — **2 дев-задачи** (меньше, чем
FE-W1-2, т.к. нет shared infrastructure):

**Dev-задача #1 — API-слой + MSW-моки + Zod:**
- `src/shared/api/roles.ts` — расширение до CRUD + migration ключей
- `src/shared/validation/roleSchemas.ts` — новый файл
- `src/mocks/handlers/roles.ts` — переписывание до полного CRUD
- `src/mocks/fixtures/roles.ts` — переписывание с PR#2 seed матрицей
- Проверка консистентности с `fixtures/users.ts` (code-ссылки)
- Unit-тесты (roleSchemas, handlers)
- Ориентир: 0.5–0.7 дня

**Dev-задача #2 — UI Roles (страницы + Sheet + Tooltip):**
- `npx shadcn@latest add sheet tooltip` — новые компоненты
- `src/pages/admin/roles/*` — все файлы из §2 структуры
- Обновление `routes.tsx` — 2 роута (list + details)
- Удаление `src/pages/admin/RolesPage.tsx`
- Playwright `e2e/admin-roles.spec.ts` — 10+ тестов
- Ориентир: 1–1.3 дня

**Итого:** ориентировочно 1.5–2 дня для одного frontend-dev
последовательно, или ~1 день параллельно (2 dev'а — меньший эффект,
т.к. Dev-задача #1 короткая). Без дедлайна (msg 1306).

### 5.2 Порядок старта и зависимости

Dev-задача #1 (API + MSW + fixtures) должна завершиться **до** Dev-
задачи #2 (UI), т.к. UI использует хуки и типы из `roles.ts`. Разница
с FE-W1-2: shared infrastructure уже закреплена, не параллелится.

### 5.3 Review-процедура

Head проверяет dev-результат по чек-листу до передачи Директору:

- [ ] Оба роута Roles открываются, back-navigation работает
- [ ] Deep-link `/admin/roles?create=true` открывает Sheet создания
- [ ] Deep-link `/admin/roles/:id?tab=permissions` открывает вкладку
      «Права»
- [ ] Структура `src/pages/admin/roles/` соответствует §2
- [ ] Новые shadcn-компоненты Sheet и Tooltip добавлены, код в
      `components/ui/`
- [ ] `roleKeys` factory расширен, существующий `useRole(id)`
      мигрирован на новый ключ (старый `[...roleKeys.all, 'detail',
      id]` не встречается в коде)
- [ ] Фикстуры ролей соответствуют PR#2 seed §5.4 (code, name,
      description, scope, is_system — 4 системные + опционально 1
      пользовательская)
- [ ] **Консистентность с FE-W1-2**: `role`-поле пользователей в
      `fixtures/users.ts` ссылается на существующие `code` в новой
      `fixtures/roles.ts` — нет сломанных ссылок
- [ ] Zod-схема `codeSchema` корректно отвергает uppercase, цифры в
      начале, спецсимволы
- [ ] MSW-хэндлеры покрывают весь CRUD + `SYSTEM_ROLE_PROTECTED` +
      `DUPLICATE_CODE` + `CODE_IMMUTABLE`
- [ ] is_system-aware UI: у системных ролей **нет** кнопки «Удалить»
      (не disabled, а unmounted); поле `code` в Sheet — disabled
- [ ] Permission-aware UI: `<Can action="role.admin">` корректно
      скрывает кнопки
- [ ] Tooltip на названии роли показывает первые 80 символов описания
- [ ] Все 5 состояний UI на каждом экране
- [ ] testid по матрице §6.2
- [ ] **4 стандарта v1.1 соблюдены** (Query Key Factory, Controlled
      Select, `<Button asChild><Link>`, 5 состояний UI)
- [ ] `npm run lint / typecheck / build` — 0 warnings
- [ ] `npm run test:e2e admin-roles.spec.ts` — все 10+ тестов проходят
- [ ] Bundle delta ≤ +20 KB gzip
- [ ] Нет изменений в forbidden-файлах (§3)

P0/P1/P2 — по аналогии FE-W1-1/FE-W1-2:
- **P0** — блокирует merge (сломан happy path, нарушены red zones,
  регрессии FE-W1-1/FE-W1-2, система может удалиться)
- **P1** — до commit'а (accessibility gap, нарушение 4 стандартов,
  missing testid, bundle превышение, is_system bypass возможен в UI,
  duplicate code принят без 409)
- **P2** — technical debt

## 6. DoD батча

- PR содержит только файлы, перечисленные в §2 и §7; ни одного
  forbidden
- Весь чек-лист §5.3 зелёный
- Playwright 10+ тестов проходят локально
- Фикстуры ролей консистентны с FE-W1-2 Users (нет разрывов по
  `code`-ссылкам)
- Директор принимает PR: (а) паттерн Sheet-формы — достаточно хорош
  как эталон для Экранов 5/6, (б) is_system-aware UI реализован
  консистентно, (в) 4 стандарта v1.1 соблюдены, (г) shared/auth
  использован, но не изменён
- Координатор коммитит PR в main, затем — push origin (правило
  auto-push)

## 7. Файлы — итоговый список (для Head, не для исполнения)

**Создать:**
- `frontend/src/pages/admin/roles/index.ts`
- `frontend/src/pages/admin/roles/RolesListPage.tsx`
- `frontend/src/pages/admin/roles/RoleDetailsPage.tsx`
- `frontend/src/pages/admin/roles/tabs/RoleGeneralTab.tsx`
- `frontend/src/pages/admin/roles/tabs/RolePermissionsTab.tsx`
- `frontend/src/pages/admin/roles/sheets/RoleFormSheet.tsx`
- `frontend/src/pages/admin/roles/dialogs/DeleteRoleDialog.tsx`
- `frontend/src/shared/validation/roleSchemas.ts`
- `frontend/src/components/ui/sheet.tsx` (shadcn add)
- `frontend/src/components/ui/tooltip.tsx` (shadcn add)
- `frontend/e2e/admin-roles.spec.ts`

**Расширить:**
- `frontend/src/routes.tsx` — 2 новых роута Roles (list, details) +
  замена lazy-импорта `RolesPage`
- `frontend/src/shared/api/roles.ts` — расширение до CRUD + миграция
  ключей
- `frontend/src/mocks/handlers/roles.ts` — переписать с нуля (CRUD +
  is_system guard)
- `frontend/src/mocks/fixtures/roles.ts` — переписать (4 системные +
  опционально 1 пользовательская, поля code/scope/is_system)
- `frontend/src/mocks/handlers/index.ts` — re-export не меняется
- `frontend/src/mocks/__tests__/handlers.test.ts` — новые тест-кейсы
  для roles
- `frontend/src/api/generated/schema.d.ts` — если PR#2 смержен до
  старта батча — перегенерировать; иначе — по Sync-gate §9
- `frontend/package.json` — shadcn sheet/tooltip как peerDeps

**Удалить:**
- `frontend/src/pages/admin/RolesPage.tsx` (старый placeholder)

**FILES_ALLOWED для dev'а** — Head фиксирует явно в distribution-
задаче.

## 8. Вопросы к Координатору (ответ пакетом)

### Вопрос 1. Расхождение OpenAPI stub — `/api/v1/roles/*` моделирует UserCompanyRole, не RoleTemplate

**Факт.** В текущем `backend/openapi.json` (`74a066e` + PR#1) пути
`/api/v1/roles/*` описывают CRUD **привязок пользователя к роли**
(UserCompanyRole), не **справочник ролей-шаблонов** (RoleTemplate).
Схема `PaginatedRoleResponse` содержит массив `UserCompanyRoleRead`,
не `RoleRead`. Схем `RoleRead / RoleCreate / RoleUpdate` для
справочника в stub'е **нет**.

После merge PR#2 (по `pr2-wave1-rbac-v2-pd-consent.md` §3 Пункт 7) —
API дифференцируется: `/api/v1/roles/` станет справочником
RoleTemplate, а `/api/v1/users/{id}/roles` останется для
UserCompanyRole привязок (что и использует FE-W1-2).

Варианты для FE-W1-3:
- **A (рекомендация Директора).** Forward-compat — MSW-моки реализуют
  контракт справочника ролей по спеке PR#2 (RoleRead с code, name,
  description, scope, is_system). Ручные типы с TODO. После merge
  PR#2 — sync-gate (§9) перегенерирует schema.d.ts. Аналог Вопроса 1
  FE-W1-2.
- **B.** Ждать мержа PR#2 — блокирует 1.5–2 дня работы.
- **C.** Backend-director добавит RoleRead / RoleCreate схемы в stub
  отдельным мини-PR. Выигрыш незначительный, PR#2 всё равно
  перегенерирует.

Директор **рекомендует вариант A** — не блокировать UX-работу,
проверенный паттерн FE-W1-1 и FE-W1-2.

### Вопрос 2. Новые shadcn-компоненты Sheet и Tooltip — апрув?

По §7.2 регламента frontend v1.1, добавление новых shadcn-компонентов
требует эскалации. В этом батче нужны:

- **Sheet** — боковая панель для компактных форм. Обязательна по
  wireframes Экрана 3 (строка 700: «Решение: Sheet»). Альтернатив нет:
  Dialog полноэкранный нарушит UX-паттерн (форма с 4 полями слишком
  мала для Dialog).
- **Tooltip** — hover-подсказка на названии роли (wireframes §3.А M-3,
  строка 643) и на Badge «Системная» (wireframes строка 763).
  Альтернатива — нативный `title=` атрибут — не поддерживает
  кастомный рендер и доступность ограничена.

Оба — часть официального shadcn registry, не сторонние библиотеки.
Оба будут переиспользоваться в Экранах 5 (Company Settings — Sheet для
sub-настроек) и 6 (Integration Registry — Tooltip для статуса).

Директор рекомендует **апрув**. Эскалация формальная, не блокирующая.

### Вопрос 3. Редактирование системных ролей — разрешить или запретить?

Wireframes (строки 665–674, режим 3.Б) показывают для системной роли
Бухгалтер: все поля на карточке, **кнопка «Редактировать» присутствует**.
Но из состояний UI (строка 763): «Кнопка „Удалить" отсутствует для
системных ролей».

Формулировка неоднозначна: можно ли **редактировать** системную роль
(менять name/description/scope) или только **просматривать**? ADR 0011
§2.2 не уточняет.

Варианты:
- **A.** Редактирование разрешено для всех ролей кроме `code` (которое
  read-only при edit в любом случае) и `is_system` (которое UI не
  показывает как редактируемое поле). MVP-гибкость: Владелец может
  уточнить `description` у системной роли «Бухгалтер».
- **B.** Системные роли read-only полностью. Кнопка «Редактировать»
  скрыта так же, как «Удалить». Строгая защита seed-данных.
- **C.** Редактирование только `description`, `name` и `scope`
  заблокированы (совсем строго).

Директор **рекомендует вариант A** — баланс гибкости и безопасности.
Код роли (`code`) защищён от изменений (readonly при edit). `is_system`
не отображается как редактируемое поле. `name` можно поменять, если
seed-вариант «Бухгалтер» не подходит (например, на «Бухгалтер-
кассир»). Вариант B слишком жёсткий для MVP; C — over-engineering.

### Вопрос 4. Область действия `scope` — всегда 2 значения?

Wireframes показывают `scope ∈ {'company', 'global'}`. ADR 0011 §2.2
упоминает «Глобальная» для роли `owner` и «Компания» для остальных.

Варианты:
- **A.** Enum из 2 значений жёстко фиксирован в Zod и UI.
- **B.** Enum расширяется в будущем (например, `pod` scope для
  domain-pod-ролей M-OS-2), поэтому в типе `RoleRead.scope` оставить
  `string` и валидировать через Zod enum, который можно легко
  расширить.

Рекомендация Директора — **A** на MVP (жёсткий enum из 2 значений),
в M-OS-2 при расширении — отдельная задача на миграцию. YAGNI.

### Вопрос 5. Вкладка «Права» — нужна ли в FE-W1-3 или отложить в FE-W1-4?

Вкладка «Права» в карточке роли — **навигационная точка** (кнопка
«Открыть матрицу прав для этой роли» → `/admin/permissions?role=<code>`).
Сама матрица — Экран 4, батч FE-W1-4.

Варианты:
- **A.** Вкладка присутствует, содержит только текст и `<Link>` на
  Экран 4. Переход ведёт на `/admin/permissions?role=<code>` — но
  эндпоинт Экрана 4 ещё placeholder `PermissionsPage.tsx`. E2E-тест
  проверит только факт перехода по URL, не функциональность.
- **B.** Вкладка скрыта в FE-W1-3, добавляется в FE-W1-4 вместе с
  самой матрицей.
- **C.** Вкладка присутствует, `<Link>` disabled с tooltip «Экран в
  разработке».

Рекомендация Директора — **A**. Соответствует wireframes, не требует
дополнительной логики, E2E-11 тест опциональный. Когда FE-W1-4
реализует матрицу — переход автоматически заработает без правок
Roles.

---

## 9. Sync-gate follow-up после PR#2 merge

**Обязательная процедура** — аналогично FE-W1-2 §9. После merge PR#2:

1. **Codegen update.** `cd frontend && npm run codegen`, проверить
   дифф `src/api/generated/schema.d.ts`. Ожидаемые изменения:
   - Новые схемы: `RoleRead`, `RoleCreate`, `RoleUpdate`,
     `PaginatedRoleResponse` (новая семантика)
   - Старая схема `PaginatedRoleResponse` → переименуется в
     `PaginatedUserCompanyRoleResponse` (уже существует как отдельная
     в stub'е) или удалится
   - `/api/v1/roles/` → GET/POST/PATCH/DELETE для RoleTemplate
   - `/api/v1/users/{id}/roles` → для UserCompanyRole (не
     пересекается с этим батчем)

2. **Type-alias update.** В `src/shared/api/roles.ts` заменить ручной
   `RoleRead` на `components['schemas']['RoleRead']`:
   ```ts
   // Было: interface RoleRead { id, code, name, ... }
   // Стало: export type RoleRead = components['schemas']['RoleRead']
   ```
   Убрать TODO-комментарии.

3. **MSW-handler realignment.** Если backend-реализация отличается от
   MSW-моков (например, `scope` называется `level` в реальном
   backend) — синхронизировать. Приоритет — реальный backend.

4. **E2E retry.** Прогнать 10+ тестов повторно. Если падает — новые
   issues, не блокируют merged FE-W1-3, фиксируются для FE-W1-4.

5. **Отчёт sync-gate.** Head оформляет отчёт Директору. Координатор
   коммитит одним commit'ом.

**Ожидание:** ~0.3 дня, если MSW-моки корректны.

## 10. Связь с sync-contract

Обновить статус в `docs/pods/cottage-platform/specs/m-os-1-1-sync-
contract.md`:
- Row 3 Roles: **WIREFRAME PENDING** → **IN PROGRESS** (FE-W1-3
  distributed) → **DONE (MSW)** → Sync-gate → **DONE (real backend)**
- Блокеры: wireframes — OK, consent — закрыт FE-W1-2. PR#2 не
  блокирует благодаря варианту A §8 Вопрос 1.

Координатор обновляет sync-contract при каждой стадии.

---

## 11. Ключевые ADR/decisions в этом брифе

Сводка для быстрого обзора при утверждении:

1. **Forward-compat API-слой** (вариант A §8 Вопрос 1) — ручной тип
   `RoleRead` до merge PR#2, sync-gate на выходе. Аналог FE-W1-2.
2. **UI-паттерн Sheet для компактных форм** (§2.2 + §8 Вопрос 2) —
   новый паттерн, эталон для Экранов 5/6. Новые shadcn-компоненты:
   Sheet + Tooltip.
3. **Редактирование системных ролей разрешено кроме `code` и
   `is_system`** (§8 Вопрос 3, вариант A) — MVP-гибкость.
4. **Scope — жёсткий enum из 2 значений** (§8 Вопрос 4, вариант A) —
   YAGNI, расширение в M-OS-2.
5. **Вкладка «Права» присутствует с `<Link>` на Экран 4** (§8 Вопрос 5,
   вариант A) — навигационная точка, не требует реализации матрицы.
6. **shared/auth — consume-only, frozen** (§2.3) — инфраструктура из
   FE-W1-2 переиспользуется без изменений. Эскалация при попытке
   расширить.
7. **Query Key Factory с миграцией существующих ключей** (§2.4.3) —
   `useRole(id)` переводится со старого ad-hoc ключа на
   `roleKeys.detail(id)` для единообразия кеша.
8. **is_system-aware UI: удаление скрыто (unmounted)** (§2.7) —
   системные роли физически не имеют кнопки «Удалить» в DOM, не
   просто disabled. Tooltip на Badge объясняет.
9. **`/api/v1/roles/permissions` — FORBIDDEN в этом батче** (§3 red
   zones) — это Экран 4, scope-control против заползания.
10. **Фикстура ролей консистентна с fixtures/users.ts** (§5.3
    review-checklist) — code-ссылки пользователей на роли должны
    остаться валидными после переписывания фикстур.

---

## История версий

- v1.0 — 2026-04-18 — frontend-director, первая редакция бриф-пакета
  для frontend-head. 10 пунктов скоупа, 5 вопросов Координатору,
  sync-gate после PR#2 merge, 2-дев-задачная декомпозиция. Новые
  UI-паттерны: Sheet + Tooltip. Обязательное применение 4
  стандартов из `departments/frontend.md` v1.1. Консистентность с
  FE-W1-2 Users по code-ссылкам в фикстурах.
