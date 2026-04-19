# Head-бриф: FE-W1-4 Permissions Matrix

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2)
- **Кому:** frontend-head (L3) → далее dev-бриф → frontend-dev (L4)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-4-permissions-matrix
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-3 Roles (ожидает приёмки на момент написания)

---

## 0. Статус и вход

**Входные артефакты:**

| Документ | Версия | Комментарий |
|---|---|---|
| User Stories | `docs/pods/cottage-platform/stories/fe-w1-4-permissions-matrix.md` | 7 US от business-analyst, 5 OQ |
| Wireframes базовый | `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` §Экран 4 | строки 793–914 |
| Wireframes P2 (детализация) | `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin-p2.md` §Экран 4 | строки 35–230 |
| Design System | `docs/design/design-system-v1.md` v1.0 | токены, shadcn-компоненты |
| FE-W1-3 head-бриф | `docs/pods/cottage-platform/tasks/fe-w1-3-roles.md` | паттерн Roles — эталон структуры |
| FE-W1-3 dev-бриф | `docs/pods/cottage-platform/tasks/fe-w1-3-roles-dev-brief.md` | паттерн декомпозиции |

**Ответы Координатора на Open Questions analyst (фиксирую как решения Директора):**

| # | Вопрос analyst | Решение Координатора | Как применять |
|---|---|---|---|
| OQ-1 | Структура API для истории: `?include=history` или отдельный endpoint? | **Отдельный endpoint** `/api/v1/roles/{id}/permissions/history` | Drawer выполняет отдельный запрос, не зависит от основной матрицы. Пагинация — query `offset`/`limit`. |
| OQ-2 | Нужен ли bulk-отзыв? | **Нет**, в backlog P3 | В M-OS-1.1 — только единичный отзыв с AlertDialog. Bulk-select существует только для назначения (US-03). |
| OQ-3 | Отображать ли `active_users_count` в Dialog? | **Да, показываем число** | Требует новое поле `active_users_count: int` в ответе API (см. OQ-Backend-1). |
| OQ-4 | Существует ли `is_system` у permissions? | **Нет**, `is_system` только у ролей | Убираем из US-05 упоминание `permissions.is_system`. Модель прав — плоская: любое permission назначаемо любой пользовательской роли. |
| OQ-5 | Формат CSV: «Да»/«Нет», «1»/«0» или «✓»/«–»? | **«Да» / «Нет»** | UTF-8 BOM для Excel. Столбец «Системная роль» — «Да»/«Нет» по каждой роли. |

---

## 1. Цель батча

Реализовать экран `/admin/permissions` — четвёртый экран Admin UI. Экран является единственной точкой управления правами доступа (permission × role). Включает:

1. Визуализацию полной матрицы «permission × role» с группировкой по ресурсу.
2. Назначение прав роли оптом (bulk-select по строке/столбцу) и единичное.
3. Отзыв прав с подтверждением через AlertDialog (Warning при наличии активных пользователей).
4. Read-only для системных ролей (`is_system=true`) с визуальной индикацией (Lock-иконка).
5. Drawer истории изменений прав роли (audit diff).
6. Экспорт матрицы в CSV (UTF-8 BOM).
7. Фильтры по роли и ресурсу (клиентские, без повторных запросов к API).
8. Вход по deep-link `?role=<code>` из карточки роли (FE-W1-3, US-07 сценарий 7.3).

Результат — готовый экран с 5 состояниями UI, полным data-testid покрытием, 8–12 E2E сценариями, интеграцией с MSW-моками.

---

## 2. Критичное расхождение US ↔ Wireframes — требует разрешения ДО старта

**Суть расхождения:**

