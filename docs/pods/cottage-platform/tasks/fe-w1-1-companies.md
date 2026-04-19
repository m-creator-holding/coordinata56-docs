# Бриф для frontend-head: батч FE-W1-1 Companies

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт», v1.6 — Директор не
  вызывает Head напрямую)
- **Батч-ID:** FE-W1-1-companies
- **Под-фаза:** M-OS-1.1 Foundation, Волна 1 (pod: cottage-platform)
- **Предыдущий батч:** FE-W1-0 FE-skeleton — закоммичен в `main` (`72b00bd`)
- **Базовый API-stub:** `74a066e` (43 пути в `backend/openapi.json`)
- **Статус брифа:** утверждено направлением, ждёт одобрения Координатора для
  передачи Head

---

## 0. Основание и источники

Этот батч — первый admin-экран «во плоти». Задаёт паттерн реализации для
оставшихся шести (Users, Roles, Permissions, Company Settings, Integration
Registry, System Config). Ошибки архитектуры здесь дорого обходятся на
последующих экранах — поэтому Head обязан проверить именно паттерны
(структура папок, api-слой, RHF/Zod-конвенции, MSW-фикстуры, testid),
а не только функциональность.

Источники, обязательные к прочтению Head'ом до распределения работы dev'у:

1. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` — **Экран 1.
   Companies**, полностью (строки 34–371): 4 режима (1.А/1.Б/1.В/1.Г),
   BankAccountDialog, поля, состояния, ссылка на OpenAPI
2. `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin-review.md` §Экран 1
   (APPROVED с одним minor — wireframe Dialog-а банковского счёта присутствует
   как текст, не как ASCII, это не блокирует)
3. `docs/pods/cottage-platform/tasks/fe-skeleton-m-os-1-1.md` — бриф
   предыдущего батча FE-W1-0: даёт контекст структуры scaffold, AdminLayout,
   AuthProvider, api.ts
4. `docs/pods/cottage-platform/m-os-1-frontend-plan.md` v1.0 — фронтенд-план
   фазы, §§2.3–2.5, §4 (стек, MSW, тесты)
5. `backend/openapi.json` — base stub, 43 пути; для этого батча релевантны
   `/api/v1/companies` (список, POST, GET, PATCH, DELETE) и
   `/api/v1/companies/{id}/bank-accounts` (CRUD-5). Head сверяет поля
   CompanyCreate/CompanyRead/BankAccountCreate со схемами в wireframes —
   **есть расхождение**, см. §8 «Вопросы к Координатору»
6. `docs/adr/0002-tech-stack.md` — утверждённый стек, не меняем
7. `docs/adr/0005-error-format.md` — формат ошибок `{error: {code, message, details}}`,
   MSW-хэндлеры ошибок должны соответствовать
8. `docs/adr/0006-pagination.md` — envelope `{items, total, offset, limit}`,
   TanStack Query запросы списка строятся на этом
9. `CLAUDE.md` корневой — секции «API», «Код», «Git»; правило ст. 45а
   «No live external integrations»

## 1. Бизнес-цель батча

Дать Владельцу возможность на MVP-бэкенде с MSW-моками **полностью пройти
сценарий управления юрлицами холдинга**: список → поиск/фильтры → создать →
открыть карточку → редактировать → добавить банковский счёт → деактивировать.
Это первый экран, где Владелец увидит работу собственного ПО «на живом UI»,
а не только на wireframes.

Техническая цель — **задать паттерн** для оставшихся шести admin-экранов:

- структура `src/pages/admin/<entity>/` для многофайловых экранов;
- api-слой `src/shared/api/<entity>.ts` с TanStack Query хуками;
- Zod-схемы в `src/shared/validation/<entity>Schemas.ts`;
- 5 состояний UI как обязательная матрица (см. §4);
- Playwright smoke-тест на полный пользовательский путь;
- bundle-budget-контроль (+30–50 KB gzip на экран).

Head фиксирует найденные отклонения от этих паттернов в review-файле и
возвращает dev'у на исправление до коммита.

## 2. Скоуп батча — закрытый список

Любое «заодно и X» запрещено — эскалация через Head Директору.
Причина: первый экран задаёт эталон, расползание скоупа ломает оценку
паттерна для следующих шести экранов.

### Пункт 1. Роуты Companies

Расширить `frontend/src/routes.tsx` admin-секцию `/admin/companies/*`:

- `/admin/companies` — список (режим 1.А)
- `/admin/companies/new` — форма создания (режим 1.В)
- `/admin/companies/:id` — детальная карточка с 4 вкладками (режим 1.Б)
- `/admin/companies/:id/edit` — форма редактирования (режим 1.Г)

Вкладки внутри `:id` — через query-param `?tab=details|users|bank|settings`
либо nested routes `/admin/companies/:id/bank-accounts` — Head выбирает,
предпочтительнее query-param (проще deep-link, не требует дополнительных
Route-узлов). Вкладка «Настройки» — навигационная ссылка на Экран 5
`/admin/companies/:id/settings` (отдельный батч, в этом батче — просто
`<Link>` без реализации).

**Acceptance:** все 4 роута открываются, back-navigation по хлебным крошкам
работает, прямой deep-link в браузере на любую вкладку возвращает нужное
состояние.

### Пункт 2. Структура файлов

В scaffold сейчас только `src/pages/admin/CompaniesPage.tsx` (placeholder).
Развернуть в полноценную многофайловую структуру:

```
src/pages/admin/companies/
  index.ts                         — re-export всех страниц
  CompaniesListPage.tsx            — режим 1.А
  CompanyDetailsPage.tsx           — режим 1.Б (обёртка с вкладками)
  CompanyFormPage.tsx              — режимы 1.В и 1.Г (один компонент, mode="create"|"edit")
  tabs/CompanyDetailsTab.tsx       — вкладка «Реквизиты»
  tabs/CompanyUsersTab.tsx         — вкладка «Сотрудники» (заглушка со ссылкой на /admin/users)
  tabs/CompanyBankAccountsTab.tsx  — вкладка «Банковские реквизиты» (sub-таблица)
  tabs/CompanySettingsTab.tsx      — вкладка «Настройки» (навигационная ссылка)
  dialogs/BankAccountDialog.tsx    — создание/редактирование счёта
  dialogs/PlaceholderUploadDialog.tsx — заглушка «Загрузка в M-OS-2»
  dialogs/DeactivateCompanyDialog.tsx — подтверждение деактивации
```

Существующий `src/pages/admin/CompaniesPage.tsx` удалить (он placeholder),
в `routes.tsx` заменить импорт на новую структуру.

**Важно.** В брифе Координатора упомянуты пути `src/shared/*`, но в scaffold
такой папки нет — используется `src/lib/` и `src/api/generated/`. Head
согласовывает с направлением: **создаём `src/shared/` как новое соглашение**
(api-слой сущностей, Zod-схемы, фикстуры-константы) или **кладём эти файлы
в существующие `src/lib/` / `src/api/`**. Рекомендация Директора — создать
`src/shared/` как корректный паттерн для роста кодобазы (см. §5.1 ниже).

### Пункт 3. API-слой

Сгенерировать типы из OpenAPI и построить api-слой:

1. Запустить `npm run codegen` — обновить `src/api/generated/schema.d.ts`
   (сейчас в нём нет companies/bank-accounts, т.к. codegen не запускался
   после `74a066e`).
2. Создать `src/shared/api/companies.ts` с хуками TanStack Query:
   - `useCompanies(filters)` — GET список, query-key `['companies', filters]`
   - `useCompany(id)` — GET карточка, query-key `['companies', id]`
   - `useCreateCompany()` — POST, invalidates `['companies']`
   - `useUpdateCompany(id)` — PATCH, invalidates `['companies', id]` и `['companies']`
   - `useDeactivateCompany(id)` — **см. §8 вопрос 1 о механике**
   - `useBankAccounts(companyId)` — GET список счетов
   - `useCreateBankAccount(companyId)` / `useUpdateBankAccount` /
     `useDeleteBankAccount`

Все хуки — типизированы через сгенерированные типы
`paths['/api/v1/companies/']['get']['responses']['200']['content']['application/json']`.
Короткие type-алиасы вверху файла, чтобы не плодить длинные обращения.

**Optimistic updates** — для деактивации компании (мгновенное изменение
Badge статуса) и для удаления банковского счёта (строка исчезает до
получения ответа). Для CRUD создания/редактирования — достаточно
invalidateQueries.

### Пункт 4. Zod-схемы и RHF

`src/shared/validation/companySchemas.ts`:

- `companyTypeEnum` = `z.enum(['ooo', 'ao', 'ip', 'other'])` — совпадает
  с backend `CompanyType` (уточнить точные значения в OpenAPI)
- `innSchema` — условная схема: для `ip` — 12 цифр, для остальных — 10 цифр;
  Luhn-проверка по алгоритму ФНС (контрольное число последней цифры)
- `kppSchema` — 9 цифр, nullable для `ip`
- `ogrnSchema` — 13 цифр для ЮЛ / 15 для ИП, опциональное
- `companyCreateSchema` — объединение выше + full_name/short_name/
  legal_address/director_name/is_active; использование `.refine()` для
  условной видимости КПП
- `companyUpdateSchema = companyCreateSchema.partial()`
- `bankAccountSchema` — БИК 9 цифр, расч. счёт 20 цифр, корр. счёт 20 цифр,
  валюта enum, назначение enum

В форме — RHF с `zodResolver(companyCreateSchema)`. Условная видимость КПП
и метка «ФИО руководителя / Индивидуальный предприниматель» — через
`useWatch({ control, name: 'company_type' })`.

Поля формы, которых **нет в текущем API-stub** (ogrn, legal_address,
director_name), — см. §8 вопрос 2. До ответа Координатора: держим их в
Zod-схемах и в UI, но в mutation-body при POST/PATCH пока передаём
как extras и помечаем TODO-комментарием, чтобы не блокировать UI-работу.

### Пункт 5. BIK-каталог

`src/shared/data/bikCatalog.ts`:

```ts
export type BikRecord = {
  bik: string                    // 9 цифр
  bank_name: string
  correspondent_account: string  // 20 цифр
}

export const bikCatalog: BikRecord[] = [ /* 10 банков */ ]

