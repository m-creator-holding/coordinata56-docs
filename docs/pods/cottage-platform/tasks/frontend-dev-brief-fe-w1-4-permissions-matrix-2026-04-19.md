# Dev-бриф: батч FE-W1-4 Permissions Matrix

- **Версия:** 1.0
- **Дата:** 2026-04-19
- **От:** frontend-head (L3), статус active-supervising
- **Кому:** frontend-dev (L4)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-4-permissions-matrix
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-3 Roles — должен быть принят Директором ДО старта дев-задачи #1

---

## 0. Назначение этого брифа

Этот документ — инструкция для исполнения, не для обсуждения. Все архитектурные решения
зафиксированы в head-брифе `fe-w1-4-permissions-matrix.md`. Здесь — только то, что нужно
для старта: что трогать, что не трогать, как делать, по каким тестам принимать.

Обязательное чтение до начала работы:
- `docs/pods/cottage-platform/tasks/fe-w1-4-permissions-matrix.md` — полный head-бриф (источник истины)
- `docs/pods/cottage-platform/design/admin-ui-wireframes-m-os-1-1b-2026-04-18.md` §2.2 — матрица с деревом групп, 4 группы-папки, 7 действий
- `frontend/src/pages/admin/roles/*` — структура-эталон 1-в-1
- `frontend/src/shared/api/roles.ts` — паттерн api-слоя
- `frontend/src/mocks/handlers/roles.ts` + `fixtures/roles.ts` — паттерн MSW

---

## 1. Кто исполняет

**frontend-dev** (один исполнитель, последовательно). Задача #1 блокирует задачу #2 — UI
нельзя строить без API-слоя и MSW-моков. Параллельная работа двух dev возможна при Фазе 4+,
сейчас — не нужна.

---

## 2. FILES_ALLOWED и FILES_FORBIDDEN

### FILES_ALLOWED — только эти файлы можно создавать или менять

**Создать:**
```
frontend/src/pages/admin/permissions/index.ts
frontend/src/pages/admin/permissions/PermissionsMatrixPage.tsx
frontend/src/pages/admin/permissions/components/PermissionsMatrixTable.tsx
frontend/src/pages/admin/permissions/components/PermissionsMatrixHeader.tsx
frontend/src/pages/admin/permissions/components/PermissionCell.tsx
frontend/src/pages/admin/permissions/components/BulkRowCheckbox.tsx
frontend/src/pages/admin/permissions/components/ResourceTabs.tsx
frontend/src/pages/admin/permissions/components/UnsavedChangesGuard.tsx
frontend/src/pages/admin/permissions/components/PrefilteredBanner.tsx
frontend/src/pages/admin/permissions/components/EditModeBanner.tsx
frontend/src/pages/admin/permissions/dialogs/RevokePermissionDialog.tsx
frontend/src/pages/admin/permissions/drawers/RolePermissionsHistoryDrawer.tsx
frontend/src/pages/admin/permissions/lib/csvExport.ts
frontend/src/pages/admin/permissions/lib/matrixState.ts
frontend/src/shared/api/permissions.ts
frontend/src/shared/api/rolePermissions.ts
frontend/src/shared/validation/rolePermissionSchemas.ts
frontend/src/components/ui/checkbox.tsx      (через npx shadcn@latest add checkbox)
frontend/src/mocks/handlers/permissions.ts
frontend/src/mocks/handlers/role_permissions.ts
frontend/src/mocks/fixtures/permissions.ts
frontend/src/mocks/fixtures/role_permissions.ts
frontend/e2e/admin-permissions.spec.ts
```

**Расширить:**
```
frontend/src/routes.tsx                              — добавить /admin/permissions
frontend/src/mocks/fixtures/roles.ts                 — добавить поле active_users_count
frontend/src/mocks/__tests__/handlers.test.ts        — +8 новых кейсов
```

**Удалить:**
```
frontend/src/pages/admin/PermissionsPage.tsx         — старый placeholder
```

### FILES_FORBIDDEN — не трогать ни при каких условиях

```
frontend/src/pages/admin/companies/**
frontend/src/pages/admin/users/**
frontend/src/pages/admin/roles/**
frontend/src/shared/api/companies.ts
frontend/src/shared/api/users.ts
frontend/src/shared/api/roles.ts           (только read-only импорты из этого файла допустимы)
frontend/src/shared/api/auth.ts
frontend/src/shared/auth/**
frontend/src/mocks/handlers/companies.ts
frontend/src/mocks/handlers/users.ts
frontend/src/mocks/handlers/roles.ts       (добавлять actor/history-handlers только в role_permissions.ts)
frontend/src/mocks/handlers/auth.ts
backend/**
docs/adr/**
.github/workflows/**
```

---

## 3. Декомпозиция: 2 дев-задачи

### Дев-задача A — API-слой, MSW-моки, Zod-схемы

**Зависимость:** задача B не стартует до завершения A и чекпоинта Head.
**Ориентир:** 0.7–1.0 дня.

---

#### A.1. Расширить `frontend/src/mocks/fixtures/roles.ts`

Добавить поле `active_users_count` к каждой фикстуре. Значение вычислять из
`fixtures/users.ts` — подсчёт пользователей с `is_active=true` и совпадающим role_id.
Если users-фикстура не содержит достаточно данных — задать статичные значения:

```ts
// Дополнение к существующей RoleFixture
active_users_count: number

// Значения по фикстурам
// owner (id=1): 1
// accountant (id=2): 3
// construction_manager (id=3): 2
// read_only (id=4): 0
// senior_manager (id=5): 1
```

Важно: менять структуру существующих ролей нельзя — только добавить поле.

---

#### A.2. Создать `frontend/src/mocks/fixtures/permissions.ts`

Фикстура справочника прав — минимум 20 permissions, 4 группы × 5+ сущностей × 7 действий
(не все комбинации обязательны — матрица разреженная).

