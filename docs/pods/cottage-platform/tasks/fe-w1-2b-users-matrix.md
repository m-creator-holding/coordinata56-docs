# Head-бриф: FE-W1-2B Users + Company-Role Matrix

- **Версия:** 1.0-draft
- **Дата:** 2026-04-19
- **От:** frontend-director (L2)
- **Кому:** frontend-head (L3)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-2B-users-matrix
- **Под-фаза:** M-OS-1.1B Config/Admin Foundation
- **Статус:** draft — финальный wireframe v0.4 от design-director ожидается
  (бриф `design-brief-fe-w1-2b-users-matrix-2026-04-19.md`).
  **Head начинает разбор только после утверждения wireframes v0.4.**
- **Предыдущий батч:** FE-W1-2 Users (базовый CRUD, существует)

---

## 0. Что именно расширяем

Базовая страница `/admin/users` (List / Details / Form) и вложенный CRUD
`/api/v1/users/:id/roles` — уже реализованы. Этот батч добавляет:
1. List колонки «Юрлица» и «Роли» с фильтрами по компании/роли
2. Замену вкладки «Роли» на вкладку «Привязки» (user_company_role matrix)
3. Диалог добавления привязки
4. Row-level isolation для accountant + специальный баннер для
   is_holding_owner

---

## 1. FILES_ALLOWED

**Создать:**
```
frontend/src/pages/admin/users/tabs/UserCompanyBindingsTab.tsx
frontend/src/pages/admin/users/dialogs/AddCompanyBindingDialog.tsx
frontend/src/pages/admin/users/dialogs/RemoveCompanyBindingDialog.tsx
frontend/src/pages/admin/users/components/HoldingOwnerBanner.tsx
frontend/src/shared/api/userCompanyBindings.ts
frontend/src/shared/validation/userCompanyBindingSchemas.ts
frontend/e2e/admin-users-matrix.spec.ts
```

**Расширить:**
```
frontend/src/pages/admin/users/UsersListPage.tsx              — колонки Юрлица/Роли + иконка holding-owner, фильтры
frontend/src/pages/admin/users/UserDetailsPage.tsx            — заменить Tabs «Роли» → «Привязки», holding_owner baner
frontend/src/mocks/fixtures/users.ts                          — добавить user_company_roles массив в каждую фикстуру
frontend/src/mocks/handlers/users.ts                          — endpoints /users/:id/companies, /users/:id/companies/:cid
frontend/src/mocks/fixtures/roles.ts                          — без изменений (переиспользуем)
```

**Удалить:** старую вкладку `UserRolesTab.tsx` (если осталась после FE-W1-2)
— проверить существование перед удалением.

## 2. FILES_FORBIDDEN

```
frontend/src/pages/admin/companies/**
frontend/src/pages/admin/roles/**
frontend/src/pages/admin/permissions/**
frontend/src/pages/admin/rules/**
frontend/src/shared/api/companies.ts
frontend/src/shared/api/roles.ts
frontend/src/shared/api/permissions.ts
frontend/src/shared/api/rolePermissions.ts
frontend/src/shared/auth/**
frontend/src/mocks/handlers/{companies,roles,permissions,role_permissions,auth}.ts
backend/**
```

---

## 3. Декомпозиция (ориентир)

### Задача A — API-слой + MSW
- Расширить `fixtures/users.ts`: у каждого user массив
  `user_company_roles: [{ company_id, role_id, assigned_at }]`
- MSW handlers:
  - `GET /api/v1/users/:id/companies` → envelope items of
    `{ company_id, company_name, role_id, role_code, role_name, assigned_at }`
  - `POST /api/v1/users/:id/companies` body `{ company_id, role_id }` →
    201 + созданная привязка; 409 если уже есть такая пара;
    403 если accountant (row-level)
  - `DELETE /api/v1/users/:id/companies/:cid` → 204; 403 если accountant;
    404 если привязки нет; 400 если user is_holding_owner
  - Query-param `?company_id=` в `GET /api/v1/users/` → фильтр users
    по наличию привязки к этой компании
- Хуки: `useUserCompanyBindings(userId)`,
  `useAddUserCompanyBinding()`, `useRemoveUserCompanyBinding()`
- Zod: `addBindingSchema = { company_id: z.number().int().positive(),
  role_id: z.number().int().positive() }`
- Тесты handlers: +6 кейсов (GET list, POST happy, POST 409 duplicate,
  DELETE happy, DELETE 400 holding_owner, DELETE 403 accountant)

### Задача B — UI
- `UsersListPage.tsx`:
  - Добавить колонки «Юрлица» (Badge-list, ≤3 + «+N»), «Роли» (dedup Badge-list)
  - Иконка `Crown` (lucide) рядом с именем если is_holding_owner
  - Фильтры в toolbar: Combobox «Компания», Combobox «Роль»
  - Для accountant: фильтр «Компания» предвыбран на своём юрлице и disabled
- `UserCompanyBindingsTab.tsx`:
  - Таблица привязок + кнопка «+ Добавить» (скрыта для accountant)
  - Кнопка «X» у каждой строки (скрыта для accountant)
  - Если user is_holding_owner → рендерит `HoldingOwnerBanner`, таблица
    и кнопка скрыты
- `AddCompanyBindingDialog.tsx` — Combobox компания + Combobox роль +
  RHF + Zod
- `RemoveCompanyBindingDialog.tsx` — AlertDialog destructive
- E2E spec — сценарии AC-1..AC-4 из design-брифа

---

## 4. Acceptance Criteria (≥3 теста, AC из design-брифа)

AC-1 Filter by company, AC-2 Add binding, AC-3 Accountant row-isolation,
AC-4 Holding-owner banner. Полные Given/When/Then см. design-бриф §5.

## 5. Стандарты (frozen)

- Query Key Factory:
  - `userCompanyBindingKeys.all = ['userCompanyBindings']`
  - `userCompanyBindingKeys.list(userId)` для useUserCompanyBindings
- Combobox (уже есть в /components/ui/) для выбора компании и роли
- data-testid: `page-users-list`, `tab-bindings`, `bindings-table`,
  `row-binding-{company_id}`, `btn-add-binding`,
  `dialog-add-binding`, `dialog-remove-binding`, `banner-holding-owner`,
  `icon-crown-{user_id}`, `filter-company`, `filter-role`,
  `field-binding-company`, `field-binding-role`
- `<Can action="user.admin">` оборачивает «+ Добавить привязку» и «X»
- Backend OQ-1 (см. §7) может изменить контракт — Head ждёт ответа Директора
  до финализации handler

---

## 6. Open Items — до финализации

OI-1. Формат эндпоинта `/users/:id/companies` (ниже OQ backend-director) —
  если бэк решит использовать существующий `/users/:id/roles` как
  полноценный user_company_role вместо дубля — MSW и хуки переименовать.
OI-2. Standalone matrix page `/admin/users/matrix` — в scope или отложено?
  Рекомендация Директора: отложено (nice-to-have sprint 1.1C).

---

## История версий

- v1.0-draft — 2026-04-19 — frontend-director. Черновой head-бриф до
  получения wireframes v0.4 от design-director и ответов OQ от
  backend-director.