export function findByBik(bik: string): BikRecord | undefined { ... }
```

Список 10 банков — Head составляет сам из общедоступных данных (Сбербанк,
ВТБ, Газпромбанк, Альфа-Банк, Тинькофф, Открытие, Россельхозбанк, Совкомбанк,
Промсвязьбанк, Райффайзен). Это фикстура, не production-каталог — полный
каталог придёт в M-OS-2 с backend-эндпоинтом.

Использование: в BankAccountDialog — `onBikChange`-хэндлер, который при
вводе 9 цифр ищет запись и автозаполняет `bank_name` и
`correspondent_account` (с возможностью ручного переопределения, поля
остаются редактируемыми).

### Пункт 6. MSW-хэндлеры и фикстуры

Существующий `src/mocks/handlers/companies.ts` **расширить** до полного CRUD:

- GET list — с фильтрами по `company_type`, `is_active`, поисковой
  строкой (матчится против `full_name` / `short_name` / `inn`)
- GET detail
- POST create — валидирует ИНН/КПП, возвращает 201 + CompanyRead
- PATCH update — валидирует, возвращает 200 + CompanyRead
- DELETE / POST /deactivate — см. §8 вопрос 1
- GET `/companies/:id/bank-accounts` — список
- POST `/companies/:id/bank-accounts` — создание
- PATCH `/companies/:companyId/bank-accounts/:accountId` — обновление
- DELETE `/companies/:companyId/bank-accounts/:accountId` — удаление

Фикстуры — `src/mocks/fixtures/companies.ts`:

- 4 компании (ООО «Металл», ООО «АЗС», ИП Иванов, ООО «Котедж» —
  последняя is_active=false) — повторяют данные wireframe 1.А для
  визуальной консистентности
- 2–3 банковских счёта, привязанных к первой и второй компании

In-memory-хранилище — модульная переменная массива + счётчик id;
handlers мутируют её. Это **не `localStorage`** — при перезагрузке
страницы моки возвращаются к исходным фикстурам (так проще тестировать).

### Пункт 7. UI-компоненты: 5 состояний

На каждом экране обязательно реализованы все 5 состояний:

| Состояние | Где применяется | Реализация |
|---|---|---|
| loading | Список, карточка, форма (edit preload) | Skeleton-строки/поля (3–5 штук), `aria-busy="true"` |
| empty | Список (0 компаний) | Иллюстрация-заглушка (lucide-react icon), текст, CTA «+ Добавить первую компанию» |
| error | Список, карточка, mutation-fail | Banner с текстом + кнопка «Повторить» (refetch); для mutation — toast через sonner |
| success | После create/update/delete | Toast + redirect (create → `/admin/companies/:id`, edit → `/admin/companies/:id`) |
| dialog-confirm | Деактивация, удаление счёта | shadcn AlertDialog, заголовок/описание/2 кнопки, destructive-вариант для подтверждения |

Toast-библиотека — **sonner** (не установлена в scaffold, добавить в
package.json; согласовано с направлением как стандарт отдела). Head
проверяет, что установка sonner — единственная новая зависимость.
Любые другие новые зависимости — эскалация.

Компоненты shadcn, которых **нет в scaffold**, но нужны для этого экрана:

- `Badge` — для статуса/типа в таблице
- `Tabs` — 4 вкладки карточки
- `Table` — список компаний и sub-таблица счетов
- `Dialog` + `AlertDialog` — BankAccountDialog, DeactivateDialog, PlaceholderUpload
- `Input`, `Label`, `Select`, `Switch`, `Textarea` — форма
- `Breadcrumb` — навигация в карточке/форме
- `Toast` (sonner) — уведомления

Все — через `npx shadcn-ui@latest add <component>`, копируются в
`src/components/ui/`, мы владеем кодом (ADR 0002).

### Пункт 8. Accessibility и testid

- Все интерактивные элементы имеют `aria-label` (кнопки-иконки —
  обязательно: `aria-label="Редактировать компанию"`)
- Формы: все `<Input>` обёрнуты в `<Label>` с `htmlFor`, ошибки валидации
  связаны через `aria-describedby`
- Dialog'и закрываются по Escape, focus-trap работает (Radix UI даёт это
  из коробки, проверить что не сломано)
- Таблицы: `<caption>` или `aria-label` у `<table>`, `scope="col"` у `<th>`
- Цветовой контраст — WCAG 2.2 AA минимум (Badge неактивной компании —
  не просто серый текст, а visible state)

`data-testid`-конвенция (единая на весь отдел, задаём паттерн здесь):

- Страница: `data-testid="page-companies-list"`, `page-company-details`,
  `page-company-form`
- Секции: `data-testid="companies-table"`, `company-form-basic-section`
- Поля формы: `data-testid="field-company-type"`, `field-company-inn`
- Кнопки: `data-testid="btn-company-create"`, `btn-company-save`,
  `btn-company-deactivate`
- Диалоги: `data-testid="dialog-bank-account"`, `dialog-deactivate`
- Строки таблиц: `data-testid="row-company-{id}"`, `row-bank-{id}`

### Пункт 9. Bundle budget

После этого батча `admin/companies` chunk не должен превышать **+50 KB gzip**
относительно baseline после FE-W1-0. Измерение — `rollup-plugin-visualizer`
(уже настроен в scaffold; если нет — Head согласует установку).

Если превышение — Head возвращает dev'у с указанием профилировать:
типичные причины — случайно подтянутый `moment` вместо `date-fns`,
тяжёлая иконочная библиотека, дублирование кода с `src/lib/*`.

### Пункт 10. Playwright smoke-тест

`frontend/e2e/admin-companies.spec.ts`:

**Сценарий «Happy path»:**
1. Открыть `/admin/companies` → видна таблица с 4 компаниями
2. Нажать «+ Добавить компанию» → перешли на `/admin/companies/new`
3. Заполнить форму (тип=ООО, full_name, short_name, ИНН=10 цифр,
   КПП=9 цифр, legal_address, director_name) → «Создать»
4. Редирект на `/admin/companies/:id`, Toast «Компания создана»,
   проверить что поля в карточке совпадают с введёнными
5. Нажать «Редактировать» → перешли на `/admin/companies/:id/edit`
6. Поменять short_name → «Сохранить» → редирект на карточку, Toast
7. Перейти на вкладку «Банковские реквизиты» (query-param `?tab=bank`)
8. Нажать «+ Добавить счёт» → открылся Dialog
9. Ввести БИК=`044525225` (Сбербанк) → проверить автозаполнение банка/
   корр. счёта; ввести расч. счёт 20 цифр; валюта=RUB; назначение=Основной
10. «Сохранить» → Dialog закрылся, Toast «Банковский счёт добавлен»,
    строка видна в sub-таблице
11. Вернуться на `/admin/companies` → созданная компания видна в списке

Тест должен проходить локально (`npm run test:e2e`) против MSW-моков,
не требуя живого бэкенда.

**Дополнительный тест (опционально, если время позволяет):**
- Сценарий деактивации: открыть неактивную компанию, deactivate flow
- Сценарий валидации: неверный ИНН → ошибка под полем

## 3. Жёсткие ограничения (red zones)

- Статья 45а CODE_OF_LAWS — **никаких живых HTTP-запросов**. Только MSW.
  `apiClient` в dev/test режиме всегда идёт на относительные пути, MSW
  перехватывает. Если в PR увидим `fetch('https://...')` или захардкоженный
  прод-URL — reject без обсуждения.
- BIK-каталог — **вшит в код**, никаких вызовов DaData/Банк России. В
  M-OS-2 заменим на backend-endpoint + кэш — но не в этом батче.
- **Не трогать** существующие страницы: `DashboardPage`, `HousesPage`,
  `FinancePage`, `SchedulePage`, `UsersPage`, `RolesPage`, `LoginPage`.
  Даже рефакторинги имен файлов. Если видится регресс — эскалация.
- **Backend — FORBIDDEN**. Любые `.py` в PR → reject.
- Тесты backend — FORBIDDEN.
- **Кастомные компоненты** — только если shadcn не покрывает. Матрица
  прав и BPM-компоненты — следующие батчи, **в этом батче их нет**,
  даже заготовок.
- **Живые интеграции с DaData / Росреестром / ФНС для подсказок ИНН/
  адреса** — запрещены. Всё вводится руками, валидация Luhn'ом.

## 4. Стандарты исполнения (из Design System Initiative v0.1 и принятых ADR)

Обязательные стандарты, которые Head проверяет в review:

1. **openapi-typescript** — типы генерируются из `backend/openapi.json`,
   не пишутся руками. Запускается `npm run codegen`, результат
   коммитится.
2. **RHF + Zod** — все формы. Валидация сервером через axios-interceptor
   422-handler + RHF `setError`.
3. **TanStack Query** — все запросы, ни одного голого `useEffect + fetch`.
   `staleTime` и `gcTime` — на уровне хуков, не в компонентах.
4. **5 состояний UI** — loading / empty / error / success / dialog-confirm,
   без исключений. Head проверяет каждый по чек-листу.
5. **WCAG 2.2 AA** минимум — aria-labels, focus-visible, контраст.
   Полный audit — M-OS-2 отдельной задачей, но базовый уровень
   обязателен сейчас.
6. **data-testid** по конвенции §2.8.
7. **Bundle budget** +30–50 KB gzip на экран.
8. **Formatting / lint / typecheck** — `npm run lint` и `npm run typecheck`
   проходят без warnings, `npm run build` проходит.

## 5. Структура работы для Head

### 5.1 Вопрос о `src/shared/`

Первое решение Head'а — где жить api-слою и валидации. Два варианта:

**Вариант A (рекомендация Директора).** Создать `src/shared/` с
поддиректориями `api/`, `validation/`, `data/`. Это корректный паттерн
для роста кодобазы: всё, что не UI и не страницы, и что переиспользуется
между треками admin и field, живёт в `shared/`.

**Вариант B.** Использовать существующие `src/lib/` (туда положить
`validation/` и `data/`) и `src/api/` (там уже `generated/`, добавить
`companies.ts`). Меньше новых директорий, но `api/` смешивает
сгенерированные типы и прикладной код.

Head выбирает и фиксирует решение в distribution-задаче dev'у. Если
выбирает B — эскалирует Директору, т.к. это отклонение от рекомендации.
Если A — просто фиксирует в review-файле для записи в регламент.

### 5.2 Декомпозиция для dev'а (ориентир)

Head распределяет сам, но ориентировочный порядок работ:

1. Codegen + api-слой + MSW-фикстуры (фундамент) — ~0.5 дня
2. Zod-схемы + BIK-каталог — ~0.3 дня
3. CompaniesListPage + таблица с фильтрами — ~0.5 дня
4. CompanyFormPage (create/edit, условная видимость) — ~1 день
5. CompanyDetailsPage + вкладки (кроме bank) — ~0.5 дня
6. BankAccountsTab + BankAccountDialog — ~0.7 дня
7. DeactivateDialog + PlaceholderUploadDialog — ~0.3 дня
8. Accessibility + testid по всем компонентам — ~0.3 дня
9. Playwright smoke — ~0.3 дня

Итого ~4.4 рабочих дня для frontend-dev-1. Это согласуется с
оценкой Координатора «3–4 дня» с учётом буфера на review-итерации.

Без дедлайна (правило Владельца msg 1306) — но Head отслеживает, что
dev не залипает на одном пункте >1.5 дня, при превышении — эскалация.

### 5.3 Review-процедура

Head проверяет dev-результат по чек-листу до передачи Директору:

- [ ] Все 4 роута открываются, back-navigation работает
- [ ] Codegen-типы актуальны (sha `backend/openapi.json` свежий)
- [ ] Структура файлов `src/pages/admin/companies/` соответствует §2.2
- [ ] Все 5 состояний UI реализованы на каждом экране (скрины в review)
- [ ] Zod-схемы валидируют ИНН/КПП/ОГРН/БИК по правилам
- [ ] BIK-каталог — 10 записей, автозаполнение работает
- [ ] MSW-хэндлеры покрывают весь CRUD + ошибки 404/422
- [ ] Все aria-labels на месте, testid по конвенции
- [ ] `npm run lint / typecheck / build` проходят
- [ ] `npm run test:e2e` (admin-companies.spec.ts) проходит локально
- [ ] Bundle delta ≤ +50 KB gzip
- [ ] Нет изменений в forbidden-файлах (Dashboard/Houses/Finance/Schedule/
  Users/Roles/Login, backend/, tests/)

Найденные проблемы Head разделяет на P0/P1/P2 (по аналогии с backend-review):
- **P0** — блокирует merge (сломан happy path, leak-secret, нарушены red zones)
- **P1** — до commit'а фикс (missing test, accessibility gap, bundle-budget превышение)
- **P2** — technical debt (nice-to-have рефакторинг)

P0/P1 → dev исправляет; P2 → фиксируется в journaling, commit пропускается.

## 6. DoD батча

- PR содержит только файлы, перечисленные в §2; ни одного forbidden
- Весь чек-лист §5.3 зелёный
- Playwright smoke проходит в CI (когда CI для frontend настроен;
  если ещё не настроен — локальный прогон со скрином)
- Директор принимает PR: проверяет, что паттерн (структура, api-слой,
  5 состояний, testid, accessibility) достаточно хорош как эталон
  для следующих 6 экранов; если нет — возврат на доработку
- Координатор коммитит PR в main

## 7. Файлы — итоговый список (для Head, не для исполнения)

**Создать:**
- `frontend/src/pages/admin/companies/index.ts`
- `frontend/src/pages/admin/companies/CompaniesListPage.tsx`
- `frontend/src/pages/admin/companies/CompanyDetailsPage.tsx`
- `frontend/src/pages/admin/companies/CompanyFormPage.tsx`
- `frontend/src/pages/admin/companies/tabs/CompanyDetailsTab.tsx`
- `frontend/src/pages/admin/companies/tabs/CompanyUsersTab.tsx`
- `frontend/src/pages/admin/companies/tabs/CompanyBankAccountsTab.tsx`
- `frontend/src/pages/admin/companies/tabs/CompanySettingsTab.tsx`
- `frontend/src/pages/admin/companies/dialogs/BankAccountDialog.tsx`
- `frontend/src/pages/admin/companies/dialogs/PlaceholderUploadDialog.tsx`
- `frontend/src/pages/admin/companies/dialogs/DeactivateCompanyDialog.tsx`
- `frontend/src/shared/api/companies.ts` (или `src/api/companies.ts` при варианте B)
- `frontend/src/shared/validation/companySchemas.ts`
- `frontend/src/shared/data/bikCatalog.ts`
- `frontend/src/mocks/fixtures/companies.ts`
- `frontend/src/components/ui/badge.tsx` (shadcn add)
- `frontend/src/components/ui/tabs.tsx` (shadcn add)
- `frontend/src/components/ui/table.tsx` (shadcn add)
- `frontend/src/components/ui/dialog.tsx` (shadcn add)
- `frontend/src/components/ui/alert-dialog.tsx` (shadcn add)
- `frontend/src/components/ui/input.tsx` (shadcn add)
- `frontend/src/components/ui/label.tsx` (shadcn add)
- `frontend/src/components/ui/select.tsx` (shadcn add)
- `frontend/src/components/ui/switch.tsx` (shadcn add)
- `frontend/src/components/ui/breadcrumb.tsx` (shadcn add)
- `frontend/src/components/ui/sonner.tsx` (shadcn add)
- `frontend/e2e/admin-companies.spec.ts`

**Расширить:**
- `frontend/src/routes.tsx` — четыре новых роута Companies
- `frontend/src/mocks/handlers/companies.ts` — полный CRUD + bank accounts
- `frontend/src/mocks/handlers/index.ts` — возможно re-export bank accounts
- `frontend/src/api/generated/schema.d.ts` — перегенерировать codegen
- `frontend/package.json` — добавить `sonner`, при необходимости shadcn UI
  registry

**Удалить:**
- `frontend/src/pages/admin/CompaniesPage.tsx` (старый placeholder)

**FILES_ALLOWED для dev'а** — Head фиксирует явно в distribution-задаче,
чтобы dev не трогал чужое.

## 8. Вопросы к Координатору (ответ пакетом)

### Вопрос 1. Механика деактивации компании — `DELETE` или `POST /deactivate`?

В wireframes (§Связи с другими экранами, режим 1.Б) — кнопка «Деактивировать»
и toast «Компания деактивирована», в Состояниях UI — «Success (деактивация):
Badge статуса меняется на „Неактивна"». В Ссылке на OpenAPI — `DELETE
/api/v1/companies/:id — деактивация компании (soft delete / is_active=false)`.

В брифе Координатора (FE-W1-1) — «POST `/api/v1/companies/:id/deactivate`».

В текущем `backend/openapi.json` — только `DELETE /api/v1/companies/{id}`
(без отдельного `/deactivate`).

Расхождение требует однозначного решения. Варианты:

- **A.** Использовать существующий `DELETE` как soft-delete (не 204, а 200
  + CompanyRead с `is_active=false`). Требует коррекции OpenAPI schema
  (сейчас ответ 204), но минимум изменений в backend.
- **B.** Добавить отдельный `POST /api/v1/companies/{id}/deactivate` в
  OpenAPI stub (в параллельном батче backend/openapi-director), фронт
  реализует по новому контракту.

Директор рекомендует **вариант A**: REST-каноничный soft-delete через
DELETE, без дополнительного ad-hoc эндпоинта. Но это решение уровня
согласования двух директоров — frontend и backend. Прошу Координатора
либо решить волевым, либо инициировать консультацию Директор↔Директор.

### Вопрос 2. Поля ОГРН / юридический адрес / ФИО руководителя

В wireframes (Экран 1, таблица полей) эти поля есть в форме. В текущей
схеме `CompanyCreate` в `backend/openapi.json` — только
`company_type / full_name / short_name / inn / kpp / is_active`. Нет
`ogrn`, `legal_address`, `director_name`.

Это расхождение: wireframes спроектированы под будущую полную схему,
а stub — под текущую минимальную (для раннего PR).

Варианты:

- **A.** В этом батче UI показывает полный набор полей (как в wireframes),
  Zod валидирует всё, но mutation-body в POST/PATCH передаёт только поля
  из `CompanyCreate`/`CompanyUpdate`. Поля ogrn/legal_address/director_name
  помечаются TODO-коментарием, сохраняются в MSW-моках в фикстурах (чтобы
  карточка их показывала). Реальная отправка на бэкенд — после расширения
  схемы в параллельном backend-батче.
- **B.** В этом батче UI показывает только поля из текущей схемы
  (6 штук), остальные поля из wireframes отложены до расширения схемы.
- **C.** Backend-director параллельно расширяет OpenAPI stub, фронт ждёт.

Директор рекомендует **вариант A** — не блокировать UX-работу на
координации с backend. Поля из wireframes показываются, в фикстурах
MSW есть, TODO отмечен. Когда backend расширит схему — меняется одна
строчка в mutation-hook.

### Вопрос 3. Nested-роуты для вкладок — через `?tab=` или `/bank-accounts`?

Принципиального выбора нет, оба паттерна валидны. Предпочтительнее
query-param (проще deep-link, не плодит Route-узлы, легче делать
«сохранить состояние вкладки»). Прошу подтвердить, чтобы зафиксировать
в регламенте как стандарт для других экранов с вкладками (Экраны 3, 5).

### Вопрос 4. `sonner` как toast-библиотека — апрув?

Sonner (https://sonner.emilkowal.ski/) — lightweight-toast, совместим с
shadcn-ui, добавляется как shadcn-компонент
`npx shadcn-ui@latest add sonner`. Альтернатива — `react-hot-toast`
(~15 KB) или встроенный shadcn Toast (перестал поддерживаться в пользу
sonner). Прошу апрув, чтобы использовать в этом и следующих батчах.

### Вопрос 5. BIK-каталог — какой список 10 банков зафиксировать?

Wireframes упоминают, что автозаполнение по БИКу — из справочника «вшитого
во фронтенд». Список конкретных 10 банков в wireframes не приведён.
Директор предлагает список системообразующих (ЦБ РФ, 2024):
Сбербанк, ВТБ, Газпромбанк, Альфа-Банк, Россельхозбанк, Московский
Кредитный Банк, Открытие, Совкомбанк, Тинькофф, Промсвязьбанк. Прошу
подтвердить или заменить.

---

## История версий

- v1.0 — 2026-04-18 — frontend-director, первая редакция бриф-пакета
  для frontend-head, все 10 пунктов скоупа и 5 вопросов Координатору