Структура одного permission:
```ts
export interface PermissionFixture {
  id: number
  resource: string       // группа: 'finance' | 'hr' | 'construction' | 'settings'
  entity: string         // сущность: 'payment' | 'contract' | ...
  action: 'create' | 'read' | 'update' | 'delete' | 'export' | 'approve' | 'archive'
  code: string           // уникальный: 'payment.read', 'contract.approve', ...
  description: string
}
```

Минимальный набор (покрыть все 4 группы wireframe §2.2):

| resource | entity | actions (задать хотя бы для каждой) |
|---|---|---|
| finance | payment | read, create, export |
| finance | contract | read, create, export, approve |
| finance | invoice | read, export |
| finance | budget_plan | read |
| hr | user | read, create, update |
| hr | role | read |
| hr | permission | read |
| construction | house | read, update, export |
| construction | stage | read, create, update, approve |
| construction | contractor | read |
| settings | company | read |
| settings | company_settings | read |

Итого: ~21 permissions. Каждый permission — уникальный `id` начиная с 1.

---

#### A.3. Создать `frontend/src/mocks/fixtures/role_permissions.ts`

Матрица «роль × permission» — для 5 ролей из `fixtures/roles.ts`.

Структура:
```ts
export interface RolePermissionFixture {
  role_id: number
  permission_id: number
  allowed: boolean
}
```

Распределение:
- **owner (id=1):** все permissions allowed=true (системная роль, lock-иконка в UI)
- **accountant (id=2):** finance.*.read, finance.*.export, construction.house.read,
  construction.stage.read, construction.contractor.read — остальные false
- **construction_manager (id=3):** construction.*.read, construction.stage.create,
  construction.stage.update, construction.stage.approve, finance.contract.read — остальные false
- **read_only (id=4):** только *.read — все read=true, остальные false
- **senior_manager (id=5):** finance.*.read, finance.contract.create, finance.contract.approve,
  construction.*.read — это пользовательская роль, доступна для изменений в UI

Фикстура возвращает только пары с `allowed=true` (плоский список).

---

#### A.4. Создать `frontend/src/mocks/handlers/permissions.ts`

MSW-хэндлер справочника permissions. In-memory (не мутируется):

```
GET /api/v1/permissions
  Query: resource?: string (фильтр по полю resource)
  Response: { items: PermissionRead[], total, offset, limit }
  Логика: if resource → filter by resource; применить offset/limit
```

Ошибки — строго по ADR 0005: `{ error: { code, message, details } }`.

---

#### A.5. Создать `frontend/src/mocks/handlers/role_permissions.ts`

In-memory CRUD с накоплением изменений:

```
GET /api/v1/role_permissions
  Response: { items: RolePermissionRead[], total, offset, limit }
  Логика: отдаёт все пары из хранилища (инициализируется из fixtures/role_permissions.ts)

GET /api/v1/roles/:id/permissions/history
  Query: offset?, limit? (default 50, max 200)
  Response: { items: PermissionHistoryEntry[], total, offset, limit }
  Логика: in-memory массив history_log (заполнить 3–5 статичными записями для accountant
  и senior_manager при инициализации); для ролей без истории — items=[], total=0
  Структура entry:
    { id, role_id, permission_id, permission_code, action: 'granted'|'revoked',
      actor_user_id, actor_user_name, created_at }

PATCH /api/v1/roles/permissions
  Body: { changes: [{ role_id, permission_id, allowed }, ...] }
  Логика 1: проверить все role_id на is_system через fixtures/roles.ts;
    если хоть один is_system=true → 403 { error: { code: 'SYSTEM_ROLE_IMMUTABLE',
    message: 'Системные роли нельзя изменять через UI',
    details: { role_ids: [...системные id...] } } }
  Логика 2: если все non-system → применить changes к in-memory хранилищу;
    добавить записи в history_log; вернуть 200 { items: [...обновлённая матрица...], total, offset, limit }

DELETE /api/v1/role_permissions
  Body: { role_id, permission_id }
  Логика: если role is_system → 403 SYSTEM_ROLE_IMMUTABLE;
    иначе удалить пару, вернуть 204 (empty body)
```

---

#### A.6. Создать `frontend/src/shared/api/permissions.ts`

Типы и хуки:

```ts
// Типы
export interface PermissionRead {
  id: number
  resource: string
  entity: string
  action: string
  code: string
  description: string
}

export interface PermissionFilters {
  resource?: string | null
}

// Query Key Factory
export const permissionKeys = {
  all: ['permissions'] as const,
  lists: () => [...permissionKeys.all, 'list'] as const,
  list: (filters: PermissionFilters) => [...permissionKeys.lists(), filters] as const,
}

// Хук
// ВАЖНО: назвать именно usePermissionsCatalog() — НЕ usePermissions()
// (usePermissions уже занят auth-хуком из shared/auth — конфликт имён)
export function usePermissionsCatalog(filters?: PermissionFilters)
```

---

#### A.7. Создать `frontend/src/shared/api/rolePermissions.ts`

```ts
// Типы
export interface RolePermissionRead {
  role_id: number
  permission_id: number
  allowed: boolean
}

export interface BatchChange {
  role_id: number
  permission_id: number
  allowed: boolean
}

export interface PermissionHistoryEntry {
  id: number
  role_id: number
  permission_id: number
  permission_code: string
  action: 'granted' | 'revoked'
  actor_user_id: number
  actor_user_name: string
  created_at: string
}

// Query Key Factory
export const rolePermissionKeys = {
  all: ['rolePermissions'] as const,
  matrix: () => [...rolePermissionKeys.all, 'matrix'] as const,
  history: (roleId: number) => [...rolePermissionKeys.all, 'history', roleId] as const,
}

// Хуки
export function useRolePermissionsMatrix()          // GET /api/v1/role_permissions
export function useBatchUpdateRolePermissions()     // PATCH /api/v1/roles/permissions
export function useRevokeRolePermission()           // DELETE /api/v1/role_permissions
export function useRolePermissionsHistory(          // GET /api/v1/roles/:id/permissions/history
  roleId: number | null,
  options?: { enabled?: boolean }
)
```

---

#### A.8. Создать `frontend/src/shared/validation/rolePermissionSchemas.ts`