| Аспект | User Stories (analyst) | Wireframes (designer) |
|---|---|---|
| Режим взаимодействия | **Optimistic single-click**: клик по ячейке → мгновенный PATCH/DELETE, AlertDialog только на отзыв | **Pessimistic edit-mode**: кнопка «Редактировать» → накопление изменений в памяти → «Сохранить» (batch PATCH) / «Отменить» |
| Endpoint'ы | `PATCH /api/v1/role_permissions` (add ids), `DELETE /api/v1/role_permissions` (role_id+permission_id) | `PATCH /api/v1/roles/permissions` (массив diff'ов) |
| Bulk-select | Floating action panel («Выбрано N permissions» + «Назначить выбранное») | Bulk-чекбокс строки + bulk-кнопка колонки **внутри edit-mode**, применяется при «Сохранить» |
| Отзыв prав | Клик по заполненной ячейке → Dialog подтверждения → DELETE | Снятие чекбокса в edit-mode → учитывается в batch при «Сохранить» (без Dialog per cell) |
| AlertDialog «несохранённые изменения» | Нет (нет концепта) | Есть (при переключении вкладки ресурса с unsaved changes) |
| Drawer истории | Есть (US-07) | Не описан в wireframes P2 |
| Экспорт CSV | Есть (US-06) | Не описан в wireframes |

**Оба подхода рабочие, но несовместимы.** Решение Директора — **выбрать pessimistic edit-mode из wireframes** с частичной интеграцией US:

### Решение D-1 (директива frontend-director): гибрид «edit-mode + single-revoke»

**Обоснование:**
1. Wireframes — приёмный артефакт design-director (уже утверждён designer→ux-head→design-director на момент передачи Координатору), wireframes более детализированы (bulk-mechanics, unsaved-dialog, сценарий B новой роли).
2. Pessimistic edit-mode безопаснее для owner-персоны: предотвращает случайные клики с немедленным эффектом, соответствует философии «подтверждение деструктивных действий».
3. Backend PATCH с массивом diff'ов — нативнее для сохранения audit-транзакции (один audit-event на batch, не N отдельных).
4. Единичный отзыв через Dialog (US-04) **сохраняется как hover-action на заполненной ячейке в режиме просмотра** — для быстрого деструктивного действия без входа в edit-mode. Это закрывает сценарий «срочно отобрать право у роли».

**Итоговая модель взаимодействия:**

| Режим | Что делает | API |
|---|---|---|
| Просмотр (view) | Read-only таблица. Hover на заполненной ячейке пользовательской роли → появляется кнопка «Отозвать» (X-иконка). Клик → AlertDialog (US-04) → DELETE. | `DELETE /api/v1/role_permissions` (одиночный) |
| Редактирование (edit) | Все чекбоксы активны. Изменения накапливаются в локальном state (Map<cellKey, 'added'|'removed'>). Bulk-select по строке/колонке работает как в wireframes. При переключении вкладки ресурса с unsaved changes → AlertDialog. «Сохранить» → один batch PATCH. «Отменить» → сброс state без запроса. | `PATCH /api/v1/roles/permissions` (batch diff) |
| Drawer истории | Открывается кнопкой «История» (в заголовке роли или в filter-panel при фильтре по роли). Параллельно с основной таблицей. | `GET /api/v1/roles/{id}/permissions/history?offset=&limit=` |
| CSV | Кнопка «Экспорт CSV» в toolbar. Генерация на клиенте из загруженных данных. | — |

**Изменения в US, требуемые от analyst (перед началом dev):**

- US-03 (bulk-назначение) — переформулировать под edit-mode: bulk-select работает внутри edit-mode, применяется в batch PATCH; нет отдельной floating-panel «Назначить выбранное».
- US-04 (одиночный отзыв) — оставить как есть, но отметить что работает **только в режиме просмотра** (view). В edit-mode снятие чекбокса — часть batch, без Dialog per cell.
- US-07 (история) — endpoint отдельный: `/api/v1/roles/{id}/permissions/history` (OQ-1 решён).
- Добавить новую US-08 — «Admin отменяет несохранённые изменения при переключении вкладки ресурса» (AlertDialog из wireframes).

**Критичность:** не блокирует старт dev-задачи #1 (API-слой), но **блокирует старт dev-задачи #2 (UI)** — без утверждённой модели взаимодействия UI спроектировать нельзя.

**Владелец разрешения:** Координатор даёт директиву по D-1 (принять/отклонить гибрид), затем inform'ит business-analyst переформулировать US-03/04/07 и добавить US-08. Параллельно — уточнить OQ-Backend-1/2/3 (см. §10).

---

## 3. Scope (состав реализации)

### 3.1 Экраны и компоненты

