# frontend-head — бриф волны 12 (Operations UI, 3 экрана)

- **Дата:** 2026-04-19
- **Автор:** frontend-director
- **Батч-ID:** ops-ui-wave-12
- **Под-фаза:** M-OS-1 Operations UI (pod: cottage-platform)
- **Паттерн:** §7.5 Fan-out (Pattern 5), размер L (3 экрана, 3 `frontend-dev` параллельно)
- **Источники:** wireframes 2026-04-19 от `designer`:
  - `docs/pods/cottage-platform/design/wireframes-operations-overview-2026-04-19.md` (Экран 1 — Dashboard)
  - `docs/pods/cottage-platform/design/wireframes-operations-houses-2026-04-19.md` (Экран 2A/2B — Houses List + House Card)
  - `docs/pods/cottage-platform/design/wireframes-operations-reports-2026-04-19.md` (Экран 3 — Reports skeleton)

---

## 1. Что сделать в целом

Реализовать 3 операционных экрана, которые ежедневно будут использовать прораб / бухгалтер / директор. Admin UI (волна 11) закрыт. Сейчас строим UI, который увидят роли `owner / director / accountant / foreman`.

Персоны и ключевые ограничения:
- **owner / director** — всё видят, всё могут.
- **accountant** — видит финансы + readonly остальное. На Overview — баннер «Режим просмотра».
- **foreman** — mobile-first планшет, **НЕ** видит финансы нигде (ни на Overview, ни на House Card «Платежи», ни на /reports/financial — там редирект).

Role detection в UI:
- Пока backend-контракта на роли нет (user.role — legacy), используем `useAuth().user?.role` + `is_holding_owner`. Роль трактуем: `is_holding_owner=true` → owner, `role==='director'` → director, `role==='accountant'` → accountant, `role==='foreman'` → foreman, иначе — показываем как owner (на MVP).
- Введите единый helper `useOperationsRole()` в `src/shared/auth/useOperationsRole.ts` (возвращает `'owner' | 'director' | 'accountant' | 'foreman'`). **Owner файла: Worker H** (создаёт первым, Worker I и J импортируют).

## 2. Структура команды и порядок работ

3 `frontend-dev` параллельно — но с **сериализацией по owner'ам общих файлов** (см. §4).

| Worker | Код | Экран | Маршруты |
|---|---|---|---|
| Worker H | `/pages/operations/overview/**` | Project Overview Dashboard | `/projects/:projectId/overview` |
| Worker I | `/pages/operations/houses/**` | Houses List + House Card | `/projects/:projectId/houses`, `/houses/:houseId` |
| Worker J | `/pages/operations/reports/**` | Financial Reports (skeleton) | `/reports/financial` |

## 3. Общие требования (ко всем трём)

- **Стек** — `departments/frontend.md` §3. Новых зависимостей не добавлять.
- **5 состояний UI** — §6.3 (loading / empty / error / success / confirm, где применимо). Review Head обязан проверить чек-лист.
- **data-testid конвенция** — §6.2. Страницы `page-ops-overview`, `page-ops-houses-list`, `page-ops-house-detail`, `page-ops-reports-financial`.
- **Query Key Factory** — §5.1. Каждый новый api-файл обязан экспортировать `<entity>Keys`. Overlap по keys с companyKeys запрещён (неймспейс отдельный: `dashboardKeys`, `housesKeys`, `reportsKeys`).
- **Controlled Select + RHF** — §5.2 (`value=`, не `defaultValue=`).
- **`<Button asChild><Link>` для навигации** — §5.2. Клик на квадрат сетки, строку таблицы, «Открыть», «Перейти к отчёту» — всегда `<Link>`.
- **Accessibility** — §6.1. Кнопки-иконки обязательно `aria-label`. Табы / диалоги — Radix UI (у нас уже в `ui/`).
- **Bundle budget** — +30-50KB gzip на экран (§6.4). Каждый Worker меряет delta через `rollup-plugin-visualizer`, отчёт в возврате Head'у.
- **Lint / typecheck / build / tests** — обязаны проходить (§6.5–6.6). `--max-warnings 0`. Unit vitest на критичные хелперы + Playwright smoke на каждый экран (happy path).
- **Mobile-responsive** — Overview и Houses List **обязательно** в mobile-layout (foreman, планшет ~768px). Reports — desktop-only, foreman редиректится.
- **Role-based rendering** — конкретные таблицы в каждом wireframe. Важно: **conditional render, а не CSS hidden** (H-P9). API не должен отдавать финансовые поля foreman'у — MSW handler'ы должны это ровно симулировать.
- **Живые интеграции запрещены** (§9 CODE_OF_LAWS ст. 45а). 1С — `disabled` + tooltip, не форма активации.