```ts
import { z } from 'zod'

export const batchChangeSchema = z.object({
  role_id: z.number().int().positive(),
  permission_id: z.number().int().positive(),
  allowed: z.boolean(),
})

export const batchUpdateSchema = z.object({
  changes: z.array(batchChangeSchema).min(1, 'Нет изменений для сохранения'),
})

export const revokePermissionSchema = z.object({
  role_id: z.number().int().positive(),
  permission_id: z.number().int().positive(),
})

export type BatchChange = z.infer<typeof batchChangeSchema>
export type BatchUpdate = z.infer<typeof batchUpdateSchema>
export type RevokePermission = z.infer<typeof revokePermissionSchema>
```

---

#### A.9. Добавить тесты в `frontend/src/mocks/__tests__/handlers.test.ts`

Добавить 8 новых кейсов (не заменять существующие):

1. `GET /api/v1/permissions` без фильтра → envelope `{ items, total, offset, limit }`, items ≥ 21
2. `GET /api/v1/permissions?resource=finance` → только items с resource=finance
3. `GET /api/v1/role_permissions` → envelope, items для всех 5 ролей
4. `PATCH /api/v1/roles/permissions` happy path (non-system role) → 200, matrix обновлена
5. `PATCH /api/v1/roles/permissions` с role_id системной роли (id=1) → 403 `SYSTEM_ROLE_IMMUTABLE`
6. `PATCH /api/v1/roles/permissions` batch с одной системной и одной не-системной → 403 (весь batch)
7. `DELETE /api/v1/role_permissions` non-system → 204
8. `DELETE /api/v1/role_permissions` system role → 403 `SYSTEM_ROLE_IMMUTABLE`

Unit-тесты для `rolePermissionSchemas.ts` (отдельный файл
`frontend/src/shared/validation/__tests__/rolePermissionSchemas.test.ts`):
- `batchChangeSchema` — valid при корректных полях
- `batchChangeSchema` — invalid при отрицательном role_id
- `batchUpdateSchema` — invalid при пустом массиве changes
- `revokePermissionSchema` — valid / invalid

---

#### A.10. Чекпоинт A — что вернуть Head

1. Список созданных/изменённых файлов
2. `npm run lint && npm run typecheck` — 0 ошибок
3. `npm run test` (unit MSW + schema) — all green
4. Ответы на open items из раздела 8

---

### Дев-задача B — UI Permissions Matrix + CSV + E2E

Стартует **после чекпоинта A** (Head проверяет и даёт добро).
**Ориентир:** 1.3–1.7 дня.

---

#### B.1. Установить shadcn Checkbox

```bash
cd frontend && npx shadcn@latest add checkbox
```

Сообщить Head что именно было установлено и нет ли конфликтов с `utils.ts` / `button.tsx`.
Запустить `npm run build` — 0 ошибок.

---

#### B.2. Обновить `frontend/src/routes.tsx`

```ts
const PermissionsMatrixPage = lazy(() =>
  import('@/pages/admin/permissions').then(m => ({ default: m.PermissionsMatrixPage }))
)
```

Добавить роут в admin-секцию:
```tsx
<Route path="permissions" element={<PermissionsMatrixPage />} />
```

Удалить lazy-импорт старого `PermissionsPage` (placeholder).

---

#### B.3. Структура `src/pages/admin/permissions/`

```
src/pages/admin/permissions/
  index.ts                                  — re-export { PermissionsMatrixPage }
  PermissionsMatrixPage.tsx                 — корневая страница
  components/
    PermissionsMatrixTable.tsx              — таблица матрицы (tree + cells)
    PermissionsMatrixHeader.tsx             — строка-заголовок с bulk-кнопками колонок
    PermissionCell.tsx                      — одна ячейка (checkbox или hover-revoke)
    BulkRowCheckbox.tsx                     — bulk-чекбокс для строки
    ResourceTabs.tsx                        — вкладки групп/ресурсов
    UnsavedChangesGuard.tsx                 — AlertDialog при смене вкладки с unsaved
    PrefilteredBanner.tsx                   — Banner «Показаны права роли X. [Сбросить]»
    EditModeBanner.tsx                      — Alert «Режим редактирования»
  dialogs/
    RevokePermissionDialog.tsx              — AlertDialog одиночного отзыва (view-mode)
  drawers/
    RolePermissionsHistoryDrawer.tsx        — Sheet-based drawer истории
  lib/
    csvExport.ts                            — утилита генерации CSV
    matrixState.ts                          — reducer для unsaved changes state
```

---

#### B.4. Детали реализации — matrixState.ts

Хранит pending-изменения в Map. Reducer:

```ts
// Тип состояния
type CellKey = `${number}_${number}`   // `${role_id}_${permission_id}`
type ChangeType = 'added' | 'removed'

interface MatrixState {
  pendingChanges: Map<CellKey, ChangeType>
  isDirty: boolean
}

// Actions
type MatrixAction =
  | { type: 'TOGGLE_CELL'; roleId: number; permissionId: number; currentValue: boolean }
  | { type: 'BULK_ROW'; roleIds: number[]; permissionId: number; targetValue: boolean }
  | { type: 'BULK_COLUMN'; roleId: number; permissionIds: number[]; targetValue: boolean }
  | { type: 'RESET' }
  | { type: 'COMMIT' }
```

Логика TOGGLE_CELL: если ячейка была `true` → добавляем 'removed'; если была `false` →
добавляем 'added'. Если повторный клик возвращает к исходному значению — убираем из Map
(изменение отменено).

`isDirty = pendingChanges.size > 0`.

---

#### B.5. Детали реализации — PermissionsMatrixPage.tsx

`data-testid="page-permissions-matrix"`

**URL-параметры:**
- `?role=<code>` — pre-filter: показать колонку только для этой роли (banner + highlight)
- `?resource=<name>` — активная вкладка ресурса (обновляется при клике по вкладкам)