```
PermissionsMatrixPage (/admin/permissions)
├── PermissionsPageHeader — Заголовок, счётчик «N ресурсов × M действий × K ролей», toolbar
│   ├── ResourceTabs — вкладки ресурсов (contract/payment/project/*)
│   ├── RoleFilterSelect — Select «Показать роль» (Combobox с поиском)
│   ├── ResourceFilterSelect — Select «Ресурс» (alternative к вкладкам, для wide-screen)
│   ├── EditModeToggleButton — «Редактировать» / «Сохранить»+«Отменить»
│   ├── HistoryButton — «История изменений» (видна при фильтре по роли)
│   └── ExportCsvButton — «Экспорт CSV»
├── PredfilterBanner — Baner «Показаны права роли "X". [Сбросить]» (при ?role=<code>)
├── EditModeBanner — Alert «Режим редактирования» (warning)
├── UnsavedChangesGuard — AlertDialog при попытке сменить вкладку
├── PermissionsMatrixTable
│   ├── PermissionsMatrixHeader — строка с bulk-кнопками колонок
│   ├── PermissionsMatrixRow — строка ресурс × действие
│   │   ├── BulkRowCheckbox — bulk-чекбокс строки (для выбранной роли)
│   │   └── PermissionCell — ячейка-чекбокс (или hover-revoke-button в view)
│   └── PermissionsMatrixEmptyState — «Справочник прав пуст»
├── RevokePermissionDialog — AlertDialog одиночного отзыва (view-mode)
└── RolePermissionsHistoryDrawer — Drawer истории изменений роли
```

### 3.2 Shared/api и MSW

- Новые API-модули: `shared/api/permissions.ts`, `shared/api/rolePermissions.ts`
- Новые MSW handlers: `mocks/handlers/permissions.ts`, `mocks/handlers/role_permissions.ts`
- Новые фикстуры: `mocks/fixtures/permissions.ts`, `mocks/fixtures/role_permissions.ts`
- Расширение `mocks/fixtures/roles.ts` — добавить `active_users_count` (вычисляется от users-fixtures).

### 3.3 Новые shadcn-компоненты

Текущий `frontend/src/components/ui/` уже содержит: `sheet`, `tooltip`, `dialog`, `alert-dialog`, `table`, `tabs`, `select`, `combobox`, `badge`, `button`, `skeleton`.

**Не хватает:**
- `checkbox.tsx` — центральный элемент матрицы (создать через `npx shadcn@latest add checkbox`)
- `drawer.tsx` — для RolePermissionsHistoryDrawer

**Решение D-2 по Drawer:** использовать существующий `Sheet` (shadcn) вместо нового `Drawer`. Radix не различает их компонентно — оба являются slide-over. Sheet уже есть в проекте (FE-W1-3). Экономим +3 KB bundle и единообразие UI.

**Итого новых зависимостей:** только `Checkbox` (`npx shadcn@latest add checkbox`).

---

## 4. Дев-задачи (декомпозиция для frontend-head)

Frontend-head принимает этот бриф и готовит свой **dev-бриф** с FILES_ALLOWED / FILES_FORBIDDEN / E2E по паттерну `fe-w1-3-roles-dev-brief.md`.

### Дев-задача #1 — API-слой + MSW-моки + Zod-схемы (0.7–1.0 дня)

**Состав:**
- `shared/api/permissions.ts` — `usePermissions()` (справочник), типы `PermissionRead`, `PermissionFilters` (resource filter).
- `shared/api/rolePermissions.ts` — `useRolePermissionsMatrix()` (full matrix), `useBatchUpdateRolePermissions()` (PATCH), `useRevokeRolePermission()` (DELETE), `useRolePermissionsHistory(roleId, page)`.
- `shared/validation/rolePermissionSchemas.ts` — Zod-схемы для batch diff и single-revoke payload.
- MSW handlers с in-memory CRUD + валидацией + корректными error-кодами (ADR 0005):
  - `GET /api/v1/permissions` — справочник с фильтром `resource`
  - `GET /api/v1/role_permissions` — полная матрица в envelope
  - `GET /api/v1/roles/{id}/permissions/history` — пагинация, envelope
  - `PATCH /api/v1/roles/permissions` — batch diff `{changes: [{role_id, permission_id, allowed}]}`, 403 для системных ролей (`SYSTEM_ROLE_IMMUTABLE`)
  - `DELETE /api/v1/role_permissions` — single revoke, 403 для системных
