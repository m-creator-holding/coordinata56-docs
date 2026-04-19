# Dev-бриф: батч FE-W1-3 Roles

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-head (L3), статус active-supervising
- **Кому:** frontend-dev (L4)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-3-roles
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-2 Users (закоммичен `bfb7041`) — shared auth готова, frozen

---

## 0. Назначение этого брифа

Этот документ — инструкция для исполнения, не для обсуждения. Все решения уже приняты
и зафиксированы в head-брифе `fe-w1-3-roles.md`. Здесь — только то, что нужно для старта:
что трогать, что не трогать, как делать, по каким тестам принимать.

Обязательное чтение до начала работы:
- `docs/pods/cottage-platform/tasks/fe-w1-3-roles.md` — полный head-бриф (источник истины)
- `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` строки 605–790 (Экран 3)
- `frontend/src/pages/admin/users/*` — структура-эталон 1-в-1
- `frontend/src/shared/api/users.ts` — паттерн api-слоя
- `frontend/src/mocks/handlers/users.ts` + `fixtures/users.ts` — паттерн MSW

---

## 1. Кто исполняет

**frontend-dev** (единственный dev, нет смысла делить задачу #1 и #2 между двумя dev'ами
из-за короткого объёма задачи #1 и жёсткой зависимости #2 от #1).

---

## 2. FILES_ALLOWED и FILES_FORBIDDEN

### FILES_ALLOWED — только эти файлы можно создавать или менять

**Создать:**
```
frontend/src/pages/admin/roles/index.ts
frontend/src/pages/admin/roles/RolesListPage.tsx
frontend/src/pages/admin/roles/RoleDetailsPage.tsx
frontend/src/pages/admin/roles/tabs/RoleGeneralTab.tsx
frontend/src/pages/admin/roles/tabs/RolePermissionsTab.tsx
frontend/src/pages/admin/roles/sheets/RoleFormSheet.tsx
frontend/src/pages/admin/roles/dialogs/DeleteRoleDialog.tsx
frontend/src/shared/validation/roleSchemas.ts
frontend/src/components/ui/sheet.tsx        (через npx shadcn@latest add sheet)
frontend/src/components/ui/tooltip.tsx      (через npx shadcn@latest add tooltip)
frontend/e2e/admin-roles.spec.ts
```

**Расширить:**
```
frontend/src/routes.tsx                              — 2 роута Roles + замена RolesPage
frontend/src/shared/api/roles.ts                     — расширить до CRUD + миграция ключей
frontend/src/mocks/handlers/roles.ts                 — переписать с нуля (CRUD + is_system)
frontend/src/mocks/fixtures/roles.ts                 — переписать (4 системных + 1 custom)
frontend/src/mocks/__tests__/handlers.test.ts        — добавить roles-кейсы
frontend/src/api/generated/schema.d.ts               — только если PR#2 смержен до старта
frontend/package.json                                — shadcn sheet/tooltip как peerDeps
```

**Удалить:**
```
frontend/src/pages/admin/RolesPage.tsx               — старый placeholder
```

### FILES_FORBIDDEN — эти файлы не трогать ни при каких условиях

```
frontend/src/pages/admin/companies/**
frontend/src/pages/admin/users/**
frontend/src/pages/admin/PermissionsPage.tsx
frontend/src/shared/api/companies.ts
frontend/src/shared/api/users.ts
frontend/src/shared/api/auth.ts
frontend/src/shared/auth/**
frontend/src/shared/validation/companySchemas.ts
frontend/src/shared/validation/userSchemas.ts
frontend/src/mocks/handlers/companies.ts
frontend/src/mocks/handlers/users.ts
frontend/src/mocks/handlers/auth.ts
backend/**
docs/adr/**
.github/workflows/**
```

---

## 3. Декомпозиция на 2 дев-задачи

### Дев-задача #1 — API-слой, MSW-моки, Zod-схемы

**Зависимость:** задача #2 не стартует до завершения #1 и чекпоинта Head.

**Что делать:**

**3.1.1. Переписать `frontend/src/mocks/fixtures/roles.ts`**

Текущая фикстура (3 абстрактных роли без `code`/`is_system`/`scope`) не соответствует
PR#2 seed-матрице. Переписать полностью:

```ts
export interface RoleFixture {
  id: number
  code: string
  name: string
  description?: string | null
  scope: 'global' | 'company'
  is_system: boolean
  created_at?: string | null
  updated_at?: string | null
}

const INITIAL_ROLES: RoleFixture[] = [
  { id: 1, code: 'owner', name: 'Владелец',
    description: 'Полный доступ ко всем ресурсам холдинга',
    scope: 'global', is_system: true,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' },
  { id: 2, code: 'accountant', name: 'Бухгалтер',
    description: 'Ввод платёжных данных, согласование расходов, подготовка бухгалтерских документов.',
    scope: 'company', is_system: true,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' },
  { id: 3, code: 'construction_manager', name: 'Прораб',
    description: 'Контроль выполнения строительных работ, управление подрядчиками.',
    scope: 'company', is_system: true,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' },
  { id: 4, code: 'read_only', name: 'Только просмотр',
    description: 'Доступ к просмотру данных без возможности редактирования.',
    scope: 'company', is_system: true,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' },
  { id: 5, code: 'senior_manager', name: 'Старший менеджер',
    description: 'Пользовательская роль для тестирования create/update/delete.',
    scope: 'company', is_system: false,
    created_at: '2026-01-10T00:00:00Z', updated_at: '2026-01-10T00:00:00Z' },
]
```

**Важно:** после переписывания проверить `frontend/src/mocks/fixtures/users.ts` —
пользователи ссылаются на роли по строковому полю (например, `role: 'owner'`).
Убедиться что значения совпадают с новыми `code`-значениями. Если не совпадают —
исправить в users.ts (это не запрещённый файл для этого конкретного hotfix).

**3.1.2. Переписать `frontend/src/mocks/handlers/roles.ts`**

Текущий handler — read-only. Переписать полностью, реализовав in-memory CRUD
по паттерну `handlers/users.ts`. Хранилище — `let roles = makeRoleFixtures()`.
Сброс — при перезагрузке (как в Companies/Users).

Требуемые хэндлеры:

- `GET /api/v1/roles` — с фильтрами `search` (by name/code), `is_system` (bool),
  `scope` (global/company). Сортировка: системные сверху, затем пользовательские,
  внутри каждой группы — алфавитно по `name`. Ответ — envelope
  `{ items, total, offset, limit }` (ADR 0006).

- `GET /api/v1/roles/:id` — возвращает `RoleRead`, 404 если нет.

- `POST /api/v1/roles` — создать роль. Валидировать уникальность `code` → 409
  `DUPLICATE_CODE`. `is_system: false` принудительно. Вернуть 201 + `RoleRead`.

- `PATCH /api/v1/roles/:id` — обновить роль. Если в body передан `code` → 422
  `CODE_IMMUTABLE`. Если `is_system` → игнорировать поле (не менять). Разрешены
  изменения `name`, `description`, `scope` для любых ролей (в том числе системных).
  Вернуть 200 + `RoleRead`.

- `DELETE /api/v1/roles/:id` — если `is_system=true` → 422 `SYSTEM_ROLE_PROTECTED`.
  Иначе — удалить, вернуть 204.

Все ошибки — формат ADR 0005: `{ error: { code, message, details: null } }`.

**3.1.3. Расширить `frontend/src/shared/api/roles.ts`**

Текущий файл содержит заготовку без `code`/`is_system`/`scope` и без mutation-хуков.
Расширить по паттерну `users.ts`:

Тип `RoleRead` — заменить на полный (с `TODO` комментарием до PR#2):
```ts
// TODO: после merge PR#2 — заменить на components['schemas']['RoleRead']
export interface RoleRead {
  id: number
  code: string
  name: string
  description?: string | null
  scope: 'global' | 'company'
  is_system: boolean
  created_at?: string | null
  updated_at?: string | null
}
```

Добавить `RoleFilters`:
```ts
export interface RoleFilters {
  search?: string
  is_system?: boolean | null
  scope?: 'global' | 'company' | null
}
```

Расширить `roleKeys` — добавить `list(filters)` и `details()`:
```ts
export const roleKeys = {
  all: ['roles'] as const,
  lists: () => [...roleKeys.all, 'list'] as const,
  list: (filters: RoleFilters) => [...roleKeys.lists(), filters] as const,
  details: () => [...roleKeys.all, 'detail'] as const,
  detail: (id: number) => [...roleKeys.details(), id] as const,
}
```

Старый `roleKeys.detail(id)` уже использует тот же паттерн `[...roleKeys.all, 'detail', id]`
— проверить, нет ли других мест в коде, где ключ строился иначе (ad-hoc).

Добавить хуки:
- `useRoles(filters?: RoleFilters)` — расширить существующий с фильтрами
- `useRole(id: number)` — мигрировать на `roleKeys.detail(id)` (проверить что ключ не дублируется)
- `useCreateRole()` — `useMutation`, POST, invalidate `roleKeys.lists()`
- `useUpdateRole(id: number)` — `useMutation`, PATCH, invalidate `roleKeys.detail(id)` и `lists()`
- `useDeleteRole()` — `useMutation`, DELETE, invalidate `roleKeys.lists()`

**3.1.4. Создать `frontend/src/shared/validation/roleSchemas.ts`**

Новый файл по паттерну `userSchemas.ts`:

```ts
import { z } from 'zod'

export const codeSchema = z
  .string()
  .min(3, 'Минимум 3 символа')
  .max(64, 'Максимум 64 символа')
  .regex(/^[a-z][a-z0-9_]*$/, 'Только латинские буквы нижнего регистра, цифры и подчёркивание; первый символ — буква')

export const nameSchema = z
  .string()
  .min(1, 'Поле обязательно для заполнения')
  .max(128, 'Максимум 128 символов')

export const descriptionSchema = z
  .string()
  .max(512, 'Максимум 512 символов')
  .nullable()
  .optional()

export const scopeSchema = z.enum(['global', 'company'])

export const roleCreateSchema = z.object({
  code: codeSchema,
  name: nameSchema,
  description: descriptionSchema,
  scope: scopeSchema,
})

export const roleUpdateSchema = roleCreateSchema
  .partial()
  .omit({ code: true })

export type RoleCreateValues = z.infer<typeof roleCreateSchema>
export type RoleUpdateValues = z.infer<typeof roleUpdateSchema>

export const LABELS_ROLE_FIELDS = {
  code: 'Код роли',
  name: 'Отображаемое название',
  description: 'Описание',
  scope: 'Область действия',
} as const

export const SCOPE_OPTIONS = [
  { value: 'company', label: 'Для конкретной компании' },
  { value: 'global', label: 'Глобальная' },
] as const
```

**3.1.5. Добавить тесты в `frontend/src/mocks/__tests__/handlers.test.ts`**

Новые roles-кейсы (добавить, не заменять существующие):
- GET list без фильтров → массив из 4–5 ролей, envelope `{ items, total, offset, limit }`
- POST create с уникальным code → 201
- POST create с `code=owner` (дубль) → 409 `DUPLICATE_CODE`
- POST create с `code=SeniorManager` (нарушение snake_case) — в MSW не валидируется Zod,
  но хэндлер может добавить проверку → 422 `INVALID_CODE`
- PATCH системной роли (менять name/description) → 200 OK
- PATCH с `code` в body → 422 `CODE_IMMUTABLE`
- DELETE системной роли → 422 `SYSTEM_ROLE_PROTECTED`
- DELETE несистемной роли (id=5) → 204

Unit-тест для `codeSchema` (в том же файле или отдельном `roleSchemas.test.ts`):
- `owner` — valid
- `senior_manager` — valid
- `SeniorManager` — invalid (uppercase)
- `1role` — invalid (первый символ цифра)
- `role-name` — invalid (дефис)
- `ab` — invalid (меньше 3 символов)

**Ориентир:** 0.5–0.7 дня.

---

### Дев-задача #2 — UI Roles (страницы + Sheet + Tooltip)

Стартует **после чекпоинта #1** (Head проверяет и даёт добро).

**3.2.1. Установить shadcn-компоненты**

```bash
cd frontend && npx shadcn@latest add sheet tooltip
```

Компоненты появятся в `src/components/ui/sheet.tsx` и `src/components/ui/tooltip.tsx`.
Проверить что `package.json` обновился. Запустить `npm run build` — убедиться что 0 ошибок.

**3.2.2. Обновить `frontend/src/routes.tsx`**

Заменить lazy-импорт `RolesPage` (старый placeholder) на новые страницы:
```ts
const RolesListPage = lazy(() => import('@/pages/admin/roles').then(m => ({ default: m.RolesListPage })))
const RoleDetailsPage = lazy(() => import('@/pages/admin/roles').then(m => ({ default: m.RoleDetailsPage })))
```

Добавить два роута в admin-секцию:
```tsx
<Route path="roles" element={<RolesListPage />} />
<Route path="roles/:id" element={<RoleDetailsPage />} />
```

**3.2.3. Создать структуру `src/pages/admin/roles/`**

```
src/pages/admin/roles/
  index.ts                         — re-export { RolesListPage, RoleDetailsPage }
  RolesListPage.tsx                — список + Sheet создания
  RoleDetailsPage.tsx              — карточка с вкладками + Sheet редактирования
  tabs/RoleGeneralTab.tsx          — вкладка «Общее»
  tabs/RolePermissionsTab.tsx      — вкладка «Права» (только <Link> на Экран 4)
  sheets/RoleFormSheet.tsx         — Sheet create/edit (mode="create"|"edit")
  dialogs/DeleteRoleDialog.tsx     — AlertDialog удаления (только non-system)
```

**Детали реализации:**

**RolesListPage.tsx:**
- `data-testid="page-roles-list"`
- Заголовок «Роли» + кнопка «+ Создать роль» (обёрнута в `<Can action="role.admin">`)
- Sheet открывается через `?create=true` query-param (deep-link) и через кнопку
- Таблица: колонки Название (с Tooltip), Код (monospace), Область, Статус
- 5 состояний: loading (Skeleton-строки + `aria-busy`), empty (иллюстрация + текст),
  error (Banner + «Повторить»), success (строки из данных), dialog-confirm (не на списке)
- Сортировка: системные сверху, внутри — алфавитно (логика на стороне MSW)
- Tooltip на Название: `<Tooltip>...<TooltipContent>{description?.slice(0, 80)}</TooltipContent></Tooltip>`
  — если description null/undefined → Tooltip не рендерится совсем
- Кнопка в строке таблицы — переход на карточку роли через `<Button asChild><Link>`

**RoleDetailsPage.tsx:**
- `data-testid="page-role-details"`
- Хлебная крошка `← Роли` через `<Button asChild><Link to="/admin/roles">`
- Заголовок = `role.name` + Badge статуса + кнопка «Редактировать» (`<Can action="role.admin">`)
- Для системной роли: Badge «Системная» с Tooltip «Системные роли созданы автоматически
  и не могут быть удалены» (`data-testid="badge-role-is-system-{id}"`,
  `data-testid="tooltip-role-system"`)
- Для несистемной роли: кнопка «Удалить» (`data-testid="btn-role-delete"`)
- Вкладки через `?tab=general` / `?tab=permissions` (как Companies)
- Кнопка «Редактировать» открывает Sheet редактирования inline

**RoleFormSheet.tsx:**
- Props: `mode: 'create' | 'edit'`, `roleId?: number` (для edit — prefetch данных)
- `data-testid="sheet-role-form"`, `aria-labelledby="sheet-role-form-title"`
- RHF + `zodResolver(mode === 'create' ? roleCreateSchema : roleUpdateSchema)`
- Поля (`data-testid="field-role-{field}"`):
  - `code` — Input, disabled если `mode === 'edit'`, help-текст «Код роли нельзя изменять
    после создания»; при создании — активен
  - `name` — Input, обязательное
  - `description` — Textarea (3 строки), необязательное, счётчик символов (до 512)
  - `scope` — Select (Controlled с `value=`, не `defaultValue=`);
    опции из `SCOPE_OPTIONS`; disabled если `mode === 'edit' && role.is_system`
    (системные роли имеют фиксированный scope — US-03 сценарий 3.3)
- Кнопки: «Отменить» (закрывает Sheet без сохранения) и
  «Создать роль» / «Сохранить изменения» (`data-testid="btn-role-save"`)
- После успешного submit: Sheet закрывается, Toast «Роль создана» / «Изменения сохранены»
- После 409 `DUPLICATE_CODE`: `setError('code', { message: 'Роль с таким кодом уже существует' })`
- Sheet остаётся открытым при ошибках

**RoleGeneralTab.tsx:**
- `data-testid="role-general-tab"`
- Поля readonly: Название, Код, Описание, Область, Статус (Badge)
- Код — monospace

**RolePermissionsTab.tsx:**
- `data-testid="role-permissions-tab"`
- Текст «Управление правами роли "{{name}}". Перейдите в Матрицу прав для редактирования разрешений.»
- Кнопка «Открыть матрицу прав для этой роли» — `<Button asChild><Link to={/admin/permissions?role=${role.code}}>`
- `data-testid="btn-role-open-permissions"`
- Никаких API-запросов к permissions в этом батче

**DeleteRoleDialog.tsx:**
- `data-testid="dialog-delete-role"`, destructive-вариант AlertDialog
- Только для ролей с `is_system=false` (UI не рендерит кнопку «Удалить» у системных)
- После подтверждения: `useDeleteRole()` → 204 → редирект на `/admin/roles` + Toast «Роль удалена»
- После 422 `SYSTEM_ROLE_PROTECTED` (bypass через devtools): Toast с ошибкой

**3.2.4. data-testid матрица (обязательная)**

Реализовать все testid из head-брифа §6.2:
```
page-roles-list, page-role-details
roles-table, role-general-tab, role-permissions-tab
sheet-role-form, sheet-role-form-title
field-role-code, field-role-name, field-role-description, field-role-scope
btn-role-create, btn-role-save, btn-role-edit, btn-role-delete, btn-role-open-permissions
dialog-delete-role
row-role-{id}
badge-role-is-system-{id}, badge-role-scope-{id}
tooltip-role-description-{id}, tooltip-role-system
```

**3.2.5. ARIA (WCAG 2.2 AA)**

- Кнопки-иконки → `aria-label`
- Таблица → `aria-label="Список ролей холдинга"`
- Sheet → `role="dialog"` + `aria-labelledby="sheet-role-form-title"` (Radix даёт)
- Tooltip → `role="tooltip"`, связан через `aria-describedby` (Radix даёт)
- Badge «Системная» → `aria-label="Системная роль"`
- Shimmer-строки → `aria-busy="true"` на таблице

**3.2.6. Playwright E2E: `frontend/e2e/admin-roles.spec.ts`**

Реализовать все 11 тестов (10 обязательных + 1 опциональный) — см. раздел 4 этого брифа.

**Ориентир:** 1–1.3 дня.

---

## 4. E2E-сценарии: 11 тестов Given/When/Then

Файл: `frontend/e2e/admin-roles.spec.ts`. Все тесты против MSW-моков.

**E2E-1: Список ролей отображается**
```
Given  пользователь авторизован как admin@example.com с правом role.admin
When   открывает /admin/roles
Then   видна таблица с data-testid="roles-table"
And    в таблице 4+ строки (row-role-1, row-role-2, row-role-3, row-role-4)
And    у строк owner/accountant/construction_manager/read_only — Badge «Системная»
       (badge-role-is-system-{id} присутствует в DOM)
And    колонки: Название, Код, Область, Статус
```

**E2E-2: Tooltip на названии роли**
```
Given  открыт /admin/roles, данные загружены
When   наводит курсор на название «Бухгалтер» (row-role-2)
Then   появляется Tooltip (tooltip-role-description-2) с текстом
       первых 80 символов описания роли «Бухгалтер»
```

**E2E-3: Открытие карточки роли**
```
Given  открыт /admin/roles
When   кликает по строке «Бухгалтер» (row-role-2)
Then   переход на /admin/roles/2
And    URL содержит ?tab=general (дефолтная вкладка)
And    видны поля Код (accountant), Название, Описание, Область, Статус
And    кнопка btn-role-edit присутствует в DOM (есть право role.admin)
```

**E2E-4: Создание пользовательской роли — happy path**
```
Given  открыт /admin/roles
When   кликает btn-role-create
And    открывается Sheet (sheet-role-form)
And    вводит code="project_coordinator", name="Координатор проекта",
       description="Управление проектами", scope="company"
And    нажимает btn-role-save
Then   Sheet закрывается
And    Toast «Роль создана» отображается
And    новая строка с «Координатор проекта» появляется в таблице
And    URL остаётся /admin/roles
```

**E2E-5: Валидация code — нарушение snake_case**
```
Given  Sheet создания открыт (sheet-role-form)
When   вводит code="ProjectCoordinator" (camelCase) и нажимает btn-role-save
Then   под field-role-code отображается ошибка валидации про snake_case
And    Sheet не закрывается
And    POST-запрос не отправляется (нет network activity)
```

**E2E-6: Дублирующий code при создании**
```
Given  Sheet создания открыт
When   вводит code="owner" (уже существует) и нажимает btn-role-save
Then   Sheet остаётся открытым
And    под field-role-code отображается «Роль с таким кодом уже существует»
       (серверная ошибка 409, прокинута через RHF setError)
```

**E2E-7: Редактирование роли — happy path**
```
Given  открыта карточка роли owner (/admin/roles/1)
When   кликает btn-role-edit
And    открывается Sheet с предзаполненными значениями (name="Владелец")
And    меняет description на "Обновлённое описание"
And    нажимает btn-role-save
Then   Sheet закрывается
And    Toast «Изменения сохранены» отображается
And    обновлённое описание видно в карточке (role-general-tab)
```

**E2E-8: Поле code в Sheet редактирования — disabled**
```
Given  Sheet редактирования открыт (для любой роли)
When   находит field-role-code
Then   атрибут disabled присутствует (input.disabled === true)
And    рядом есть help-текст «Код роли нельзя изменять после создания»
```

**E2E-9: Удаление системной роли — кнопка отсутствует**
```
Given  открыта карточка системной роли owner (/admin/roles/1, is_system=true)
When   страница отрендерена
Then   btn-role-delete отсутствует в DOM (не disabled, а не существует)
And    badge-role-is-system-1 присутствует
And    Tooltip tooltip-role-system содержит текст
       «Системные роли созданы автоматически и не могут быть удалены»
```

**E2E-10: Permission guard без role.admin**
```
Given  авторизован пользователь без права role.admin
When   открывает /admin/roles
Then   таблица ролей видна (read доступен)
And    btn-role-create отсутствует в DOM
And    btn-role-edit отсутствует в DOM (в строках и карточках)
And    открытие /?create=true не открывает Sheet (Sheet не рендерится)
```

**E2E-11 (опциональный): Навигация в матрицу прав**
```
Given  открыта карточка роли accountant (/admin/roles/2)
And    активна вкладка «Права» (?tab=permissions)
When   кликает btn-role-open-permissions
Then   браузер переходит на /admin/permissions?role=accountant
       (Экран 4 — placeholder, тест проверяет только URL)
```

---

## 5. Shared-компоненты переиспользуемые (frozen из FE-W1-2)

Использовать без изменений:

| Компонент / хук | Откуда | Что делает |
|---|---|---|
| `<Can action="role.admin">` | `frontend/src/shared/auth/Can.tsx` | Скрывает UI-элементы без права |
| `usePermissions()` | `frontend/src/shared/auth/usePermissions.ts` | Программная проверка прав |
| `ConsentGuard` | `frontend/src/shared/auth/ConsentGuard.tsx` | Блокирует навигацию при `consent_required=true` |
| `AuthProvider` | `frontend/src/shared/auth/AuthProvider.tsx` | JWT контекст |
| `apiClient` | `frontend/src/lib/api.ts` | HTTP-клиент с базовым URL |

**Запрещено:** создавать новые файлы в `shared/auth/`, расширять `AuthUser`, менять логику хуков.
При обнаружении необходимости расширения — **эскалация Head немедленно**, не самостоятельно.

---

## 6. Стандарты (4 обязательных из departments/frontend.md v1.1)

1. **Query Key Factory** — `roleKeys` фабрика обязательна для всех queries и invalidations.
   Нет ни одного места в коде, где ключ строится вручную (например, `['roles', 'detail', id]`).

2. **Controlled Select + RHF** — Select «Область действия» использует `value=` с `Controller`,
   не `defaultValue=`. Паттерн из `userSchemas.ts` / компонентов Users.

3. **`<Button asChild><Link>`** — все навигационные действия (назад, открыть матрицу прав,
   перейти в карточку) — через `<Button asChild><Link to="...">`, не `onClick={navigate}`.

4. **5 состояний UI** — loading, empty, error, success, dialog-confirm — на каждом экране
   (RolesListPage и RoleDetailsPage). Без исключений.

---

## 7. DoD батча (Definition of Done)

Перед передачей на чекпоинт Head — убедиться самостоятельно:

**Функциональность:**
- [ ] `/admin/roles` открывается, таблица с данными из MSW
- [ ] `/admin/roles/:id?tab=general` открывается, карточка с полями
- [ ] `/admin/roles/:id?tab=permissions` открывается, вкладка «Права» с кнопкой перехода
- [ ] Deep-link `/admin/roles?create=true` открывает Sheet создания
- [ ] Sheet создания: форма создаёт роль, taблица обновляется
- [ ] Sheet редактирования: code disabled, name/description/scope редактируемы
- [ ] Системная роль: нет кнопки «Удалить», Tooltip на Badge
- [ ] Несистемная роль: кнопка «Удалить» есть, Dialog работает
- [ ] `<Can action="role.admin">` скрывает кнопки при отсутствии права

**Код:**
- [ ] Структура `src/pages/admin/roles/` соответствует §2 head-брифа
- [ ] `roleKeys` factory используется везде, нет ad-hoc ключей
- [ ] `roleSchemas.ts` содержит `codeSchema` с regex `/^[a-z][a-z0-9_]*$/`
- [ ] Select «Область» использует `value=` с `Controller`
- [ ] Навигационные кнопки через `<Button asChild><Link>`
- [ ] Нет изменений в FILES_FORBIDDEN
- [ ] `shared/auth/` не изменён

**Тесты:**
- [ ] `npm run lint && npm run typecheck && npm run build` — 0 warnings, 0 errors
- [ ] Все 10+ E2E тестов проходят: `npm run test:e2e admin-roles.spec.ts`
- [ ] Unit-тесты `codeSchema` — все кейсы green
- [ ] MSW-тесты handlers.test.ts — все новые кейсы green

**Данные:**
- [ ] Фикстуры: 4 системных роли с корректными `code`/`scope`/`is_system`
- [ ] Консистентность: `fixtures/users.ts` — role-ссылки не сломаны
- [ ] Envelope `{ items, total, offset, limit }` в GET list

**Доступность:**
- [ ] data-testid матрица полная (все из §6.2 head-брифа)
- [ ] `aria-label` на всех кнопках-иконках
- [ ] Badge «Системная» с `aria-label="Системная роль"`
- [ ] Bundle delta ≤ +20 KB gzip (Sheet + Tooltip ≈ 5–8 KB)

---

## 8. Чекпоинты

**Чекпоинт #1 — после завершения дев-задачи #1:**

Dev возвращает Head:
1. Список изменённых файлов (fixtures, handlers, api/roles.ts, roleSchemas.ts, handlers.test.ts)
2. Результат `npm run lint && npm run typecheck` — должно быть 0 ошибок
3. Результат `npm run test` (unit-тесты handlers + roleSchemas) — all green
4. Явный ответ на open items раздела 9

Head проверяет по чек-листу §5.3 head-брифа (API-часть) и даёт добро на задачу #2.

**Чекпоинт #2 — финальная сдача (после завершения дев-задачи #2):**

Dev возвращает Head:
1. Полный список созданных/изменённых файлов
2. `npm run lint && npm run typecheck && npm run build` — 0 warnings
3. `npm run test:e2e admin-roles.spec.ts` — все 10+ тестов green
4. Bundle delta (gzip)

Head проводит финальное ревью по полному чек-листу §5.3 head-брифа.
При P0/P1 — возврат на исправление. При OK — передача Директору.

---

## 9. Open items — ответить до начала кода

Dev обязан уточнить эти пункты у Head **до старта задачи #1**:

**OI-1.** Проверить текущее состояние `frontend/src/mocks/fixtures/users.ts`:
какое поле в user-фикстурах ссылается на роль (строковый code или числовой id)?
Если строковый `role: 'owner' | ...` — при переписывании fixtures/roles.ts
консистентность сохранится автоматически. Если числовой `role_id: 1` — нужна
проверка, что id 1–4 совпадают с новыми фикстурами. Прочитать файл, сообщить Head.

**OI-2.** Проверить, мерджен ли PR#2 на момент старта:
- `git log --oneline | grep PR#2` или проверить наличие `RoleRead` в `schema.d.ts`
- Если смержен — запустить `npm run codegen` и использовать сгенерированные типы
- Если не смержен — работать с ручными типами (вариант A из head-брифа §8 Вопрос 1)
- Сообщить Head результат

**OI-3.** Подтвердить что `npx shadcn@latest add sheet tooltip` прошло без конфликтов
(shadcn иногда предлагает перезаписать существующие файлы `utils.ts` и `button.tsx`).
Запустить и сообщить что именно было установлено/обновлено перед тем, как идти дальше.

---

## 10. Решения, принятые Координатором (закрытые вопросы)

Эти решения окончательны, dev не пересматривает:

- **OQ-1 (scope при редактировании):** scope НЕ меняется при редактировании — фиксируется
  при создании аналогично `code`. Select «Область» в Sheet редактирования — disabled для всех ролей.
- **OQ-2 (сортировка):** системные сверху, пользовательские ниже; внутри каждой группы —
  алфавитно по `name`.
- **Вопрос 3 (редактирование системных ролей):** разрешено менять `name` и `description`;
  `code` и `is_system` — immutable; `scope` — disabled при редактировании (решение OQ-1 выше).
- **Вопрос 4 (scope enum):** жёстко 2 значения `global | company`. YAGNI.
- **Вопрос 5 (вкладка «Права»):** присутствует, содержит только `<Link>` на Экран 4.

---

## История версий

- v1.0 — 2026-04-18 — frontend-head, первая редакция dev-брифа на основе head-брифа
  fe-w1-3-roles.md v1.0. Декомпозиция на 2 задачи, 11 E2E тестов, FILES_ALLOWED/FORBIDDEN,
  DoD, 3 open items для dev, решения Координатора по OQ-1/OQ-2.