**Состояния страницы:**
1. loading — Skeleton-строки в таблице + `aria-busy="true"` на таблице
2. empty — «Справочник прав пуст» + иконка
3. error — Banner «Ошибка загрузки» + кнопка «Повторить»
4. success (view-mode) — полная матрица, hover-кнопки на ячейках пользовательских ролей
5. edit-mode — чекбоксы активны, EditModeBanner сверху, кнопки «Сохранить»/«Отменить»

**Toolbar (в заголовке страницы):**
- `RoleFilterSelect` (Combobox с поиском) — `data-testid="select-role-filter"`
- `EditModeToggleButton`:
  - view-mode: кнопка «Редактировать» (`data-testid="btn-edit-mode-enter"`)
  - edit-mode: кнопки «Сохранить» (`data-testid="btn-save"`) и «Отменить» (`data-testid="btn-cancel"`)
  - оба скрыты через `<Can action="permission.admin">`
- `HistoryButton` (`data-testid="btn-history"`) — видна только при наличии ?role-фильтра
- `ExportCsvButton` (`data-testid="btn-export-csv"`) — `<Can action="permission.admin">`

**Pre-filter banner** (`PrefilteredBanner`):
```
«Показаны права роли "Старший менеджер". [Сбросить]»
data-testid="banner-prefilter"
```

**Edit mode banner** (`EditModeBanner`):
```
Alert (variant=warning): «Режим редактирования активен. Изменения будут применены после нажатия «Сохранить».»
data-testid="banner-edit-mode"
```

---

#### B.6. Детали реализации — PermissionsMatrixTable.tsx

Layout: вертикальная таблица где:
- Строки — permission (entity × action)
- Столбцы — роли

Группировка строк: по 4 группам из wireframe §2.2 (Финансы / Кадры / Стройка / Настройки).
Каждая группа — Accordion/Collapsible с заголовком, кнопкой bulk «выбрать всю группу» и бэйджем.

Состояния expand/collapse — в localStorage (`pm_group_state`).

**Структура колонок:**
```
Первая колонка: «Объект» + «Действие» (2 sub-cells или merged)
Последующие колонки: по одной на роль
```

**Системные роли** (is_system=true):
- В заголовке колонки: Lock-иконка (`data-testid="icon-lock-{role_id}"`) + Tooltip
  «Права системной роли зафиксированы. Редактирование через UI недоступно»
- Все ячейки этой колонки — disabled в edit-mode
- Bulk-чекбокс колонки — disabled
- В view-mode hover-кнопка «Отозвать» не появляется

**Пользовательские роли** в view-mode:
- При hover на заполненную ячейку (allowed=true) → появляется X-кнопка
  (`data-testid="btn-revoke-cell-{role_id}-{permission_id}"`)
- Клик → открывает `RevokePermissionDialog`

**Edit-mode:**
- Все ячейки некоторых ролей — Checkbox, управляемый через matrixState
- Pending changes визуально отражаются: ячейка 'added' — зелёная рамка, 'removed' — красная

---

#### B.7. Детали реализации — PermissionCell.tsx

Props: `roleId`, `permissionId`, `currentValue: boolean`, `isSystemRole: boolean`,
`isEditMode: boolean`, `pendingChange?: 'added' | 'removed'`

View-mode + non-system:
- if `currentValue === true`: `<div>✓</div>` + hover → X-кнопка видна
- if `currentValue === false`: пустая ячейка, без hover-кнопки

Edit-mode + non-system:
- `<Checkbox checked={effectiveValue} onCheckedChange={...} data-testid="cell-{roleId}-{permissionId}" />`
- `effectiveValue` = применить pendingChange поверх currentValue

System role (любой режим):
- Чекбокс disabled + Lock-визуализация (без текстовой иконки в каждой ячейке — только в шапке колонки)
- `aria-disabled="true"`, `data-testid="cell-{roleId}-{permissionId}-locked"`

---

#### B.8. Детали реализации — BulkRowCheckbox.tsx

Только в edit-mode. Находится в первой колонке строки (рядом с названием).

Логика:
- Если выбрана одна конкретная роль (RoleFilterSelect) → bulk относится к ней
- Если роль не выбрана → bulk-чекбокс не рендерится (нет смысла без выбранной роли)

`data-testid="bulk-row-{permission_id}"`
`aria-label="Выбрать все права для {action} по всем ролям"` (или по выбранной роли)

Состояние: если все non-system ячейки строки = true → checked; если все = false → unchecked;
иначе — indeterminate.

---

#### B.9. Детали реализации — UnsavedChangesGuard.tsx

AlertDialog (shadcn). Срабатывает когда:
1. isDirty=true И пользователь кликает по другой вкладке ресурса
2. isDirty=true И пользователь пытается перейти по навигации (Prompt через React Router)

Кнопки:
- «Остаться» — закрыть Dialog, остаться на текущей вкладке
- «Перейти» — сбросить pendingChanges (dispatch RESET), перейти

`data-testid="dialog-unsaved-changes"`
`data-testid="btn-unsaved-stay"`, `data-testid="btn-unsaved-leave"`

---

#### B.10. Детали реализации — RevokePermissionDialog.tsx

Открывается в view-mode при клике на X-кнопку заполненной ячейки.

Содержимое:
- Текст: «Отозвать право "{permission_code}" у роли "{role_name}"?»
- Если `role.active_users_count > 0`: Alert warning
  «{N} активных пользователей потеряют это право немедленно»
- Кнопки: «Отмена» и «Подтвердить отзыв» (destructive)

`data-testid="dialog-revoke-permission"`
`data-testid="btn-revoke-confirm"`, `data-testid="btn-revoke-cancel"`
`data-testid="warning-active-users"` (условно)

После confirm: `useRevokeRolePermission()` → 204 → invalidate matrix → Toast «Право отозвано»;
при 403: Toast error.

---

#### B.11. Детали реализации — RolePermissionsHistoryDrawer.tsx

Sheet-based (переиспользовать `<Sheet>` из FE-W1-3, НЕ устанавливать drawer.tsx).

`data-testid="sheet-history"`
`aria-labelledby="sheet-history-title"`