- Фикстуры: 
  - `permissions.ts` — ~12 permissions (3 ресурса × 4 действия минимум)
  - `role_permissions.ts` — матрица для 5 ролей (4 системных + 1 custom senior_manager)
  - Расширение `roles.ts` фикстур — поле `active_users_count` (вычислять из users.ts).
- MSW тесты в `mocks/__tests__/handlers.test.ts`:
  - 8 новых test-кейсов (GET matrix, PATCH happy, PATCH system-role→403, PATCH mixed batch с 1 system в списке → 403 всего, DELETE happy, DELETE system-role→403, GET history pagination, GET permissions с фильтром resource)

**Output:** PR/batch готовый к ревью Head; dev передаёт Head sanity-check.

### Дев-задача #2 — UI Permissions Matrix (1.3–1.7 дня)

**Состав:**
- Страница `pages/admin/permissions/PermissionsMatrixPage.tsx` + subfolder структура по паттерну Roles/Users.
- View-mode + edit-mode переключение. Bulk-select механика (row/column).
- Unsaved changes guard (AlertDialog при переключении вкладки ресурса).
- Pre-filter от `?role=<code>` (highlight строки, banner с «Сбросить»).
- Lock-иконка + Tooltip для системных ролей (все ячейки disabled).
- Hover-revoke-button в view-mode + RevokePermissionDialog с Warning про `active_users_count`.
- RolePermissionsHistoryDrawer (Sheet-based) с infinite scroll.
- CSV-экспорт на клиенте (генерация Blob, UTF-8 BOM, скачивание через `<a download>`).
- 5 состояний UI на каждом уровне (loading / empty / error / success / edit-mode unsaved dialog).
- Полная data-testid матрица (см. wireframes P2 §data-testid конвенция).
- Маршруты: `<Route path="permissions" element={<PermissionsMatrixPage />} />`.

**Output:** готовый UI с прошедшим E2E-сьютом.

**Декомпозиция не делится на 3 задачи** — unsaved-changes guard и bulk-select механика тесно связаны и их нельзя разделить без двойной работы.

---

## 5. API-контракт (ожидание к backend-director)

**Endpoints (требуют подтверждения/реализации):**

```
GET    /api/v1/permissions
  Query: resource?: string (filter)
  Response: { items: PermissionRead[], total, offset, limit }
  PermissionRead: { id: int, resource: str, action: str, description: str, code: str }
  Note: is_system УБРАНО из модели permissions (OQ-4 решение)

GET    /api/v1/role_permissions
  Response: { items: RolePermissionRead[], total, offset, limit }
  RolePermissionRead: { role_id: int, permission_id: int, allowed: bool }
  Note: плоский список разрешённых пар — фронт разворачивает в матрицу

GET    /api/v1/roles/{id}/permissions/history
  Query: offset?: int, limit?: int (default 50, max 200)
  Response: { items: PermissionHistoryEntry[], total, offset, limit }
  PermissionHistoryEntry: {
    id: int,
    role_id: int,
    permission_id: int,
    permission_code: str,       // для отображения без доп. запроса
    action: 'granted' | 'revoked',
    actor_user_id: int,
    actor_user_name: str,       // denormalized
    created_at: str (ISO)
  }

PATCH  /api/v1/roles/permissions
  Body: { changes: [{ role_id: int, permission_id: int, allowed: bool }, ...] }
  Response 200: { items: RolePermissionRead[], total, offset, limit } (обновлённая матрица)
  Response 403: { error: { code: "SYSTEM_ROLE_IMMUTABLE", message, details: { role_ids: [...] } } }
  Note: если В batch есть ХОТЯ БЫ ОДНА системная роль → весь batch отклоняется (атомарность)

DELETE /api/v1/role_permissions
  Body: { role_id: int, permission_id: int }
  Response 204 (empty body)
  Response 403: { error: { code: "SYSTEM_ROLE_IMMUTABLE", ... } }
```

**Новое поле в существующей модели:**
```
RoleRead.active_users_count: int   # OQ-3 решение
  # количество users с is_active=true, которым назначена эта роль
  # вычисляется backend при запросе, в кэш не попадает
```