## 4. FILES_ALLOWED и owner'ы общих файлов (обязательно соблюдать)

### Worker H (Overview)
```
FILES_ALLOWED:
  frontend/src/pages/operations/overview/**                  (owner)
  frontend/src/shared/api/dashboard.ts                       (owner, новый)
  frontend/src/mocks/handlers/dashboard.ts                   (owner, новый)
  frontend/src/mocks/fixtures/dashboard.ts                   (owner, новый)
  frontend/src/shared/auth/useOperationsRole.ts              (owner, новый — Worker I и J импортируют)
  frontend/src/layouts/OperationsLayout.tsx                  (owner, новый — Worker I и J импортируют)
  frontend/src/routes.tsx                                    (owner в этой волне — добавляет /projects/:projectId/overview + скаффолд /projects/:projectId/houses, /houses/:houseId, /reports/financial как placeholder lazy-imports; Worker I и J ТОЛЬКО реализуют таргеты, не трогают routes.tsx)
  frontend/src/mocks/handlers/index.ts                       (owner в этой волне — регистрирует dashboard, houses, reports handlers все сразу скаффолдом; но реальная реализация houses/reports от других Worker)
  frontend/src/components/ui/{card,progress,avatar,dropdown-menu,toggle-group}.tsx — если нет, копирует из shadcn-cli (owner первым применением; Worker I и J читают)
```

**Критично:** Worker H в своём PR **создаёт скаффолд** routes и handlers для всех 3 экранов. То есть добавляет lazy-imports `OverviewPage`, `HousesListPage` (placeholder), `HouseDetailsPage` (placeholder), `FinancialReportsPage` (placeholder) и route-нод. Placeholder — это `export default function HousesListPage(){ return <div>TODO: ops-ui-I</div> }`. Тогда Worker I и J просто заменяют содержимое этих файлов в своих PR, не трогая routes.tsx и index.ts. Это убирает 3-way merge.

### Worker I (Houses)
```
FILES_ALLOWED:
  frontend/src/pages/operations/houses/**                    (owner)
  frontend/src/shared/api/houses.ts                          (owner, новый)
  frontend/src/mocks/handlers/houses.ts                      (owner, новый — файл создан-скаффолд Worker H; Worker I пишет содержимое)
  frontend/src/mocks/fixtures/houses.ts                      (owner, новый — файл создан-скаффолд Worker H; Worker I пишет содержимое)
  frontend/src/shared/validation/housesSchemas.ts            (owner, новый — Zod для смены стадии и опций)

ЗАПРЕЩЕНО изменять:
  routes.tsx, mocks/handlers/index.ts, OperationsLayout.tsx, useOperationsRole.ts
```

### Worker J (Reports)
```
FILES_ALLOWED:
  frontend/src/pages/operations/reports/**                   (owner)
  frontend/src/shared/api/reports.ts                         (owner, новый)
  frontend/src/mocks/handlers/reports.ts                     (owner, новый — файл-скаффолд от Worker H)
  frontend/src/mocks/fixtures/reports.ts                     (owner, новый — файл-скаффолд от Worker H)

ЗАПРЕЩЕНО изменять:
  routes.tsx, mocks/handlers/index.ts, OperationsLayout.tsx, useOperationsRole.ts
```

## 5. Порядок merge (serial, но параллельная разработка)

1. **Worker H первым** — закрывает скаффолд. Его PR включает: OperationsLayout, useOperationsRole, routes.tsx (4 маршрута), handlers/index.ts (3 новых импорта), placeholders страниц Houses/Reports, скаффолд-файлы handlers/fixtures houses.ts и reports.ts (пустые массивы + TODO), реальный Overview-экран + shared/api/dashboard.ts + mocks handlers/fixtures dashboard.ts.
2. **Worker I и J параллельно** — во время работы Worker H уже реализуют свой код в `pages/operations/houses/**` и `pages/operations/reports/**`, но merge-ятся строго после Worker H. После merge Worker H их PR-ветки **rebase** на main и merge без конфликтов (они не трогают общие файлы).

Коммит-префиксы: `feat(ops):`, файлов в коммите ≤10, `git add` точечный, **auto-push после каждого commit** (правило Владельца 2026-04-18 msg 1325).