Содержимое:
- Заголовок: «История изменений прав роли "{role_name}"»
- ScrollArea с записями
- Каждая запись: «{action_text} {permission_code} · {actor_user_name} · {date}»
  - action_text: 'Назначено' если action='granted', 'Отозвано' если action='revoked'
  - date: локализованная дата/время (`dd.MM.yyyy HH:mm`)
- Бесконечная прокрутка через useRolePermissionsHistory с пагинацией (offset/limit)
- При пустой истории: «Изменений прав ещё не было» (`data-testid="history-empty"`)

`data-testid="history-entry-{id}"`

---

#### B.12. Детали реализации — csvExport.ts

```ts
export function exportPermissionsMatrixToCsv(
  permissions: PermissionRead[],
  roles: RoleRead[],
  matrix: RolePermissionRead[]
): void
```

Формат выходного файла:
- UTF-8 BOM (байты `\uFEFF` в начале)
- Заголовочная строка: `Группа,Объект,Действие,{role_name_1},{role_name_2},...,Системная роль`
- Строки данных: `{resource},{entity},{action},{«Да»|«Нет»},...,{«Да»|«Нет»}`
- Сортировка: по resource → entity → action (алфавитно)
- Имя файла: `permissions-matrix-{YYYY-MM-DD}.csv`
- Скачивание через `<a download>` (создать, кликнуть, удалить)

Нет зависимостей на сторонние библиотеки — только нативный Blob API.

---

#### B.13. data-testid матрица (обязательная)

```
page-permissions-matrix
toolbar-permissions
select-role-filter
btn-edit-mode-enter
btn-save
btn-cancel
btn-history
btn-export-csv
banner-prefilter
btn-prefilter-reset
banner-edit-mode
matrix-table
matrix-header
group-{resource}         (Финансы, Кадры, Стройка, Настройки)
bulk-group-{resource}    (bulk-чекбокс всей группы)
row-{permission_id}
bulk-row-{permission_id}
cell-{role_id}-{permission_id}
cell-{role_id}-{permission_id}-locked
icon-lock-{role_id}
btn-revoke-cell-{role_id}-{permission_id}
dialog-revoke-permission
btn-revoke-confirm
btn-revoke-cancel
warning-active-users
dialog-unsaved-changes
btn-unsaved-stay
btn-unsaved-leave
sheet-history
history-entry-{id}
history-empty
```

---

#### B.14. ARIA (WCAG 2.2 AA)

- `aria-busy="true"` на таблице в loading-состоянии
- `aria-label` на все Checkbox-ячейки: `«Право {permission_code} для роли {role_name}»`
- `aria-label` на bulk-чекбоксы строки: `«Выбрать все права для действия {action}»`
- `aria-label` на bulk-кнопки колонок: `«Выбрать все права для роли {role_name}»`
- `aria-labelledby="sheet-history-title"` на Sheet
- `aria-describedby` на Tooltip системных ролей (Radix даёт автоматически)
- Disabled ячейки системных ролей: `aria-disabled="true"`, `aria-label` включает «(недоступно)»

---

## 4. E2E-сценарии: 10 тестов Given/When/Then

Файл: `frontend/e2e/admin-permissions.spec.ts`. Все тесты против MSW-моков.

**E2E-1: Матрица загружается**
```
Given  пользователь авторизован с правом permission.admin
When   открывает /admin/permissions
Then   data-testid="matrix-table" присутствует в DOM
And    в заголовке — названия 5 ролей
And    на 4 системных ролях присутствуют icon-lock-{1,2,3,4}
And    счётчик «N ресурсов × M действий × K ролей» виден
And    4 группы-accordion присутствуют (group-finance, group-hr, group-construction, group-settings)
```

**E2E-2: Pre-filter по роли из FE-W1-3**
```
Given  пользователь авторизован с правом permission.admin
When   открывает /admin/permissions?role=senior_manager
Then   banner-prefilter присутствует с текстом «Старший менеджер»
And    btn-prefilter-reset присутствует
When   кликает btn-prefilter-reset
Then   URL не содержит ?role=, banner-prefilter исчезает
```

**E2E-3: Переключение вкладок групп и guard**
```
Given  открыт /admin/permissions в edit-mode (кликнули btn-edit-mode-enter)
And    в группе «Финансы» изменена хотя бы одна ячейка
When   кликают на заголовок группы «Кадры» (раскрыть)
Then   dialog-unsaved-changes появляется
When   кликают btn-unsaved-stay
Then   Dialog закрывается, группа «Финансы» остаётся раскрытой (изменения не сброшены)
When   кликают btn-unsaved-leave
Then   Dialog закрывается, группа «Кадры» раскрылась, pendingChanges сброшены
```

**E2E-4: Edit-mode — вход, изменения, сохранение**
```
Given  открыт /admin/permissions
When   кликает btn-edit-mode-enter
Then   banner-edit-mode появляется
And    btn-save и btn-cancel присутствуют (btn-edit-mode-enter исчезает)
And   ячейки non-system ролей содержат Checkbox компоненты
When   кликает cell-5-{permission_id} (senior_manager, любой permission) — меняет значение
And    нажимает btn-save
Then   PATCH запрос отправлен с корректным changes массивом
And    Toast «Матрица прав обновлена» отображается
And    edit-mode завершён (banner-edit-mode исчез, btn-edit-mode-enter вернулся)
```

**E2E-5: Bulk-select по строке**
```
Given  открыт /admin/permissions в edit-mode
And    выбрана роль senior_manager в select-role-filter
When   кликает bulk-row-{permission_id} (bulk-чекбокс строки)
Then   все non-system ячейки этой строки становятся checked
And    ячейки системных ролей не изменились (остались locked)
When   нажимает btn-save
Then   PATCH отправлен с N изменениями (только non-system)
```

**E2E-6: Системная роль read-only в edit-mode**
```
Given  открыт /admin/permissions в edit-mode
When   кликает cell-1-{permission_id} (owner — системная роль)
Then   клик игнорируется (значение не изменилось)
And   атрибут disabled/aria-disabled присутствует на Checkbox
When  наводит курсор на icon-lock-1
Then  Tooltip содержит «Права системной роли зафиксированы. Редактирование через UI недоступно»
```