**Решения, требующие согласования с backend-director (см. §10).**

---

## 6. Ключевые решения (резюме, 5 штук)

| # | Решение | Обоснование |
|---|---|---|
| **D-1** | **Модель взаимодействия: гибрид «edit-mode + single-revoke» из wireframes P2 + US-04.** Bulk/batch-изменения → pessimistic edit-mode с «Сохранить»/«Отменить»; одиночный срочный отзыв в view-mode — через hover-кнопку + AlertDialog. | Wireframes приоритетны (утверждены design-director). Pessimistic безопаснее для owner. US-03/04/07 требуют переформулировки analyst'ом — см. §2. |
| **D-2** | **Drawer = reuse Sheet (shadcn).** Не устанавливаем отдельный `drawer.tsx`. | Radix не различает; экономия bundle +3 KB; единообразие с FE-W1-3. |
| **D-3** | **CSV-экспорт — на клиенте.** Генерация Blob + `<a download>`, UTF-8 BOM. Нет серверного endpoint'а `/export`. | Данные уже в памяти; не грузит backend; обеспечивает офлайн-генерацию. Формат ячеек — «Да»/«Нет» (OQ-5). Столбец per-role + «Системная роль: Да/Нет» в header. |
| **D-4** | **Атомарный batch при системных ролях.** Если в PATCH batch попал `role_id` системной роли — весь batch отклоняется с 403, не частичная запись. | Транзакционная целостность audit-log (ADR 0007). Упрощает error-handling на фронте (один Toast, не per-cell). |
| **D-5** | **`active_users_count` — требование к backend-dev.** Поле добавляется в `RoleRead`, вычисляется при GET `/api/v1/roles/{id}`. Для одиночного DELETE-запроса фронт использует это поле из уже загруженного состояния (не делает доп. запрос). | OQ-3 решение Координатора; минимизация запросов; консистентность с loaded state. |

---

## 7. Переиспользование (frozen компоненты)

Строго запрещено расширять:

| Компонент | Из какого батча | Использование в FE-W1-4 |
|---|---|---|
| `<Can action="...">` | FE-W1-2 | `<Can action="permission.admin">` — скрыть «Редактировать», «Экспорт» |
| `usePermissions()` (auth hook) | FE-W1-2 | **ВНИМАНИЕ: конфликт имён!** auth-hook и API-hook одинаково называются. В `shared/api/permissions.ts` использовать **`usePermissionsCatalog()`** чтобы избежать конфликта. |
| `AlertDialog`, `Sheet`, `Tooltip`, `Table`, `Tabs`, `Combobox`, `Badge` | FE-W1-3 | Без изменений |
| `apiClient`, `Toast/Sonner` | FE-W1-2 | Без изменений |

**Именование API-хуков (D-6):**
- `usePermissionsCatalog()` — справочник prав
- `useRolePermissionsMatrix()` — полная матрица
- `useBatchUpdateRolePermissions()` — PATCH
- `useRevokeRolePermission()` — DELETE
- `useRolePermissionsHistory()` — история

---

## 8. E2E-сценарии (10 штук — обязательная нижняя граница)

Файл: `frontend/e2e/admin-permissions.spec.ts`. MSW-моки.