## 6. Бриф Worker H (overview + скаффолд)

### Цель
Реализовать `/projects/:projectId/overview` — дашборд проекта. Параллельно заложить скаффолд volley-12 (layout, routes, handlers/index, placeholders остальных страниц).

### Файлы
См. §4 Worker H.

### Маршрут (добавить в routes.tsx)
```tsx
const OperationsLayout = lazy(() => import('./layouts/OperationsLayout'))
const OverviewPage = lazy(() =>
  import('./pages/operations/overview').then((m) => ({ default: m.OverviewPage })),
)
const HousesListPage = lazy(() =>
  import('./pages/operations/houses').then((m) => ({ default: m.HousesListPage })),
)
const HouseDetailsPage = lazy(() =>
  import('./pages/operations/houses').then((m) => ({ default: m.HouseDetailsPage })),
)
const FinancialReportsPage = lazy(() =>
  import('./pages/operations/reports').then((m) => ({ default: m.FinancialReportsPage })),
)

// Новый блок — operations-routes (под защитой OperationsLayout)
{
  path: '/',
  element: <Suspense fallback={<LoadingSpinner />}><OperationsLayout /></Suspense>,
  children: [
    { path: 'projects/:projectId/overview', element: <OverviewPage /> },
    { path: 'projects/:projectId/houses', element: <HousesListPage /> },
    { path: 'houses/:houseId', element: <HouseDetailsPage /> },
    { path: 'reports/financial', element: <FinancialReportsPage /> },
  ],
}
```

Важно: существующий `RootLayout` сейчас отвечает за `/`, `/houses`, `/finance`, `/schedule` (legacy scaffold). Не трогаем — operations-маршруты добавляются **параллельно**, под новым `OperationsLayout`. Старые `/houses`, `/finance` остаются временно (legacy).

### OperationsLayout
- **Desktop (≥1024px):** Sidebar слева (Дашборд / Дома / Отчёты / Задачи / Профиль) + Topbar с combobox проекта + аватар. Для foreman пункт «Отчёты» **скрыт** (role check).
- **Mobile / Tablet (<1024px):** Topbar compact + Bottom TabBar (4 иконки: Дашборд / Дома / Задачи / Профиль). Sidebar скрыт.
- **Auth-guard:** `isAuthenticated` из `useAuth()` → redirect на `/login`.
- **Role check:** для foreman, если URL `/reports/*` — `<Navigate to="/projects/{projectId}/overview" replace />` (tight redirect, без страницы 403).

### useOperationsRole
```ts
export type OperationsRole = 'owner' | 'director' | 'accountant' | 'foreman'
export function useOperationsRole(): OperationsRole {
  const { user } = useAuth()
  if (user?.is_holding_owner) return 'owner'
  const r = user?.role?.toLowerCase()
  if (r === 'director' || r === 'accountant' || r === 'foreman') return r
  return 'owner' // MVP fallback
}
```

### Overview экран — детали из wireframe (см. полный файл wireframes-operations-overview-2026-04-19.md)

Реализация:
- **KPI** — 4 `<Card>` (Total / Completed / In Progress / Blocked). На mobile — grid 2×2.
- **Financial Snapshot** — `<Card>` с `<Progress>` (shadcn). Role-gate: **скрыт для foreman** (`if role==='foreman' return null`).
- **Houses grid 10×9** — CSS-grid `grid-cols-10` (desktop 28px квадраты), `grid-cols-5` (mobile 40px). Каждый квадрат — `<Link to={`/houses/${id}`}>` с `<Tooltip>` (номер, тип, стадия). Цвет фона — по стадии из палитры (восемь стадий). Badge `!` поверх для `overdue=true`.
- **Blocking issues** — `<Card>` со списком, каждая строка с кнопкой `<Button asChild><Link>Открыть</Link></Button>` (для accountant — `disabled`).
- **Audit feed** — `<ScrollArea>` 280px, `<Avatar>` + текст + timestamp (форматируйте через `Intl.RelativeTimeFormat` для «10 мин назад»).
- **Accountant banner** — `<Alert role="alert">` вверху: «Режим просмотра — редактирование недоступно».

### API (MSW)
```
GET /api/v1/projects/:projectId/overview
  response (owner/director):
    { kpi: {total, completed, in_progress, blocked},
      financial_snapshot: {plan, fact, delta, pct},
      houses_grid: [{ id, number, stage, overdue }] × 85,
      blocking_issues: [{ house_id, number, type, stage, expected_date, overdue_days }] × 4,
      audit_feed: [{ user_name, user_avatar_url|null, action, ts }] × 10 }
  response (foreman):
    same BUT `financial_snapshot: null`
```

