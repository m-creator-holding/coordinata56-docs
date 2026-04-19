# Бриф для frontend-head: батч FE-W1-2 Users

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6 — Директор
  не вызывает Head напрямую)
- **Батч-ID:** FE-W1-2-users
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-1 Companies (закоммичен `9406cc0` / `4628cc0`)
- **Блокеры сняты:** FE-INFRA-1 lint cleanup (коммит `a98d41a`) закрывает
  обязательный gate `npm run lint` = 0 warnings для следующих админ-экранов
- **Статус брифа:** утверждён направлением, ждёт одобрения Координатора
  для передачи Head

---

## 0. Основание и источники

Этот батч — второй admin-экран. Применяет паттерн FE-W1-1 Companies к
новой сущности с тремя специфическими усложнениями относительно Companies:

1. **RBAC-aware UI** — JWT содержит `permissions` и `is_holding_owner`;
   часть кнопок (Создать / Удалить пользователя / Сменить
   `is_holding_owner`) видна только holding_owner / админу с
   `user.admin` permission.
2. **Consent-модалка (C-1 ФЗ-152)** — глобальный блокирующий экран,
   перехватывающий навигацию при `consent_required=true` в JWT.
   Появляется на всех admin-страницах до принятия актуальной политики.
3. **Вложенный ресурс** — привязки роли к компании
   (`UserCompanyRole`) через отдельный CRUD-subset, не через форму
   пользователя.

Источники, обязательные к прочтению Head'ом до распределения работы dev'у:

1. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` —
   **Экран 2. Users**, строки 377–600 (3 режима 2.А/2.Б/2.В, Dialog
   привязки роли, состояния UI, ссылка на OpenAPI)
2. `docs/pods/cottage-platform/specs/m-os-1-1-sync-contract.md` — статус
   `FE-W1-2 Users` IN PROGRESS, cross-cutting требования по Consent
3. `docs/agents/departments/frontend.md` **v1.1** — 4 обязательных стандарта
   из retrospective FE-W1-1:
   - §5.1 Query Key Factory (`<entity>Keys`)
   - §5.2 Controlled Select + RHF (`value=` вместо `defaultValue=`)
   - §5.2 `<Button asChild><Link>` для навигационных действий
   - §6.2 data-testid матрица
   - §6.3 матрица 5 состояний UI как обязательная
   - §6.4 baseline bundle FE-W1-1
4. **Эталон FE-W1-1 Companies** — полный (Head должен прочитать эти
   файлы и перенять структуру 1-в-1):
   - `frontend/src/pages/admin/companies/*` — вся структура List /
     Details / Form / tabs / dialogs
   - `frontend/src/shared/api/companies.ts` — `companyKeys`-фабрика,
     хуки TanStack Query, optimistic updates, pattern `TODO-fields`
   - `frontend/src/shared/validation/companySchemas.ts` — паттерн
     Zod-схем + `FormValues`-тип + `LABELS`-константы
   - `frontend/src/mocks/handlers/companies.ts` и
     `frontend/src/mocks/fixtures/companies.ts` — паттерн in-memory
     хранилища
   - `frontend/e2e/admin-companies.spec.ts` — паттерн smoke-тестов
5. `docs/pods/cottage-platform/tasks/fe-w1-1-companies.md` — бриф-эталон
   (сверять структуру этого брифа 1-в-1)
6. `docs/pods/cottage-platform/tasks/pr2-wave1-rbac-v2-pd-consent.md` —
   **§3 Пункт 7 и Пункт 8** (админ-эндпоинты `/roles`, `/users/{id}/roles`,
   consent endpoints `GET /auth/consent-status`, `POST /auth/accept-consent`),
   **§5.1 матрица permissions**, **§5.3 JWT claims** (`consent_required`).
   Это контракт, на который закладываются MSW-моки. После merge PR#2 —
   sync-gate (см. §9).
7. `docs/adr/0011-foundation-multi-company-rbac-audit.md` — **Часть 2
   §2.1 шаг 1** (holding_owner bypass), **§2.2** (роли и permissions)
8. `backend/openapi.json` — релевантные пути:
   - `/api/v1/users/` (GET list, POST create)
   - `/api/v1/users/{user_id}` (GET/PATCH/DELETE)
   - `/api/v1/users/{user_id}/roles` (GET list, POST assign)
   - `/api/v1/users/{user_id}/roles/{assignment_id}` (PATCH/DELETE)
   - `/api/v1/roles/` (GET list) — как источник опций Select «Роль»
   - Схемы `UserRead`, `UserCreate`, `UserCompanyRoleRead`,
     `UserCompanyRoleCreateBody`, `UserCompanyRoleUpdate`, `UserRole`
   - **Расхождение с wireframes — см. §8 Вопрос 2** (поля `phone`,
     `is_holding_owner`, `pd_consent_at`, `last_login_at`, `created_at`,
     `company_roles` в wireframes, но отсутствуют в текущей `UserRead`
     stub'а — применяем вариант A FE-W1-1 через TODO-fields)
9. `CLAUDE.md` корневой — секции «API», «Код», «Git», правило
   строгой цепочки делегирования, паттерн Координатор-транспорт v1.6

## 1. Бизнес-цель батча

Дать Владельцу возможность на MVP-бэкенде с MSW-моками полностью пройти
**цикл управления пользователями холдинга**: список → поиск/фильтры →
создать нового бухгалтера → открыть карточку → назначить ему роль
«Бухгалтер» в двух компаниях → снять одну из привязок → деактивировать
уволенного сотрудника → принять политику ПД при первом входе (консент-флоу).

Техническая цель — подтвердить, что паттерн FE-W1-1 масштабируется
на сущность с **вложенным ресурсом** (UserCompanyRole) и с
**разделяемой инфраструктурой** (ConsentGuard + permission-aware UI),
которая понадобится всем следующим экранам (Roles, Permissions, Settings,
Audit). Ошибка в архитектуре этих двух слоёв дорого обходится на
последующих экранах — поэтому Head обязан проверить именно паттерны
разделяемого слоя (`src/shared/auth/*`), а не только функциональность
Users-экрана.

## 2. Скоуп батча — закрытый список

Любое «заодно и X» запрещено — эскалация через Head Директору. Причина:
этот батч задаёт два разделяемых инфраструктурных паттерна
(ConsentGuard, permission-aware UI), ошибки в них каскадом попадут в
следующие 5 экранов.

### Пункт 1. Роуты Users

Расширить `frontend/src/routes.tsx` admin-секцию `/admin/users/*`
(сейчас один placeholder-роут):

- `/admin/users` — список (режим 2.А)
- `/admin/users/new` — форма создания (режим 2.В — create)
- `/admin/users/:id` — детальная карточка (режим 2.Б)
- `/admin/users/:id/edit` — форма редактирования (режим 2.В — edit)

В отличие от Companies, **вкладок на карточке нет** — одна страница с
тремя секциями («Основные данные», «Роли по компаниям», «Системная
информация»). Query-param `?tab=` не нужен. Это упрощение относительно
Companies, которое нужно отметить в review: Head подтверждает выбор.

Dialog назначения роли (режим 2.Б dialog) открывается на странице
карточки, не как отдельный роут. Dialog деактивации — тоже inline.

**Acceptance:** все 4 роута открываются, back-navigation по хлебным
крошкам работает, прямой deep-link в браузере — на любую из карточек.

### Пункт 2. Структура файлов

Существующий `src/pages/admin/UsersPage.tsx` (placeholder) удалить.
Развернуть в многофайловую структуру по паттерну Companies:

```
src/pages/admin/users/
  index.ts                         — re-export всех страниц
  UsersListPage.tsx                — режим 2.А
  UserDetailsPage.tsx              — режим 2.Б (одна страница, 3 секции)
  UserFormPage.tsx                 — режимы 2.В create и edit (один компонент, mode="create"|"edit")
  UserFormWrappers.tsx             — UserFormCreatePage / UserFormEditPage (как в CompanyFormWrappers)
  sections/UserBasicSection.tsx    — секция «Основные данные» карточки
  sections/UserRolesSection.tsx    — секция «Роли по компаниям» + sub-таблица
  sections/UserSystemInfoSection.tsx — «Дата создания», «Последний вход»
  dialogs/RoleAssignmentDialog.tsx — создание/редактирование привязки
  dialogs/DeactivateUserDialog.tsx — подтверждение деактивации
  dialogs/ResetPasswordDialog.tsx  — подтверждение «Отправить письмо
                                      со сбросом пароля?»
```

Обоснование сегментации секций через подкомпоненты (а не inline в
`UserDetailsPage.tsx`): в карточке Users — 3 логически независимые
секции, каждая со своим состоянием (одна из них — sub-таблица
ролей с собственными loading/empty/error). Вынесение в `sections/`
облегчает unit-тестирование и параллельную работу dev'а.

### Пункт 3. Расширение AuthProvider (разделяемая инфраструктура)

**Критичный пункт — задаёт паттерн для следующих 5 экранов.**

Существующий `src/providers/AuthProvider.tsx` содержит только
`token / user / isAuthenticated / login / logout` с минимальной
моделью `AuthUser { id: string; email: string; role: string }`.
Для FE-W1-2 и всех следующих admin-экранов нужно:

1. **Расширить `AuthUser`:**
   ```ts
   interface AuthUser {
     id: number                      // был string, изменить
     email: string
     full_name: string               // новое (есть в UserRead)
     role: string                    // legacy, оставить пока
     is_holding_owner: boolean       // новое, из JWT
     permissions: string[]           // новое, массив 'resource.action'
     consent_required: boolean       // новое, из JWT claim
   }
   ```

2. **Добавить метод `refreshAuth(newToken)`** — вызывается
   `ConsentAcceptModal` после `POST /auth/accept-consent`, чтобы
   обновить `consent_required=false` без logout + login заново.
   Принимает новый JWT, декодирует claims, обновляет состояние.

3. **Добавить утилиту `decodeJwtClaims(token: string)`** в
   `src/shared/auth/jwtUtils.ts` — простой base64-декод payload,
   **без проверки подписи** (это делает backend; MVP-клиент доверяет
   токену из login-ответа). Обоснование: не тащим библиотеку
   `jwt-decode` ради 20 строк. Файл защищён unit-тестом.

4. **Добавить хук `usePermissions()`** в `src/shared/auth/usePermissions.ts`:
   ```ts
   export function usePermissions() {
     const { user } = useAuth()
     return {
       has: (code: string) => user?.is_holding_owner === true
                            || user?.permissions.includes(code)
                            || user?.permissions.includes(code.split('.')[0] + '.admin')
                            || user?.permissions.includes('*.admin'),
       isHoldingOwner: user?.is_holding_owner ?? false,
     }
   }
   ```
   Реализует логику проверки прав 1-в-1 с backend `can()` (ADR 0011
   §2.1): holding_owner bypass + точное совпадение + матчинг через
   `admin` action и `*`-wildcard.

5. **Добавить компонент `<Can action="user.admin">{children}</Can>`**
   в `src/shared/auth/Can.tsx` — скрывает children, если прав нет.
   Используется для кнопок «+ Добавить пользователя», «Удалить»,
   «Сменить holding_owner».

**Важно про backward-compat.** Изменение типа `AuthUser.id` с `string`
на `number` ломает существующих потребителей, если таковые есть. Head
выполняет **ревизию использований `user.id`** перед правкой и
адаптирует все места. Если объём правок превышает 5 файлов — эскалация
Директору (возможно делаем field `id_str: string` как deprecated-alias).

**Acceptance:**
- Все новые файлы `src/shared/auth/*` имеют unit-тесты
- `usePermissions` тестируется на всех 4 случаях (owner / exact match /
  admin-upgrade / wildcard / deny)
- `refreshAuth` тестируется через вручную созданный JWT с разными claims

### Пункт 4. ConsentGuard (разделяемая инфраструктура)

**Критичный пункт — задаёт паттерн для всех защищённых экранов.**

`src/shared/auth/ConsentGuard.tsx` — React-компонент-обёртка, которая
встраивается в `src/admin/AdminApp.tsx` и во все будущие admin-treks
(позже — и field).

Логика:

```tsx
<ConsentGuard>
  <Outlet />  // весь остальной admin
</ConsentGuard>
```

Когда `useAuth().user?.consent_required === true`:
1. Рендерит blocking-модалку `<ConsentAcceptModal>` поверх всего
2. Модалка вызывает `GET /api/v1/auth/consent-status` → показывает
   заголовок политики и блок `body_markdown` (через простой рендерер
   Markdown — **НЕ markdown-react-renderer**, чтобы не тащить
   зависимость; используем `<pre className="whitespace-pre-wrap">`
   для MVP, полный renderer — M-OS-2)
3. Кнопка «Принять» — `POST /api/v1/auth/accept-consent` с `version`
4. При успехе — получает новый токен в ответе (или перелогинивает,
   если backend вариант A), вызывает `refreshAuth(newToken)`, модалка
   закрывается, навигация разблокирована

**Поведение при 403 `PD_CONSENT_REQUIRED` от любого endpoint'а.**
Дополнительный axios response-interceptor в `src/lib/api.ts`
(НЕ трогать существующий 401-handler, дополнить):

```ts
if (error.response?.status === 403
    && error.response?.data?.error?.code === 'PD_CONSENT_REQUIRED') {
  // Триггер ConsentGuard через события — или через глобальный store
  window.dispatchEvent(new CustomEvent('consent-required'))
}
```

ConsentGuard слушает это событие и показывает модалку даже без
перелогина. После accept — можно вызвать retry оригинального запроса
(опционально для MVP — достаточно ручной навигации).

**Edge case — holding_owner без consent.** По PR#2 Пункт 9 §3
holding_owner тоже обязан принять политику. Не делать bypass
в UI — ConsentGuard работает одинаково для всех ролей.

**Acceptance:**
- E2E-тест (см. Пункт 10) покрывает полный consent-flow
- Модалка blocking — попытка клика по sidebar-ссылке не переключает
  страницу
- После accept — возврат к исходной навигации (если был deep-link в
  URL — остаётся)
- Тест на holding_owner consent (отдельный E2E-сценарий)

### Пункт 5. API-слой

Файл `src/shared/api/users.ts`, паттерн 1-в-1 `companies.ts`:

1. **Type-aliases** через `components['schemas']['UserRead']` и т.д.
   Плюс расширение `UserReadExtended` для TODO-fields (вариант A):
   ```ts
   export type UserReadExtended = UserRead & {
     phone?: string | null
     is_holding_owner?: boolean
     pd_consent_at?: string | null
     last_login_at?: string | null
     created_at?: string | null
     company_roles?: UserCompanyRoleRead[]
   }
   ```
   TODO-комментарий: «когда backend расширит UserRead — убрать
   расширение».

2. **Фильтры `UserFilters`:** `search`, `is_active`, `company_id`,
   `offset`, `limit`.

3. **Query Key Factory `userKeys`:** обязательно по §5.1 регламента
   v1.1 — по образцу `companyKeys`:
   ```ts
   export const userKeys = {
     all: ['users'] as const,
     lists: () => [...userKeys.all, 'list'] as const,
     list: (filters) => [...userKeys.lists(), filters] as const,
     details: () => [...userKeys.all, 'detail'] as const,
     detail: (id) => [...userKeys.details(), id] as const,
     roles: (userId) => [...userKeys.detail(userId), 'roles'] as const,
   }
   ```

4. **Хуки:**
   - `useUsers(filters)`
   - `useUser(id)`
   - `useCreateUser()` — возвращает созданный User + temporary
     password (см. §8 Вопрос 3)
   - `useUpdateUser(id)`
   - `useDeactivateUser()` — optimistic update, Badge мгновенно
     меняется (по образцу `useDeactivateCompany`)
   - `useResetPassword()` — POST /users/{id}/reset-password, возвращает
     temporary password для отображения в UI на MVP (см. §8 Вопрос 3)
   - `useUserRoles(userId)` — GET список привязок
   - `useAssignUserRole(userId)` — POST, invalidate userKeys.roles
   - `useUpdateUserRole(userId)` — PATCH, invalidate userKeys.roles
   - `useRevokeUserRole(userId)` — DELETE с optimistic-update

   Все типизированы через сгенерированные схемы.

5. **Отдельный файл `src/shared/api/roles.ts` (только GET list и
   GET one, read-only для Users-экрана):**
   - `useRoles()` — для Select «Роль» в Dialog
   - `useRole(id)` — опционально, на Экране 3 доделаем полноценно
   - `roleKeys` — Query Key Factory, нарастить в FE-W1-3

   **Scope-контроль:** этот файл — заготовка под Экран 3 Roles. В
   FE-W1-2 используется только read-only методы. CRUD роли — НЕ
   реализуется в этом батче, оставляется как TODO с пометкой «FE-W1-3».

6. **Auth endpoints `src/shared/api/auth.ts`** (новый файл):
   - `useConsentStatus()` — GET /auth/consent-status
   - `useAcceptConsent()` — POST /auth/accept-consent, возвращает
     новый токен (см. §8 Вопрос 1)
   - `useLogin()` — POST /auth/login, обрабатывает 403
     `PD_CONSENT_REQUIRED` (возвращает токен + consent_required, по
     варианту A PR#2 Пункт 8)

### Пункт 6. Zod-схемы

`src/shared/validation/userSchemas.ts`, паттерн 1-в-1
`companySchemas.ts`:

- `emailSchema` — стандартная проверка формата (встроенный `z.string().email()`)
- `phoneSchema` — опциональное поле, если задано — формат
  `+7 (XXX) XXX-XX-XX` через regex; пустая строка допустима (трансформ
  в `null`)
- `passwordSchema` — `z.string().min(8).max(128)` — границы по
  `UserCreate` OpenAPI (см. строки 5478-5484)
- `fullNameSchema` — `z.string().min(1).max(255)`
- `userCreateSchema` — объединение: email + full_name + phone +
  password + is_active (default true) + is_holding_owner (default
  false)
- `userUpdateSchema = userCreateSchema.partial().omit({ password: true })`
  — пароль не меняется через update; сбрасывается отдельным
  endpoint'ом
- `userRoleAssignmentSchema` — для Dialog: company_id (int) +
  role_template (z.enum из UserRole) + pod_id (string nullable)

**Нет BIK-каталога** — это был специфичный для Companies. Users
без справочников.

### Пункт 7. MSW-хэндлеры и фикстуры

**Существующие** `src/mocks/handlers/users.ts` и
`src/mocks/handlers/roles.ts` — **полностью переписать**. Сейчас они
не соответствуют OpenAPI:
- `id` — `string` вместо `integer`
- Нет `is_active`, `company_roles`
- Roles: нет `is_system`, `description`

Паттерн 1-в-1 `handlers/companies.ts`:

1. **`src/mocks/fixtures/users.ts`** — 4-5 пользователей, повторяющих
   данные wireframe §2.А:
   - Мартин Васильев — holding_owner, роль owner в 3 компаниях (из
     fixtures/companies.ts)
   - Анна Смирнова — accountant, роль accountant в 2 компаниях
   - Иван Петров — construction_manager, 1 компания
   - Сидоров П.П. — read_only, 2 компании, `is_active=false` (для
     empty/status-filter тест-кейсов)
   - Новый бухгалтер — пустые company_roles (для случая «без ролей»)

2. **`src/mocks/fixtures/roles.ts`** — 4 системные роли из PR#2
   seed-матрицы §5.4: `owner`, `accountant`, `construction_manager`,
   `read_only`. Поля: `id` (int), `code`, `name` (display),
   `description`, `is_system: true`. (`foreman`, `worker` — по
   решению не включать в фикстуру этого батча; они появятся в seed
   backend в PR#2, но для UX Users-экрана 4 роли достаточно и
   визуально совпадает с wireframes Roles §3.А.)

3. **`src/mocks/handlers/users.ts` расширенный CRUD:**
   - GET list — с фильтрами `search` (full_name/email),
     `is_active`, `company_id` (через JOIN по company_roles)
   - GET detail — возвращает UserReadExtended с заполненным
     `company_roles` (inline-join с фикстурой ролей для display_name)
   - POST create — валидирует уникальность email, генерирует
     случайный password если не передан, возвращает 201
     `{user: UserRead, temporary_password: string}` (ADR-отклонение —
     см. §8 Вопрос 3)
   - PATCH update — валидирует, возвращает 200
   - DELETE — soft-delete (вариант A из FE-W1-1 — `is_active=false` +
     возвращает UserReadExtended, не 204)
   - GET `/users/{id}/roles` — пагинированный список UserCompanyRole
   - POST `/users/{id}/roles` — создать привязку, валидировать
     дубликат (409 с `code: DUPLICATE_ASSIGNMENT`)
   - PATCH `/users/{id}/roles/{assignment_id}` — обновить
   - DELETE `/users/{id}/roles/{assignment_id}` — удалить
   - POST `/users/{id}/reset-password` — возвращает
     `{temporary_password: string}` (MVP-шорткат, см. §8 Вопрос 3)

4. **`src/mocks/handlers/roles.ts` read-only CRUD:**
   - GET list — пагинация, возвращает 4 системные роли
   - GET detail — одна роль
   - **НЕ реализуем** POST/PATCH/DELETE в этом батче (scope = Users).
     Оставить TODO-хэндлеры-заглушки с комментарием «заполнится в
     FE-W1-3 Roles».

5. **`src/mocks/handlers/auth.ts` новый файл (consent-flow):**
   - `GET /auth/consent-status` — возвращает фикстивный
     `ConsentStatusResponse`: текущая версия `v1.0`, user_version из
     фикстуры пользователя, `required_action` вычисляется
   - `POST /auth/accept-consent` — валидирует `version==='v1.0'`,
     обновляет фикстуру пользователя, возвращает
     `{access_token: string}` (новый токен без `consent_required`
     claim)
   - `POST /auth/login` (расширить существующий, если есть) —
     возвращает JWT с `consent_required=true` для пользователя
     без consent

   **Текст политики v1.0** — короткий плейсхолдер в фикстуре (200-300
   символов). Полный текст — в backend seed, frontend не знает текста,
   только показывает через ConsentGuard запрос к endpoint'у.

**In-memory + сбрасывается на перезагрузку** — как в Companies
(никакого localStorage).

### Пункт 8. UI-компоненты: 5 состояний (обязательно)

По §6.3 регламента v1.1 — все 5 состояний на каждом экране:

| Состояние | Где применяется | Реализация |
|---|---|---|
| loading | List / Details / Form(edit preload) / RoleAssignmentDialog (Select «Компания» / «Роль» loading) | Skeleton-строки/поля, `aria-busy="true"` |
| empty | List (0 пользователей) / UserRolesSection (0 привязок) | Иллюстрация lucide-icon + CTA: «+ Добавить первого пользователя» / «+ Добавить привязку» |
| error | List / Details / mutation-fail | Banner с `role="alert"` + «Повторить»; для mutation — toast sonner |
| success | Create/Update/Assign/Revoke | Toast sonner + redirect (create/edit); для role-assignment — Dialog закрывается, строка появляется в sub-таблице |
| dialog-confirm | Деактивация пользователя / удаление привязки роли / сброс пароля | AlertDialog, destructive-вариант для деактивации |

**Новое относительно Companies: permission-aware состояние.** Когда
`!usePermissions().has('user.admin')`:
- Кнопка «+ Добавить пользователя» → скрыта (через `<Can>`)
- Кнопка «Редактировать» → скрыта
- Кнопка «Деактивировать» → скрыта
- Поле `is_holding_owner` в форме → disabled с tooltip «Только
  holding_owner может изменить это поле»
- Доступ к `/admin/users/new` прямым URL → редирект на
  `/admin/users` + toast «Недостаточно прав»

Компоненты shadcn — **все уже добавлены в FE-W1-1**, новых
устанавливать не нужно. Используются: Badge, Table, Dialog,
AlertDialog, Input, Label, Select, Switch, Breadcrumb, sonner.

**Исключение — возможно потребуется Tooltip** для hover-описания
поля `is_holding_owner` (если disabled). Если Head решает добавить —
эскалация Директору (одна новая shadcn-зависимость, несущественная,
но через процедуру §7.2 регламента).

### Пункт 9. Accessibility и testid

**data-testid конвенция §6.2 регламента v1.1 — обязательна. Testid
матрица для Users:**

- Страницы: `page-users-list`, `page-user-details`, `page-user-form`
- Секции: `users-table`, `user-basic-section`, `user-roles-section`,
  `user-system-info-section`
- Поля формы: `field-user-email`, `field-user-full-name`,
  `field-user-phone`, `field-user-password`, `field-user-is-active`,
  `field-user-is-holding-owner`
- Поля Dialog привязки: `field-role-assignment-company`,
  `field-role-assignment-role`, `field-role-assignment-pod`
- Кнопки: `btn-user-create`, `btn-user-save`, `btn-user-edit`,
  `btn-user-deactivate`, `btn-user-reset-password`,
  `btn-role-assign`, `btn-role-revoke-{assignmentId}`,
  `btn-role-edit-{assignmentId}`
- Диалоги: `dialog-role-assignment`, `dialog-deactivate-user`,
  `dialog-reset-password`, `dialog-consent-accept`
- Строки таблиц: `row-user-{id}`, `row-user-role-{assignmentId}`

**Consent-модалка testid:** `dialog-consent-accept`,
`btn-consent-accept`, `consent-policy-title`, `consent-policy-body`.

По §6.2 Head при review делает беглый аудит: если у одного поля
формы нет testid — скорее всего забыты все; эскалация P1.

**ARIA:** все кнопки-иконки имеют `aria-label`. Все `<Input>` через
`<Label htmlFor>`. Таблицы с `<caption>` или `aria-label`.
Консент-модалка — `role="dialog"` + `aria-labelledby="consent-policy-title"`
(Radix даёт, проверить).

### Пункт 10. Playwright E2E — минимум 10 тестов

`frontend/e2e/admin-users.spec.ts` — по аналогии с
`admin-companies.spec.ts`, но с расширенным покрытием (минимум 10
тестов, требование Координатора):

1. **Happy path — CRUD пользователя:** list → create → details →
   edit → save → visible в list
2. **Создание без пароля (auto-generate):** POST без password →
   toast показывает сгенерированный temporary password
3. **Назначение роли:** open user → «+ Добавить привязку» → Dialog
   → выбрать компанию + роль + pod → save → строка в sub-таблице
4. **Снятие роли (revoke):** user с привязкой → «Удалить» привязку
   → AlertDialog confirm → optimistic-update строка исчезает, после
   ответа — вообще удалена
5. **Изменение привязки:** «Изменить» строку → Dialog preload'ит
   компанию/роль → смена роли → save → строка обновлена
6. **Деактивация пользователя:** карточка → «Деактивировать» →
   AlertDialog → confirm → Badge меняется мгновенно (optimistic),
   кнопка превращается в «Активировать»
7. **Сброс пароля:** карточка → «Сбросить пароль» → Dialog →
   confirm → toast показывает temporary password
8. **Валидация email:** неверный формат → inline ошибка; дубликат
   email → серверная ошибка через `setError`
9. **Consent-флоу (критичный):** login с пользователем без
   consent → ConsentAcceptModal показан, sidebar-клики не работают
   → «Принять» → модалка закрывается, навигация работает
10. **Permission guard — cross-company/RBAC IDOR simulation:**
    логин как пользователь БЕЗ `user.admin` permission →
    `/admin/users` открывается, но кнопки «+ Добавить»,
    «Редактировать», «Деактивировать» **не видны в DOM** (через
    `<Can>`); прямой URL `/admin/users/new` → редирект +
    toast «Недостаточно прав»

**Дополнительные тесты (опционально, если время позволяет):**
- Поиск по full_name/email
- Фильтр «Статус: Заблокирован»
- Filter «Компания» (select)

Все 10 тестов должны проходить локально (`npm run test:e2e`) против
MSW-моков, без живого backend.

## 3. Жёсткие ограничения (red zones)

- Статья 45а CODE_OF_LAWS — **никаких живых HTTP-запросов**. Только
  MSW. В PR увидим `fetch('https://...')` или захардкоженный прод-URL —
  reject.
- **Не трогать** существующие страницы: `DashboardPage`, `HousesPage`,
  `FinancePage`, `SchedulePage`, `RolesPage`, `LoginPage`, **весь
  `pages/admin/companies/**`** — FE-W1-1 уже в main, регрессий быть
  не должно.
- **Backend — FORBIDDEN**. Любые `.py` в PR → reject.
- Кастомные рендерeры Markdown — запрещены (достаточно `<pre>` для
  MVP); если Head видит, что нужен настоящий рендерер — эскалация.
- Живые интеграции (DaData / email-отправка / SMS) — запрещены.
  «Reset password» и «создание пользователя» — фейковый
  temporary-password в ответе, без реальной отправки.
- **Forbidden files под FE-W1-2:**
  - `src/pages/admin/companies/**` (FE-W1-1 зона)
  - `src/pages/admin/RolesPage.tsx` (останется placeholder до FE-W1-3;
    **не развёртываем в многофайловую структуру в этом батче**, даже
    если Head видит возможность «заодно»)
  - `src/shared/api/companies.ts` (FE-W1-1 зона)
  - `src/shared/validation/companySchemas.ts` (FE-W1-1 зона)
  - `src/mocks/handlers/companies.ts` (FE-W1-1 зона)
  - `src/mocks/fixtures/companies.ts` (FE-W1-1 зона)
  - `backend/**`, `docs/adr/**`, `.github/workflows/**`

## 4. Стандарты исполнения (из departments/frontend.md v1.1)

Head проверяет в review по чек-листу §5.3 своего брифа. Базовые —
повторяют FE-W1-1 + 4 стандарта retrospective:

1. **openapi-typescript** — типы из `backend/openapi.json`,
   `npm run codegen` → `src/api/generated/schema.d.ts` коммитится
2. **RHF + Zod** — все формы
3. **TanStack Query** — все запросы; никакого `useEffect + fetch`
4. **Query Key Factory** — `userKeys`, `roleKeys` — обязательно
   (§5.1 регламента)
5. **Controlled Select + RHF** — `value=` вместо `defaultValue=` на
   Select в RoleAssignmentDialog и в UserFormPage (§5.2 регламента)
6. **`<Button asChild><Link>`** — для всех навигационных действий
   («Редактировать» на карточке, «Назад» по хлебным крошкам) (§5.2
   регламента). `onClick={navigate}` — P1 нарушение
7. **5 состояний UI** — все 5 на каждом экране (§6.3 регламента)
8. **data-testid матрица** — §6.2 регламента, см. Пункт 9
9. **WCAG 2.2 AA** базовый уровень (как в FE-W1-1)
10. **Bundle budget** — +30 KB gzip (меньше чем Companies +50, т.к.
    переиспользуем shadcn и многое из shared/). Измерение после
    сборки. Превышение — профилировать
11. **Lint / typecheck / build** — `npm run lint && npm run typecheck
    && npm run build` — **0 warnings**. FE-INFRA-1 gate уже закрыт —
    регрессии не допускаются
12. **Unit-тесты** — для `jwtUtils`, `usePermissions`, `<Can>`,
    MSW-handlers. Тесты handlers — `src/mocks/__tests__/handlers.test.ts`
    расширить новыми кейсами

## 5. Структура работы для Head

### 5.1 Разделение на dev-задачи (рекомендация Директора)

Head распределяет сам. Рекомендация — 3 дев-задачи, чтобы не
перегружать одного dev'а и чтобы обеспечить параллелизм (если
`frontend-dev-2` активирован) или последовательность (если только
`frontend-dev-1`):

**Dev-задача #1 — Shared infrastructure (разделяемый слой):**
- `src/shared/auth/*` — jwtUtils + usePermissions + Can +
  ConsentGuard
- Расширение `AuthProvider` (`id: number`, permissions,
  consent_required, refreshAuth)
- Расширение `src/lib/api.ts` — response-interceptor на 403
  PD_CONSENT_REQUIRED
- `src/shared/api/auth.ts` — consent-endpoints
- `src/mocks/handlers/auth.ts` — consent handlers
- `src/mocks/fixtures/auth.ts` — политика v1.0
- Unit-тесты всего выше
- Ориентир: 0.8–1 день

**Dev-задача #2 — API-слой + MSW users/roles:**
- `src/shared/api/users.ts` + `src/shared/api/roles.ts`
- `src/shared/validation/userSchemas.ts`
- `src/mocks/handlers/users.ts` (переписывание)
- `src/mocks/handlers/roles.ts` (переписывание read-only)
- `src/mocks/fixtures/users.ts` + `src/mocks/fixtures/roles.ts`
- MSW-handler тесты
- Ориентир: 0.8 день

**Dev-задача #3 — UI Users (страницы):**
- `src/pages/admin/users/*` (все файлы из §2 структуры)
- Обновление `routes.tsx` — 4 роута
- Удаление `src/pages/admin/UsersPage.tsx`
- Playwright `e2e/admin-users.spec.ts` — 10 тестов
- Ориентир: 1.5 дня

**Итого:** ориентировочно 3.1 дня для одного frontend-dev
последовательно, или ~1.5-2 дня параллельно (2 dev'а).

Без дедлайна (правило Владельца msg 1306). Head следит, чтобы dev
не залипал на одном пункте >1 день.

### 5.2 Порядок старта и зависимости

Строгий порядок **только для первой задачи** — Dev-задача #1 (shared
infra) должна завершиться **до** Dev-задачи #3 (UI Users), т.к.
страницы используют `usePermissions`, `<Can>`, ConsentGuard.
Dev-задачи #2 и #3 можно начинать параллельно — API-слой и UI не
блокируют друг друга критически (UI-dev мокирует хуки заглушками,
пока API-слой не готов — это допустимо для параллельности).

### 5.3 Review-процедура

Head проверяет dev-результат по чек-листу до передачи Директору:

- [ ] Все 4 роута Users открываются, back-navigation работает
- [ ] Codegen-типы актуальны (sha `backend/openapi.json`)
- [ ] Структура `src/pages/admin/users/` соответствует §2
- [ ] Разделяемая инфра `src/shared/auth/*` — корректные unit-тесты
- [ ] ConsentGuard работает: полный E2E-цикл accept-consent зелёный
- [ ] `<Can>` + `usePermissions` — все 4 случая (owner/exact/
      admin-upgrade/wildcard) в unit-тестах
- [ ] `AuthProvider` backward-compat: все места `user.id` переведены
      с `string` на `number` без регрессий (проверить Companies,
      чтобы FE-W1-1 не сломался)
- [ ] Все 5 состояний UI на каждом экране
- [ ] Zod-схемы валидируют email/phone/password по правилам
- [ ] MSW-хэндлеры покрывают весь CRUD + вложенный ресурс
      (users/{id}/roles) + consent-flow
- [ ] testid по матрице §6.2 регламента v1.1
- [ ] **4 стандарта v1.1 соблюдены** — Query Key Factory, Controlled
      Select, `<Button asChild><Link>`, 5 состояний UI
- [ ] `npm run lint / typecheck / build` — 0 warnings (FE-INFRA-1 gate!)
- [ ] `npm run test:e2e admin-users.spec.ts` — все 10 тестов
- [ ] Bundle delta ≤ +30 KB gzip (меньше чем FE-W1-1, т.к.
      переиспользуем)
- [ ] Нет изменений в forbidden-файлах (§3 red zones)

P0/P1/P2 по аналогии с FE-W1-1:
- **P0** — блокирует merge (сломан happy path, нарушены red zones,
  регрессии FE-W1-1, утечка secret в тестах/JWT)
- **P1** — до commit'а (accessibility gap, нарушение 4 стандартов
  v1.1, missing testid, bundle превышение, consent-flow не работает)
- **P2** — technical debt, фиксируется в journal, commit пропускается

## 6. DoD батча

- PR содержит только файлы, перечисленные в §2 и §7; ни одного
  forbidden
- Весь чек-лист §5.3 зелёный
- Playwright 10 тестов проходят локально (CI для frontend ещё не
  настроен полноценно; если локально зелено — скрин в отчёте Head'а)
- Директор принимает PR: проверяет (а) паттерн разделяемой инфры —
  достаточно хорош как эталон для следующих 5 экранов,
  (б) consent-flow работает консистентно с PR#2-спекой, (в) 4
  стандарта v1.1 соблюдены. Если нет — возврат на доработку.
- Координатор коммитит PR в main.

## 7. Файлы — итоговый список (для Head, не для исполнения)

**Создать (shared infra):**
- `frontend/src/shared/auth/jwtUtils.ts`
- `frontend/src/shared/auth/usePermissions.ts`
- `frontend/src/shared/auth/Can.tsx`
- `frontend/src/shared/auth/ConsentGuard.tsx`
- `frontend/src/shared/auth/ConsentAcceptModal.tsx`
- `frontend/src/shared/auth/__tests__/jwtUtils.test.ts`
- `frontend/src/shared/auth/__tests__/usePermissions.test.tsx`
- `frontend/src/shared/auth/__tests__/Can.test.tsx`
- `frontend/src/shared/api/users.ts`
- `frontend/src/shared/api/roles.ts`
- `frontend/src/shared/api/auth.ts`
- `frontend/src/shared/validation/userSchemas.ts`

**Создать (MSW):**
- `frontend/src/mocks/fixtures/users.ts`
- `frontend/src/mocks/fixtures/roles.ts`
- `frontend/src/mocks/fixtures/auth.ts`
- `frontend/src/mocks/handlers/auth.ts`

**Создать (pages):**
- `frontend/src/pages/admin/users/index.ts`
- `frontend/src/pages/admin/users/UsersListPage.tsx`
- `frontend/src/pages/admin/users/UserDetailsPage.tsx`
- `frontend/src/pages/admin/users/UserFormPage.tsx`
- `frontend/src/pages/admin/users/UserFormWrappers.tsx`
- `frontend/src/pages/admin/users/sections/UserBasicSection.tsx`
- `frontend/src/pages/admin/users/sections/UserRolesSection.tsx`
- `frontend/src/pages/admin/users/sections/UserSystemInfoSection.tsx`
- `frontend/src/pages/admin/users/dialogs/RoleAssignmentDialog.tsx`
- `frontend/src/pages/admin/users/dialogs/DeactivateUserDialog.tsx`
- `frontend/src/pages/admin/users/dialogs/ResetPasswordDialog.tsx`
- `frontend/e2e/admin-users.spec.ts`

**Расширить:**
- `frontend/src/routes.tsx` — 4 новых роута Users + замена
  lazy-импорта `UsersPage`
- `frontend/src/providers/AuthProvider.tsx` — расширение AuthUser +
  refreshAuth + утилиты
- `frontend/src/lib/api.ts` — 403 PD_CONSENT_REQUIRED interceptor
- `frontend/src/admin/AdminApp.tsx` — обёртка ConsentGuard
- `frontend/src/mocks/handlers/users.ts` — переписать с нуля (CRUD +
  nested roles + reset-password)
- `frontend/src/mocks/handlers/roles.ts` — переписать read-only
- `frontend/src/mocks/handlers/index.ts` — экспорт auth + fix roles
- `frontend/src/mocks/__tests__/handlers.test.ts` — новые тест-кейсы
- `frontend/src/api/generated/schema.d.ts` — если PR#2 смержен до
  старта батча — перегенерировать; иначе — по Sync-gate §9

**Удалить:**
- `frontend/src/pages/admin/UsersPage.tsx` (старый placeholder)

**FILES_ALLOWED для dev'а** — Head фиксирует явно в distribution-
задаче, чтобы dev не трогал чужое. Критично — не пустить
`pages/admin/companies/**` и `pages/admin/RolesPage.tsx` в диф.

## 8. Вопросы к Координатору (ответ пакетом)

### Вопрос 1. Consent-endpoints в OpenAPI stub — до или после PR#2 merge?

В текущем `backend/openapi.json` (коммит `74a066e` + PR#1)
**нет путей** `/api/v1/auth/consent-status`, `/api/v1/auth/accept-consent`,
`/api/v1/permissions`. Они появятся после merge PR#2.

Варианты для FE-W1-2:
- **A (рекомендация Директора).** Закладываемся на форвард-
  совместимый контракт: MSW-моки реализуют спеку из
  `pr2-wave1-rbac-v2-pd-consent.md` §3 Пункт 7.5, Пункт 8. Когда
  PR#2 смержен — Sync-gate (см. §9) перегенерирует `schema.d.ts`,
  тип-алиасы авто-обновятся, адаптер в `src/shared/api/auth.ts`
  меняется минимально (заменяем ручной тип на
  `components['schemas']['ConsentStatusResponse']`).
- **B.** Ждать мержа PR#2 перед стартом FE-W1-2. Блокирует ~3-5
  дней work'а frontend-dev.
- **C.** Попросить backend-director добавить эти пути в OpenAPI
  stub отдельным мини-PR до merge полноценного PR#2. Выигрыш
  незначительный: тип-алиасы всё равно надо сгенерировать заново,
  когда backend закоммитит реализацию. MVP-контракт типов уже
  зафиксирован в брифе PR#2.

Директор **рекомендует вариант A** — не блокировать UX-работу. Это
тот же паттерн, который мы применили в FE-W1-1 для полей
`ogrn/legal_address/director_name` (Вопрос 2 FE-W1-1).

### Вопрос 2. TODO-fields для UserRead — полный список расширений?

Wireframes требуют в форме и на карточке:
- `phone` (поле формы + отображение)
- `is_holding_owner` (Switch в форме, доступ только holding_owner)
- `pd_consent_at` (системная инфа на карточке — не отображается
  явно в wireframes, но как факт есть в модели)
- `last_login_at` (системная инфа на карточке)
- `created_at` (системная инфа на карточке)
- `company_roles: UserCompanyRoleRead[]` (массив в sub-таблице)

Текущая `UserRead` в OpenAPI stub — только `id`, `email`, `full_name`,
`role`, `is_active`. Нет ни одного из шести полей выше.

Варианты — идентичны Вопросу 2 FE-W1-1:
- **A (рекомендация Директора).** Зод валидирует всё, UI отображает
  всё. В mutation-body передаём весь объект, backend игнорирует
  лишнее (после PR#2 — примет). MSW-моки хранят полную фикстуру.
  TODO-комментарии с пометкой «убрать после расширения UserRead в
  backend».
- **B.** В этом батче UI показывает только 5 полей из stub'а.
  Остальные — отложены.
- **C.** Backend-director параллельно расширяет UserRead. Ожидание.

Директор **рекомендует вариант A** (согласуется с FE-W1-1).

### Вопрос 3. Password generation & reset-password — UX на MVP

В PR#2 Пункт 7 описан `POST /users/{id}/reset-password` (не
детализировано, как клиент получает новый пароль). Wireframe пишет:
«Отправить письмо со сбросом пароля на email пользователя?» — но
email-интеграция **запрещена** ст. 45а (никаких live SMTP/Mailgun).

Три MVP-варианта:
- **A (рекомендация Директора).** Admin-API возвращает
  `temporary_password` в ответе. UI показывает его в
  AlertDialog-success: «Новый пароль для <email>: <pwd>. Сохраните и
  передайте пользователю — показывается один раз». Без реальной
  отправки email. Это компромисс MVP: email-сервис придёт в
  production-gate, сейчас — ручная передача.
- **B.** Admin-API просто генерирует + persist в базе, UI говорит
  «Пароль изменён, свяжитесь с пользователем». Но пользователь
  никак не узнаёт пароль — сломанный UX.
- **C.** Email-сервис сейчас — заглушка в backend (логирует в
  stdout), UI показывает «Письмо отправлено». Тоже нерабочий
  сценарий для MVP.

Вариант A единственно рабочий на MVP. Нужно согласие Координатора
и, вероятно, backend-director (потому что возврат
`temporary_password` — отклонение от стандартной практики, должно
быть задокументировано в OpenAPI response). Для MSW-моков —
внедряем сразу; при рассинхронизации с backend-реализацией — по
Sync-gate §9 согласуем.

### Вопрос 4. Field `role` в `UserRead` — сохранять в UI?

Текущая `UserRead.role` — единственная роль пользователя (легаси
из PR#1, до RBAC v2). По PR#2 §6 эта колонка остаётся для
backward-compat, но бизнес-логика читает `user_company_roles`.

В UI Users wireframes §2.Б показывают **только массив
`company_roles`** в sub-таблице, **не одиночный `role`**. Это
корректный путь (role становится неинформативной).

Вариант действий:
- **A (рекомендация Директора).** В форме создания
  `UserCreate.role` — default `read_only`, поле **не показывается в
  форме** (скрытое). В карточке и списке `UserRead.role` тоже не
  отображается. На карточке — только `company_roles`. После
  deprecate в backend (PR#3+) — уберём из `UserCreate` вообще.
- **B.** Показывать `role` как главную «системную» роль рядом с
  company_roles. Захламляет UI, сбивает пользователя с толку.

Директор рекомендует вариант A. Prompt подтверждения от Координатора.

### Вопрос 5. Сортировка и фильтрация списка пользователей

Wireframes показывают сортировку только по ФИО и фильтры: search,
status, company. OpenAPI list endpoint — без явных query-параметров
sort. Варианты:
- **A (рекомендация Директора).** Сортировка — клиент-сайд через
  TanStack Query `select` (проще, нагрузки пока мало). Фильтры —
  server-side через query-params (мы уже делаем так в Companies).
- **B.** Всё server-side — добавлять sort-параметры в запрос.
  Overkill для MVP — 5-10 пользователей.

Рекомендуется A. После роста до 1000+ пользователей — перейдём на
server-side.

---

## 9. Sync-gate follow-up после PR#2 merge

**Обязательная процедура** — frontend-director отслеживает merge PR#2
через sync-contract. После merge:

1. **Codegen update.** Координатор или frontend-head запускает
   `cd frontend && npm run codegen`, проверяет дифф
   `src/api/generated/schema.d.ts`. Ожидаемые изменения:
   - Новые схемы: `ConsentStatusResponse`, `AcceptConsentRequest`,
     `PermissionRead`, `RolePermissionAssignment`, `RolePermissionBulkUpdate`
   - Расширение `UserRead`: поля `is_holding_owner`,
     `pd_consent_at`, `pd_consent_version`
   - Новые пути: `/api/v1/auth/consent-status`,
     `/api/v1/auth/accept-consent`, `/api/v1/permissions`
   - Новая структура seed в `/api/v1/roles/` (поле `code`, `name`,
     `is_system`)

2. **Type-alias update.** В `src/shared/api/users.ts` и
   `src/shared/api/auth.ts` заменить ручные TODO-extensions на
   сгенерированные типы:
   ```ts
   // Было: UserReadExtended = UserRead & { is_holding_owner?: boolean ... }
   // Стало: type UserRead = components['schemas']['UserRead']
   ```
   Убрать TODO-комментарии.

3. **MSW-handler realignment.** Если backend-реализация отличается
   от нашей MSW-спеки (например, consent-accept возвращает не
   `{access_token: string}`, а другой формат) — синхронизировать
   handlers с реальным контрактом. Приоритет — реальный backend.

4. **E2E retry.** Прогнать 10 тестов повторно. Если какой-то
   падает — новые issues, не блокируют merged FE-W1-2, но
   фиксируются для FE-W1-3.

5. **Отчёт sync-gate.** Head оформляет отчёт «Sync-gate после PR#2»
   Директору: список изменений в codegen, список правок в
   shared/api/, результат E2E. Директор принимает. Координатор
   коммитит одним commit'ом.

**Ожидание:** sync-gate — ~0.3 дня работы, если MSW-моки были
заложены корректно. Если расхождение принципиальное (например,
backend выдаёт temporary_password по-другому) — может раздуться до
0.5-0.7 дня.

## 10. Связь с sync-contract

Обновить статус в `docs/pods/cottage-platform/specs/m-os-1-1-sync-contract.md`:
- Row 2 Users: **IN PROGRESS** → FE-W1-2 distributed → FE-W1-2 DONE
  (MSW) → Sync-gate → FE-W1-2 DONE (real backend)
- Блокеры: FE-INFRA-1 — `CLOSED` (коммит `a98d41a`). PR#2 — продолжает
  быть **прогрессирующим**; FE-W1-2 не блокируется им полностью
  благодаря варианту A §8 Вопрос 1.

Координатор обновляет sync-contract при каждой стадии.

---

## История версий

- v1.0 — 2026-04-18 — frontend-director, первая редакция бриф-пакета
  для frontend-head. 10 пунктов скоупа, 5 вопросов Координатору,
  sync-gate после PR#2 merge, 3-дев-задачная декомпозиция с
  разделяемым слоем infrastructure (ConsentGuard, usePermissions,
  Can). Обязательное применение 4 стандартов из
  `departments/frontend.md` v1.1.