1. **Матрица загружается** — видны вкладки ресурсов, таблица, счётчик, 5 ролей в заголовках, Lock-иконка на 4 системных.
2. **Pre-filter по роли из FE-W1-3** — переход `/admin/permissions?role=senior_manager` → banner «Показаны права роли "Старший менеджер"», строка-колонка выделена.
3. **Переключение вкладки ресурса** — клик по вкладке «payment» → таблица фильтруется; URL обновляется (query `?resource=payment`).
4. **Вход в edit-mode + сохранение** — клик «Редактировать» → чекбоксы активны → установить несколько → «Сохранить» → PATCH отправлен с корректным diff → Toast «Матрица прав обновлена» → режим просмотра.
5. **Bulk-select по строке** — в edit-mode клик по bulk-чекбоксу строки «contract × read» → все не-системные ячейки строки становятся checked (системные пропущены) → «Сохранить» → PATCH с корректными N изменениями.
6. **Bulk-кнопка колонки** — в edit-mode клик «Выбрать всех» над колонкой роли → все non-system ячейки колонки checked (только для текущего ресурса) → «Сохранить» успешно.
7. **Unsaved changes guard** — в edit-mode сделать изменение → клик по вкладке другого ресурса → AlertDialog «Есть несохранённые изменения» → «Остаться» → остался на текущей вкладке; «Перейти» → вкладка сменилась, изменения отброшены.
8. **Одиночный отзыв в view-mode** — hover на заполненную ячейку пользовательской роли → появилась X-кнопка → клик → AlertDialog с Warning «3 активных пользователя потеряют это право» → «Подтвердить» → DELETE → Toast «Право отозвано», ячейка опустела.
9. **Системная роль read-only** — в edit-mode клик по ячейке системной роли игнорируется (чекбокс disabled), Tooltip «Права системной роли зафиксированы. Редактирование через UI недоступно»; bulk-чекбокс колонки системной роли disabled.
10. **Drawer истории** — при фильтре по роли `accountant` клик «История» → Sheet-drawer с записями «Назначено accountant×contract.write by Иванов И. 2026-04-17 14:32»; пустая история для роли без изменений → «Изменений прав ещё не было».

**Опциональные (если время позволит):**
11. **CSV-экспорт** — клик «Экспорт CSV» → скачивается файл `permissions-matrix-2026-04-18.csv` с корректной структурой (проверка Playwright `download` API).
12. **403 при попытке PATCH системной роли** — симулировать через devtools/MSW override → PATCH возвращает 403 → Toast error → edit-mode остаётся, изменения не сброшены.

---

## 9. FILES_ALLOWED / FILES_FORBIDDEN (для dev-брифа Head)

Head детализирует в своём dev-брифе. Ориентир:

**ALLOWED create:**
```
frontend/src/pages/admin/permissions/index.ts
frontend/src/pages/admin/permissions/PermissionsMatrixPage.tsx
frontend/src/pages/admin/permissions/components/PermissionsMatrixTable.tsx
frontend/src/pages/admin/permissions/components/PermissionsMatrixHeader.tsx
frontend/src/pages/admin/permissions/components/PermissionCell.tsx
frontend/src/pages/admin/permissions/components/BulkRowCheckbox.tsx
frontend/src/pages/admin/permissions/components/ResourceTabs.tsx
frontend/src/pages/admin/permissions/components/UnsavedChangesGuard.tsx
frontend/src/pages/admin/permissions/dialogs/RevokePermissionDialog.tsx
frontend/src/pages/admin/permissions/drawers/RolePermissionsHistoryDrawer.tsx
frontend/src/pages/admin/permissions/lib/csvExport.ts
frontend/src/pages/admin/permissions/lib/matrixState.ts        (unsaved-changes reducer)
frontend/src/shared/api/permissions.ts
frontend/src/shared/api/rolePermissions.ts
frontend/src/shared/validation/rolePermissionSchemas.ts
frontend/src/components/ui/checkbox.tsx                         (npx shadcn@latest add)
frontend/src/mocks/handlers/permissions.ts
frontend/src/mocks/handlers/role_permissions.ts
frontend/src/mocks/fixtures/permissions.ts
frontend/src/mocks/fixtures/role_permissions.ts
frontend/e2e/admin-permissions.spec.ts
```

**ALLOWED extend:**
```
frontend/src/routes.tsx                                         — добавить /admin/permissions
frontend/src/mocks/fixtures/roles.ts                            — поле active_users_count
frontend/src/mocks/__tests__/handlers.test.ts                   — +8 новых кейсов
frontend/src/pages/admin/PermissionsPage.tsx                    — удалить (старый placeholder)
```

**FORBIDDEN (не трогать):**
```
frontend/src/pages/admin/companies/**
frontend/src/pages/admin/users/**
frontend/src/pages/admin/roles/**                               (FE-W1-3, frozen на момент FE-W1-4)
frontend/src/shared/api/companies.ts
frontend/src/shared/api/users.ts
frontend/src/shared/api/roles.ts                                (за исключением read-only импортов)
frontend/src/shared/api/auth.ts
frontend/src/shared/auth/**
frontend/src/mocks/handlers/companies.ts
frontend/src/mocks/handlers/users.ts
frontend/src/mocks/handlers/roles.ts                            (read handlers из FE-W1-3; добавлять только actor/history-specific handlers можно в новый role_permissions.ts)
frontend/src/mocks/handlers/auth.ts
backend/**
docs/adr/**
.github/workflows/**
```