Handler должен читать роль из JWT (в MSW мы не будем разбирать реально — берём из request header `X-Test-Role` или модульной переменной MSW. На MVP достаточно query-param `?role=foreman` для E2E). Обсуди с Head выбор механики.

### Тесты Worker H
- Unit: `useOperationsRole` (4 сценария) + dashboard handler (foreman filter финанов).
- Playwright smoke: `operations-overview.spec.ts` — логин → открыть `/projects/1/overview` → проверить KPI + карту домов + редирект foreman с /reports/financial.

### DoD Worker H
- [ ] Скаффолд routes + OperationsLayout + useOperationsRole готов
- [ ] Overview-страница работает для всех 4 ролей
- [ ] 5 состояний UI (loading skeleton, empty, error, success, confirm где надо)
- [ ] data-testid по конвенции
- [ ] Lint / typecheck / build / unit / e2e green
- [ ] Bundle delta <50KB gzip
- [ ] Placeholder файлы pages/operations/houses/index.ts и pages/operations/reports/index.ts созданы (с заглушками)
- [ ] Auto-push после каждого commit

## 7. Бриф Worker I (Houses List + House Card)

### Цель
Реализовать `/projects/:projectId/houses` + `/houses/:houseId` согласно wireframe `wireframes-operations-houses-2026-04-19.md`.

### Файлы
См. §4 Worker I. **Не трогать routes.tsx** — маршруты уже заложены Worker H.

### Структура
```
src/pages/operations/houses/
  index.ts                             (re-export HousesListPage, HouseDetailsPage)
  HousesListPage.tsx
  HouseDetailsPage.tsx
  tabs/
    HouseOverviewTab.tsx
    HouseOptionsTab.tsx
    HousePaymentsTab.tsx
    HouseDocumentsTab.tsx
    HouseHistoryTab.tsx
  dialogs/
    ChangeStageDialog.tsx
  components/
    HouseTypeBadge.tsx        (квадрат 32px с буквой A/B/C/D, цветной фон)
    HouseCard.tsx             (для Grid view)
```

### Houses List (`/projects/:projectId/houses`)
- **Toggle Table ↔ Grid** в header.
- **Фильтры:**
  - ToggleGroup типы: «Все / A / B / C / D» (мультивыбор).
  - Combobox опций (мультивыбор). На MVP опции захардкожены в фикстуре (10 опций): баня, гараж, терраса, сауна, бассейн, котельная, веранда, мансарда, беседка, система безопасности.
  - Select стадии.
  - Select прораб.
  - Поиск по номеру дома.
  - Кнопка «Сбросить фильтры».
- **Table view** (shadcn Table) — колонки: `[☐]`, `Тип`, `Дом №`, `Стадия + progress`, `Прораб`, `Сдача`, `Бюджет план / факт` (скрыт для foreman, conditional render), `[⚠]` overdue.
- **Grid view** — сетка `<Card>` 5 в ряд (desktop), 2 в ряд (mobile). Каждая карточка — 200px, клик → `/houses/:id`.
- **Bottom action bar** — появляется при выборе ≥1 дома (Sticky bottom): «Выбрано N домов» + [Изменить стадию ▼] + [Назначить прораба]. Только owner/director.
- **Клик на строку** → `<Link to={`/houses/${id}`}>` обёрнутый через `<Button asChild>` или полностью `<tr>` как ссылка (accessibility через `role="link"` на row). Предпочтительно — `<Link>` на ячейке с номером дома.

### House Card (`/houses/:houseId`)
- **Header:** breadcrumb `← Дома`, номер дома, Badge типа, Badge стадии, ответственный, дата сдачи.
- **5 Tabs:** Обзор / Опции / Платежи / Документы / История (shadcn `<Tabs>`).
- **Обзор** — параметры дома, выбранные опции, кнопки действий (role-gated):
  - «Перевести в стадию ▼» — DropdownMenu со следующими возможными стадиями → ChangeStageDialog (shadcn AlertDialog).
  - «Назначить прораба» — только owner/director (откроет Dialog с Combobox; на MVP можно placeholder TODO + disabled).
  - «Редактировать параметры» — только owner/director, placeholder TODO.