**E2E-7: Unsaved changes guard — остаться**
```
Given  открыт /admin/permissions в edit-mode
And    изменена ячейка (isDirty=true)
When   кликает btn-cancel
Then   dialog-unsaved-changes появляется
When   кликает btn-unsaved-stay
Then   Dialog закрывается, edit-mode остался, изменения сохранены в state
```

**E2E-8: Одиночный отзыв в view-mode**
```
Given  открыт /admin/permissions в view-mode
And    ячейка cell-5-{permission_id} (senior_manager) имеет allowed=true
When   наводит курсор на эту ячейку
Then   btn-revoke-cell-5-{permission_id} становится видимой
When   кликает эту кнопку
Then   dialog-revoke-permission появляется
And    если active_users_count роли > 0: warning-active-users присутствует
When   кликает btn-revoke-confirm
Then   DELETE запрос отправлен
And    Toast «Право отозвано» отображается
And    ячейка становится пустой (allowed=false)
```

**E2E-9: Drawer истории**
```
Given  открыт /admin/permissions?role=accountant
And   btn-history виден (есть role-filter)
When   кликает btn-history
Then   sheet-history открывается
And    присутствуют history-entry-{id} с записями про accountant
And    каждая запись содержит: action (Назначено/Отозвано), permission_code, actor_user_name, дату
When   открывает историю для роли без изменений (senior_manager с нулевой историей)
Then   history-empty присутствует: «Изменений прав ещё не было»
```

**E2E-10: CSV-экспорт**
```
Given  открыт /admin/permissions
When   кликает btn-export-csv
Then   браузер инициирует скачивание файла (Playwright download API)
And    имя файла соответствует формату permissions-matrix-{YYYY-MM-DD}.csv
And    файл содержит BOM (первые байты — EF BB BF)
And    первая строка — заголовок с названиями ролей
And    ячейки значений — «Да» или «Нет»
```

**Опциональные (если время позволит):**

**E2E-11: 403 при PATCH — error toast, edit-mode сохраняется**
```
Given  открыт /admin/permissions в edit-mode
And    MSW переопределён для возврата 403 на PATCH
When   нажимает btn-save
Then   Toast с текстом ошибки отображается
And    edit-mode остался активным (btn-save всё ещё присутствует)
And    pendingChanges не сброшены
```

---

## 5. Переиспользуемые компоненты (frozen из FE-W1-2 и FE-W1-3)

| Компонент / хук | Откуда | Что делает |
|---|---|---|
| `<Can action="permission.admin">` | `shared/auth/Can.tsx` | Скрывает Edit/Export без права |
| `usePermissions()` (auth) | `shared/auth/usePermissions.ts` | Программная проверка прав. **НЕ путать с usePermissionsCatalog()** |
| `AlertDialog`, `Sheet`, `Tooltip`, `Table`, `Tabs`, `Badge`, `Combobox` | FE-W1-3 | Без изменений |
| `apiClient`, `Toast/Sonner` | FE-W1-2 | Без изменений |

**Именование хуков — критично:**
- `usePermissionsCatalog()` — справочник прав из API
- `useRolePermissionsMatrix()` — полная матрица
- `useBatchUpdateRolePermissions()` — PATCH
- `useRevokeRolePermission()` — DELETE
- `useRolePermissionsHistory()` — история

Создать что-то с именем `usePermissions` в `shared/api/` — запрещено.

**Запрещено:** создавать новые файлы в `shared/auth/`, расширять `AuthUser`, менять
логику auth-хуков. При необходимости расширения — эскалация Head немедленно.

---

## 6. Стандарты (из departments/frontend.md)

1. **Query Key Factory** — `permissionKeys` и `rolePermissionKeys` обязательны для всех queries.
   Нет ни одного места, где ключ строится вручную.

2. **Controlled Select + RHF** — `RoleFilterSelect` в toolbar использует `value=` с `Controller`.

3. **`<Button asChild><Link>`** — все навигационные действия.

4. **5 состояний UI** — loading / empty / error / success / edit-mode — на каждом экране.

5. **Envelope ADR 0006** — все list-responses: `{ items, total, offset, limit }`.

6. **Ошибки ADR 0005** — все error-responses: `{ error: { code, message, details } }`.

---

## 7. DoD батча (Definition of Done)

Перед передачей на чекпоинт Head — убедиться самостоятельно:

**Функциональность:**
- [ ] `/admin/permissions` открывается, матрица из MSW
- [ ] 4 группы-accordion с expand/collapse, состояние в localStorage
- [ ] Deep-link `?role=<code>` работает: banner + highlight колонки
- [ ] Edit-mode: btn-edit-mode-enter → btn-save/btn-cancel; bulk row; batch PATCH
- [ ] View-mode: hover-revoke на non-system ячейках; RevokePermissionDialog с warning
- [ ] Системные роли: Lock + Tooltip + disabled ячейки + отсутствие hover-revoke
- [ ] UnsavedChangesGuard: AlertDialog при смене группы с isDirty=true
- [ ] HistoryDrawer (Sheet): открывается при ?role-фильтре, infinite scroll, empty state
- [ ] CSV: скачивание, BOM, «Да»/«Нет», имя файла с датой
- [ ] `<Can action="permission.admin">` скрывает Edit и Export

**Код:**
- [ ] Структура `src/pages/admin/permissions/**` по паттерну §3 этого брифа
- [ ] `permissionKeys` и `rolePermissionKeys` — везде, нет ad-hoc ключей
- [ ] Хук `usePermissionsCatalog()` — не `usePermissions()`
- [ ] matrixState.ts — reducer без side-effects, чистый
- [ ] Нет изменений в FILES_FORBIDDEN
- [ ] Нет `# type: ignore` без обоснования