---

## 10. Open Questions для других директоров

### OQ-Backend-1. Endpoint `GET /api/v1/roles/{id}/permissions/history` — есть ли в планах backend?

Adresat: backend-director.
Context: на момент написания брифа у backend реализованы только роли и базовый audit через `audit_log`-таблицу (ADR 0007). Нужен отдельный query для истории изменений прав конкретной роли — фильтрация audit_log по `entity_type='role_permission' AND role_id=X`, denormalized `actor_user_name` и `permission_code`. 

Вопрос: backend реализует endpoint сразу в этом спринте (блокирует dev-задачу #1 полностью? или только UI history-drawer можно отложить?), или фронт работает на MSW-моке, backend добавит позже?

Предлагаемое решение frontend-director: фронт пишет MSW-мок + UI, history-drawer тестируется только E2E против мока. Реальный endpoint — отдельный backend-batch (B-W1-4-audit-history-queries). E2E на реальном backend — в следующей волне.

### OQ-Backend-2. Атомарность batch PATCH при смешанных ролях

Adresat: backend-director.
Context: решение D-4 — «если в batch есть системная роль → 403 целиком». Это требует транзакционной валидации ДО любой записи (first pass — проверка всех role_ids на is_system, second pass — применение changes).

Вопрос: backend подтверждает эту семантику? Альтернатива — 207 Multi-Status с per-item результатом (сложнее для фронта, стандартнее REST).

Предлагаемое решение frontend-director: 403 целиком (атомарность). 207 не поддерживается multi-status fetch API единообразно. Фронт предотвращает включение системных ролей в batch на UI-уровне (disabled checkbox), 403 — защита от bypass.

### OQ-Backend-3. Поле `active_users_count` в `RoleRead`

Adresat: backend-director.
Context: решение D-5 — поле добавляется в response модели. Вычисление: `SELECT COUNT(*) FROM user_roles WHERE role_id=X AND user.is_active=true`.

Вопрос: backend согласен добавить вычисление при каждом GET `/roles/{id}`? Это дополнительный JOIN на каждый запрос. Альтернатива — отдельный endpoint `GET /api/v1/roles/{id}/active-users-count` с кэшем.

Предлагаемое решение frontend-director: поле в RoleRead. Без кэша. Запросы на карточку роли редкие (несколько раз в день на пользователя), overhead незначителен. Если станет bottleneck — переносим в отдельный endpoint в следующей волне.

---

## 11. Definition of Done (батч)

**Функциональность:**
- [ ] `/admin/permissions` открывается, отображает матрицу из MSW
- [ ] Deep-link `?role=<code>` работает (banner + highlight)
- [ ] Edit-mode: Save/Cancel, bulk-select row/col, unsaved guard
- [ ] View-mode: hover-revoke с AlertDialog + Warning про active_users
- [ ] Системные роли: Lock + Tooltip + disabled checkboxes
- [ ] Drawer истории: infinite scroll, пустая история
- [ ] CSV-экспорт с UTF-8 BOM; ячейки «Да»/«Нет»
- [ ] `<Can action="permission.admin">` скрывает edit/export

**Код:**
- [ ] Структура `pages/admin/permissions/**` следует паттерну Roles
- [ ] Query Key Factory (`permissionKeys`, `rolePermissionKeys`) — без ad-hoc keys
- [ ] Controlled Select (не defaultValue) в фильтрах
- [ ] Нет изменений в FILES_FORBIDDEN
- [ ] Нет нарушений §Код из CLAUDE.md (`# type: ignore` без обоснования и пр.)

**Тесты:**
- [ ] `npm run lint && npm run typecheck && npm run build` — 0 warnings, 0 errors
- [ ] Все 10+ E2E из §8 — green
- [ ] MSW handlers.test.ts — +8 кейсов green
- [ ] Zod-unit тесты для rolePermissionSchemas

**Данные:**
- [ ] Фикстуры: 12+ permissions (3 ресурса × 4 действия), матрица для 5 ролей
- [ ] `RoleFixture.active_users_count` — корректный подсчёт от users.ts
- [ ] Envelope `{ items, total, offset, limit }` во всех list-responses

**Доступность и бандл:**
- [ ] Полная data-testid матрица из wireframes P2 §data-testid конвенция
- [ ] ARIA: `aria-labelledby` на Sheet, `aria-describedby` на Tooltip, `aria-busy` на loading table, `aria-label` на bulk-checkbox и bulk-кнопки («Выбрать все права для роли X», «Выбрать всех для действия write»)
- [ ] Bundle delta ≤ +25 KB gzip (Checkbox ~2 KB + новая страница ~20 KB)

---

## 12. Оценка трудозатрат

| Задача | Дни | Примечание |
|---|---|---|
| Разрешение расхождения US↔Wireframes (D-1) — analyst переформулирует US-03/04/07 + добавляет US-08 | 0.3 | Блокирует dev-задачу #2, не #1 |
| OQ-Backend-1/2/3 (согласование) — backend-director даёт ответы | 0.2 | Параллельно с дев-задачей #1 |
| Дев-задача #1 (API + MSW + Zod) | 0.7–1.0 | По паттерну Roles |
| Чекпоинт #1 Head | 0.2 | Sanity-check + approve |
| Дев-задача #2 (UI + Drawer + CSV + bulk) | 1.3–1.7 | Самая объёмная часть |
| Чекпоинт #2 Head + E2E-прогон | 0.3 | Финальное ревью |
| Директорская приёмка | 0.2 | Вердикт → Координатор → коммит |

**Итого:** **3.0–4.0 дня** (без учёта параллельных backend-задач).

Критический путь: US re-formulation → dev-#2 start. Если analyst и backend отвечают в день Т+1 — старт dev-#2 в Т+2, коммит в Т+4.

---

## 13. Блокеры на старте

| # | Блокер | Кому адресован | Приоритет |
|---|---|---|---|
| B-1 | Разрешение расхождения US↔Wireframes (D-1) — требуется re-formulation US-03/04/07 + US-08 от analyst | business-analyst (через Координатора) | **Blocking dev-#2** |
| B-2 | OQ-Backend-1 (endpoint /history реализуется сейчас или позже?) | backend-director | Non-blocking (фронт работает на MSW) |
| B-3 | OQ-Backend-2 (атомарность batch — 403 целиком подтвердить) | backend-director | Non-blocking (default assumption) |
| B-4 | OQ-Backend-3 (active_users_count — в RoleRead или отдельный endpoint) | backend-director | Non-blocking (default assumption) |
| B-5 | FE-W1-3 Roles ещё не принят на момент старта FE-W1-4 | frontend-director (сам) | Non-blocking — frontend-head ждёт приёмки FE-W1-3 перед стартом dev-#1, иначе риск double-merge |

---

## 14. Протокол передачи

1. Координатор передаёт этот бриф frontend-head с extended thinking keyword.
2. frontend-head читает бриф, wireframes P2 §Экран 4, US analyst, design-system v1.0.
3. frontend-head готовит **dev-бриф** по паттерну `fe-w1-3-roles-dev-brief.md` — с FILES_ALLOWED/FORBIDDEN детализированными, 10+ E2E Given/When/Then, декомпозицией на 2 дева-задачи, open items для dev.
4. frontend-head параллельно формулирует запросы analyst и backend-director (§10, §13) — через Координатора-транспорт.
5. После ответов analyst (B-1) и approval дев-брифа frontend-director'ом — Head стартует dev-задачу #1.
6. Чекпоинт #1 Head → dev-задача #2.
7. Чекпоинт #2 Head → вердикт frontend-director → Координатор → git commit + push.

---

## История версий

- **v1.0** — 2026-04-18 — frontend-director, первая редакция head-брифа на основе User Stories analyst'а, wireframes P2 designer'а и решений Координатора по 5 OQ. Зафиксировано критичное расхождение US↔Wireframes с директивой D-1 (гибрид edit-mode + single-revoke). 3 OQ к backend-director. Оценка 3.0–4.0 дня.