- **Опции** — таблица с checkbox (foreman может отмечать), inline DatePicker для «Дата установки». PATCH `/api/v1/houses/:id/options/:optionId`.
- **Платежи** — DataTable с платежами. **Для foreman:** рендерится `<Alert role="status">` «Финансовая информация недоступна для вашей роли. Обратитесь к руководителю проекта». Таблица не показывается. Для accountant/owner/director — плюс `<DropdownMenu>` «Экспорт» (CSV/Excel — enabled, 1С — disabled с tooltip).
- **Документы** — placeholder Alert «Хранилище документов будет доступно в M-OS-2», список-плейсхолдер из 3 типов документов. Кнопка «Загрузить» disabled для owner/director, скрыта для остальных.
- **История** — ScrollArea 400px, timeline аудит-событий. foreman — только stage-события (фильтрация по type, не по API-фильтру — API возвращает полный список, клиент фильтрует через roleFilter).

### API (MSW)
```
GET /api/v1/projects/:projectId/houses
  ?type=A,B  &option_ids=1,2  &stage=walls  &foreman_id=?
  → { items: [{ id, number, type, stage, overdue, foreman:{id,name}, expected_date, budget_plan?, budget_fact? }], total: 85 }
  # budget_* — undefined для foreman

GET /api/v1/houses/:houseId
  → { id, number, type, stage, expected_date, foreman, progress_pct,
      options: [{id, name, installed, installed_at}],
      payments?: [{date, amount, type, status}],   # undefined для foreman
      audit_events: [{ts, user, action, event_type: 'stage'|'payment'|'system'}] }

PATCH /api/v1/houses/:houseId/stage      body {stage}    → 200 | 403 | 409
PATCH /api/v1/houses/:houseId/options/:optionId   body {installed, installed_at}  → 200 | 403
```

Фикстура: 85 домов, 4 типа (A/B/C/D примерно 25/25/20/15 домов), 8 стадий разбросаны, 4 дома overdue (match с blocking_issues из dashboard.ts — координация через фикстуру shared IDs, если фикстура dashboard.ts **импортирует** из houses.ts — лучше так). Head решает: `mocks/fixtures/houses.ts` — источник истины, `dashboard.ts` импортирует.

### Тесты Worker I
- Unit: houses handler (фильтры, role-hiding budget, PATCH stage 409 для невозможной стадии), housesKeys, role-filter в HouseHistoryTab.
- Playwright smoke: `operations-houses.spec.ts` — список → фильтр по типу → клик на дом → открыть вкладку Опции → поставить чекбокс → сменить стадию → подтвердить в Dialog. Отдельный сценарий foreman: открыть House Card → вкладка Платежи → увидеть баннер.

### DoD Worker I
- [ ] Houses List с Table+Grid toggle, все фильтры работают
- [ ] House Card с 5 tabs, role-based rendering корректен
- [ ] 5 состояний UI на обоих экранах + на каждом tab
- [ ] data-testid конвенция
- [ ] Lint/typecheck/build/unit/e2e green
- [ ] Bundle delta <50KB gzip
- [ ] Auto-push

## 8. Бриф Worker J (Financial Reports skeleton)

### Цель
Реализовать `/reports/financial` согласно wireframe `wireframes-operations-reports-2026-04-19.md`.

### Файлы
См. §4 Worker J.

### Структура
```
src/pages/operations/reports/
  index.ts
  FinancialReportsPage.tsx
  components/
    ReportsFilters.tsx          (DateRangePicker + Select детализации)
    ReportsSummaryTable.tsx     (сводная таблица план/факт/дельта/% + sticky ИТОГО)
    ReportsDrilldownSheet.tsx   (Sheet справа с разбивкой по домам)
    ReportsExportMenu.tsx       (DropdownMenu CSV/Excel/1С)
```

### Экран
- **Доступ foreman:** на уровне OperationsLayout foreman редиректится — но продублируйте guard на самой странице (`if role==='foreman' → <Navigate>`).
- **Фильтры:**
  - DateRangePicker (нужно реализовать или использовать `react-day-picker` — проверь с Head; на MVP можно два `<input type="date">` с Label). Если полноценный DateRangePicker — это требует новой зависимости → согласовать с Head→Директор.
  - Select «По месяцу / По кварталу».
  - Кнопки «Применить» / «Сбросить».