**Тесты:**
- [ ] `npm run lint && npm run typecheck && npm run build` — 0 warnings, 0 errors
- [ ] Все 10 E2E тестов: `npm run test:e2e admin-permissions.spec.ts` — green
- [ ] MSW handlers.test.ts — +8 кейсов green
- [ ] Zod unit-тесты rolePermissionSchemas — all green
- [ ] Bundle delta ≤ +25 KB gzip

**Данные:**
- [ ] Фикстуры: 21+ permissions (4 группы, 11+ сущностей)
- [ ] Матрица: 5 ролей, корректные allowed для каждой
- [ ] `RoleFixture.active_users_count` присутствует у всех 5 ролей
- [ ] Envelope во всех list-responses

**Доступность:**
- [ ] Полная data-testid матрица из раздела B.13
- [ ] `aria-busy` на таблице в loading
- [ ] `aria-label` на всех Checkbox-ячейках и bulk-элементах
- [ ] `aria-labelledby` на Sheet

---

## 8. Чекпоинты

**Чекпоинт A — после завершения дев-задачи A:**

Dev возвращает Head:
1. Список изменённых файлов (fixtures, handlers, api/permissions.ts, api/rolePermissions.ts,
   validation/rolePermissionSchemas.ts, handlers.test.ts, rolePermissionSchemas.test.ts)
2. `npm run lint && npm run typecheck` — 0 ошибок
3. `npm run test` — all green
4. Ответы на open items из раздела 9

Head проверяет API-часть по head-брифу §3.2 и §5, даёт добро на задачу B.

**Чекпоинт B — финальная сдача:**

Dev возвращает Head:
1. Полный список созданных/изменённых файлов
2. `npm run lint && npm run typecheck && npm run build` — 0 warnings
3. `npm run test:e2e admin-permissions.spec.ts` — все 10+ тестов green
4. Bundle delta (gzip)
5. Скриншот или запись прогона E2E (по возможности)

Head проводит финальное ревью по DoD §7.
При P0/P1 — возврат на исправление. При OK — передача Директору.

---

## 9. Open items — ответить до начала кода

Dev обязан уточнить эти пункты у Head **до старта задачи A**:

**OI-1.** Проверить что FE-W1-3 Roles принят Директором и закоммичен.
Выполнить: `git log --oneline | head -5` — убедиться что есть коммит FE-W1-3.
Если не закоммичен — сообщить Head немедленно, не начинать FE-W1-4.

**OI-2.** Проверить что `frontend/src/components/ui/sheet.tsx` и `tooltip.tsx`
существуют (из FE-W1-3). Если нет — сообщить Head.

**OI-3.** Подтвердить что `npx shadcn@latest add checkbox` прошло без конфликтов.
Запустить, сообщить что именно было установлено и нет ли перезаписи `utils.ts` / `button.tsx`.

**OI-4.** Проверить текущее состояние `frontend/src/mocks/fixtures/users.ts`:
сколько пользователей с `is_active=true` по каждой роли? Это нужно для
корректного заполнения `active_users_count` в дополнении к roles-фикстуре.
Прочитать файл, сообщить Head числа.

---

## 10. Решения, принятые frontend-director/head (закрытые вопросы)

Эти решения окончательны, dev не пересматривает:

- **D-1 (модель взаимодействия):** гибрид edit-mode + single-revoke. Batch-изменения — pessimistic.
  Одиночный отзыв — только в view-mode через hover-кнопку + AlertDialog.
- **D-2 (Drawer):** reuse Sheet из FE-W1-3. Компонент `drawer.tsx` не устанавливается.
- **D-3 (CSV):** клиентская генерация через Blob API. «Да»/«Нет» + UTF-8 BOM.
- **D-4 (атомарность batch):** если в PATCH batch есть системная роль → весь batch → 403.
  UI предотвращает это через disabled ячейки. 403 — защита от обхода.
- **D-5 (active_users_count):** поле в RoleFixture. Фронт использует из loaded state.
- **D-6 (именование хуков):** `usePermissionsCatalog()` — не `usePermissions()` (конфликт).
- **Accordion (группы):** `Collapsible` или `Accordion` shadcn — на выбор dev,
  главное: состояние в localStorage, анимация, badge с числом сущностей.

---

## 11. Решения backend-director по OQ API-контракта (updated by backend-director 2026-04-19)

Ответы директора бэкенда на 3 открытых вопроса API-контракта от frontend-director. Эти решения
окончательны и замыкают бриф со стороны бэкенда. Dev не пересматривает.

---

### OQ-1 — `GET /api/v1/roles/{id}/permissions/history`: Sprint 1 или отложить

**Вердикт: NO — откладываем реальный endpoint на M-OS-1.1B (отдельный backend-batch).**

Обоснование (≤3 строки):
- Audit trail permissions — дополнительная фича поверх core RBAC (US-03 закрыл core), не блокер
  Foundation Sprint. Frontend пишет MSW-мок + UI по зафиксированному в §A.5 контракту — этого
  достаточно для чекпоинта и E2E-9. Реальный endpoint — отдельный backend-batch в M-OS-1.1B,
  подключение через feature-flag или прямую замену MSW → apiClient без изменений UI-кода.

**Что делает frontend в Sprint 1:**
- Полный MSW-хэндлер `GET /api/v1/roles/:id/permissions/history` с envelope и структурой entry — как в §A.5.
- Хук `useRolePermissionsHistory()` в `shared/api/rolePermissions.ts` — готов к переключению на реальный API.
- E2E-9 проходит против MSW.

**Что делает backend в M-OS-1.1B (отдельный batch, здесь не нужно):**
- Реальная таблица `role_permission_history` (миграция Alembic).
- Запись в history в той же транзакции, что и PATCH/DELETE permissions (ADR 0007).
- Endpoint с пагинацией ADR 0006.

---

### OQ-2 — Batch PATCH `/api/v1/roles/permissions`: атомарный 403 или 207 Multi-Status

**Вердикт: Вариант А — атомарный 403.**

Если хоть одно изменение в массиве `changes` относится к системной роли (`is_system=true`) —
весь batch отклоняется с 403, ничего не применяется. Это уже зафиксировано в D-4 и §A.5
(handler MSW), директор подтверждает семантику и для реального backend.

Обоснование:
1. RBAC-защита, не бизнес-правило. UI предотвращает отправку batch с системной ролью через
   disabled ячейки (§B.7). 403 — защита от обхода (curl, custom client, баг в UI).
2. 207 Multi-Status усложняет error-handling без UX-value: frontend пришлось бы парсить
   массив результатов и показывать частичный успех — путает пользователя, ломает optimistic
   rollback в `matrixState.ts`.
3. Соответствует правилу 10 `departments/backend.md` «Bulk-операции — atomic: всё или ничего.
   При ошибке в одном элементе откат всего батча».
4. Формат ошибки — ADR 0005: `{error: {code, message, details}}`.

**Пример response (403):**
```json
{
  "error": {
    "code": "SYSTEM_ROLE_IMMUTABLE",
    "message": "Системные роли нельзя изменять через UI",
    "details": {
      "role_ids": [1, 2, 3, 4],
      "offending_changes": [
        {"role_id": 1, "permission_id": 15, "allowed": false}
      ]
    }
  }
}
```

Поле `details.role_ids` — все системные `role_id`, встреченные в batch; `details.offending_changes`
— конкретные элементы из тела запроса, которые вызвали отказ (для отладки). Frontend рендерит
Toast с `error.message`; `details` — только в dev-консоль.

**Happy path (200):**
```json
{
  "items": [ /* обновлённая матрица всех non-system ролей */ ],
  "total": 42,
  "offset": 0,
  "limit": 200
}
```

---

### OQ-3 — `active_users_count` в `RoleRead`: включить в payload или отдельный stats-endpoint с кэшем

**Вердикт: Вариант А — включить `active_users_count: int` в `RoleRead`.**

Обоснование:
1. Frontend уже ожидает поле в RoleRead (D-5, §A.1 фикстуры). Отдельный endpoint потребовал бы
   второго fetch в `RevokePermissionDialog.tsx` — лишний round-trip + race-условие (warning
   про active_users может не успеть отрисоваться до confirm).
2. Per-call cost приемлем: `SELECT COUNT(*) FROM users WHERE role_id=? AND is_active=true`
   с композитным индексом `users(role_id, is_active)` — O(log N) + O(матчей). Для Sprint 1
   ожидаемая нагрузка: десятки ролей, сотни users. Bottleneck исключён.
3. Вариант Б (кэш TTL=60s) — overkill на skeleton-этапе: добавляет инфраструктуру (Redis/
   in-memory cache с invalidation), stale-data риск для warning «N пользователей потеряют
   право» (критично для UX решения об отзыве).
4. Если в нагрузочном тестировании (M-OS-2 или позже) станет bottleneck — миграция на
   stats-endpoint с кэшем через expand/contract (ADR 0013): сначала добавить
   `GET /api/v1/roles/{id}/stats`, frontend мигрируется, потом удалить поле из RoleRead.

**API-контракт:**

```python
# backend/app/schemas/role.py
class RoleRead(BaseModel):
    id: int
    code: str
    name: str
    description: str | None
    is_system: bool
    active_users_count: int  # NEW: число активных users с этой ролью
    created_at: datetime
    updated_at: datetime
```

```
GET /api/v1/roles/{id}
Response 200:
{
  "id": 5,
  "code": "senior_manager",
  "name": "Старший менеджер",
  "description": "...",
  "is_system": false,
  "active_users_count": 1,
  "created_at": "2026-04-19T10:00:00Z",
  "updated_at": "2026-04-19T10:00:00Z"
}
```

```
GET /api/v1/roles
Response 200:
{
  "items": [ /* RoleRead[] с active_users_count в каждом */ ],
  "total": 5,
  "offset": 0,
  "limit": 200
}
```

Backend-реализация (не в этом брифе — справочно для frontend-dev):
- `RoleService.get()` делает subquery COUNT на `users` в том же запросе (через
  `selectinload`/`with_expression` SQLAlchemy или отдельный batched COUNT в репозитории).
- Обновление `active_users_count` — derived, не хранится в таблице roles.
- Индекс `ix_users_role_id_is_active` на `users(role_id, is_active)` обязателен
  (миграция — отдельный backend-batch при реализации).

**Для MSW-фикстуры (§A.1) ничего не меняется:** статичные значения 1/3/2/0/1 остаются.
Контракт RoleRead совпадает между MSW и реальным backend.

---

### Summary для frontend-dev

| OQ | Вердикт | Что делать dev |
|---|---|---|
| OQ-1 history | NO | Только MSW + UI по §A.5, реального endpoint в Sprint 1 нет |
| OQ-2 batch PATCH | А (атомарный 403) | Следовать §A.5 как есть; error-handling одним кейсом 403 |
| OQ-3 active_users_count | А (в RoleRead) | Следовать §A.1 как есть; фикстура совпадёт с реальным API |

Никаких изменений в FILES_ALLOWED / FILES_FORBIDDEN / DoD / E2E по итогам этих решений
не требуется — все 3 вердикта совпадают с текущей реализацией брифа (MSW-моки уже отражают
атомарный 403 и active_users_count в RoleFixture). Директор подтверждает контракт для
будущего реального backend.

---

## История версий

- v1.0 — 2026-04-19 — frontend-head, первая редакция dev-брифа на основе head-брифа
  fe-w1-4-permissions-matrix.md v1.0 и wireframes v0.3. Декомпозиция на 2 задачи (A/B),
  10 E2E тестов Given/When/Then, FILES_ALLOWED/FORBIDDEN, DoD, 4 open items для dev.
- v1.1 — 2026-04-19 — backend-director — добавлен раздел 11 «Решения backend-director по
  OQ API-контракта»: OQ-1 (history) → NO (MSW-only в Sprint 1), OQ-2 (batch PATCH) → А
  (атомарный 403 с примером response), OQ-3 (active_users_count) → А (в RoleRead с
  API-контрактом). Контракт для реального backend зафиксирован, MSW-фикстуры не меняются.
  Updated by backend-director 2026-04-19.