- **Summary table:** shadcn Table с колонками Категория / Бюджет план / Факт / Дельта / %. Sticky bottom row «ИТОГО» через `<TableRow className="sticky bottom-0 bg-background font-semibold">` или CSS.
- **Drill-down:** клик на строку категории → `<Sheet>` справа (420px). В Sheet — таблица по домам (дом / план / факт).
- **Export dropdown:** CSV и Excel — enabled (MSW возвращает `Blob` с `Content-Disposition: attachment`, клик скачивает). **1С — disabled**, Tooltip: «Доступно после подключения 1С в M-OS-2». Никаких fetch-ов на реальные 1С URL.

### API (MSW)
```
GET /api/v1/reports/financial?project_id=1&date_from=...&date_to=...&group_by=month|quarter
  → { categories: [{id, name, plan, fact, delta, pct}] × 4,
      total: {plan, fact, delta, pct} }

GET /api/v1/reports/financial/category/:categoryId/drilldown?project_id=...&date_from=...&date_to=...
  → { category: 'materials', items: [{house_id, house_number, plan, fact}] × N }

GET /api/v1/reports/financial/export?format=csv|excel&...  → Blob
```

Фикстура 4 категории: Стройматериалы / Подрядчики / Коммуникации / Прочее (см. wireframe §Summary table — значения).

### Тесты Worker J
- Unit: reports handler (фильтр по датам, foreman → 403).
- Playwright smoke: `operations-reports.spec.ts` — accountant логин → /reports/financial → изменить период → увидеть обновление → клик на «Стройматериалы» → Sheet открыт → клик «Экспорт CSV» → файл скачивается (проверка `expect(page).toHaveURL` или download event).

### DoD Worker J
- [ ] Страница reports/financial работает для owner/director/accountant
- [ ] foreman редиректится на /projects/:projectId/overview
- [ ] Drill-down Sheet открывается / закрывается
- [ ] Export CSV/Excel работает, 1С disabled
- [ ] 5 состояний UI
- [ ] Lint/typecheck/build/unit/e2e green
- [ ] Auto-push

## 9. Review Head'а — чек-лист

Для каждого Worker (в таком порядке):

1. [ ] FILES_ALLOWED соблюдён (нет файлов вне списка)
2. [ ] Query Key Factory (§5.1)
3. [ ] Controlled Select (§5.2)
4. [ ] `<Button asChild><Link>` для навигации (§5.2)
5. [ ] 5 состояний UI на каждом экране / вкладке (§6.3)
6. [ ] data-testid конвенция (§6.2)
7. [ ] Role-based rendering через conditional render (не CSS hidden)
8. [ ] Mobile-responsive (Overview + Houses List обязательно; Reports — desktop-only OK)
9. [ ] Accessibility (aria-label на кнопках-иконках, label на полях, dialog focus-trap, table scope)
10. [ ] Lint / typecheck / build — без warnings
11. [ ] Unit + E2E — зелёные
12. [ ] Bundle delta измерен, <50KB gzip
13. [ ] Commits ≤10 файлов, `feat(ops):`, auto-push
14. [ ] Никаких живых интеграций

P0/P1 — возврат на доработку. P2 — в notes для следующей волны.

## 10. Сводный отчёт Head → Директор (§7.5 п.5)

После закрытия 3 Worker-PR — один сводный отчёт с:
- Вердикт (принято / возвращено / частично)
- Список файлов по Worker (agg by worker)
- Bundle delta на каждый экран
- Open questions
- Метрики волны

Далее Директор пишет **один** возврат Координатору.

## 11. Open Questions для Head (перед стартом)

- OQ1: Как в MSW handler различать роли без прохода через JWT? Предложение — query-param `?role=foreman` в test-окружении + helper `getCurrentRoleFromMsw()` на основе последнего `/auth/login` ответа. Head решает, фиксирует в брифах Worker'ов.
- OQ2: DateRangePicker — пишем свой на базе двух `<input type="date">` или добавляем `react-day-picker` в зависимости? Предпочтительный — свой, без новой зависимости (Решение §3 регламента — dependencies через Директор→Координатор).
- OQ3: shadcn компоненты (progress, avatar, dropdown-menu, toggle-group, sheet уже есть) — Worker H первым добавляет через `npx shadcn-ui add` в scaffold-коммит; Worker I и J — используют. Head подтверждает.

---

**Старт:** после прочтения Head'ом и решения OQ1-3 Head сообщает Директору — Директор просит Координатора-транспорт спавнить 3 дев-вызова с дословными брифами из §6/§7/§8 этого документа.

**Повторю ключевое:** Worker H **первым** merge-ится. Worker I и J разрабатывают параллельно, но merge только **после** Worker H.
