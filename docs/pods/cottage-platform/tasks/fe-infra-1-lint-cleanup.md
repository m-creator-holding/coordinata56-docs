# Бриф для frontend-head: FE-INFRA-1 — Lint Gate Cleanup

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6 — Директор
  не вызывает Head напрямую)
- **Тип:** тех-долг (инфраструктура линтинга), мини-батч
- **Источник:** round-1 review FE-W1-1 Companies —
  `docs/reviews/fe-w1-1-companies-round-1-head-review.md`, раздел
  «Pre-existing ESLint ошибки» и «Резюме для Директора»
- **Блокирующее условие:** `npm run lint` = exit 0 — моё условие APPROVE
  FE-W1-1 и обязательный gate перед стартом FE-W1-2 Users.

---

## 0. Контекст — зачем этот батч

В round-1 FE-W1-1 я (Директор) выдал условный APPROVE с одним дополнительным
требованием: `npm run lint` обязан проходить зелёным до старта следующего
admin-экрана. Head зафиксировал в review, что проблема — **не в коде
FE-W1-1**, а в pre-existing дефектах инфраструктуры линтера:

- `src/api/generated/schema.d.ts` — 374 ошибки в **генерируемом файле**
  (`openapi-typescript` выдаёт index-signatures вместо `Record<>`, что бьёт
  правило `@typescript-eslint/consistent-indexed-object-style`). Файл
  перегенерируется командой `npm run codegen`, мы его не пишем руками, —
  значит он не должен линтиться в принципе.
- `playwright.config.ts`, `vitest.config.ts` — parsing-errors, потому что
  эти файлы не включены ни в один `tsconfig`, упомянутый в
  `parserOptions.project` ESLint'а. (Важно: `vite.config.ts` уже в
  `ignorePatterns` — его не трогаем, он работает корректно.)
- `src/components/ui/table.tsx` — **2 ошибки** `react/prop-types` на
  строках 72 (`TableHead`, `React.ThHTMLAttributes<...>`) и 87
  (`TableCell`, `React.TdHTMLAttributes<...>`). Остальные 6 компонентов
  того же файла (Table / TableHeader / TableBody / TableFooter / TableRow
  / TableCaption) — используют обычный `React.HTMLAttributes<...>` и не
  бьют правило. Баг — локальный, только для `Th/Td`-вариантов.

Итого: 380 ошибок (374 + 2 + 2 parsing). Все — инфраструктурные,
**ни одна не относится к продакшн-коду FE-W1-1**. Именно поэтому вывожу
их в отдельный батч.

Почему это критично:
1. Без зелёного lint'а нельзя подключить pre-commit hook / CI gate — а
   `regulation/backend` уже настроил CI `lint-migrations`, и фронтенд
   отстаёт по зрелости.
2. Каждый следующий экран (Users, Roles, ещё 4) **должен мериться
   зелёным lint'ом** — если гейт сломан сейчас, будущие регрессии
   проскочат незамеченно.
3. Мой собственный регламент `departments/frontend.md` §6.5 говорит:
   `npm run lint && npm run typecheck && npm run build` — обязаны
   проходить **без warnings**. Сейчас эта норма нарушена на уровне
   baseline.

Правило: **только конфигурация**. Продакшн-код (`src/pages/**`,
`src/shared/**`, `src/hooks/**`, `src/api/**` кроме генерируемого) —
**не трогаем**. Никаких рефакторов «заодно».

---

## 1. Scope (ровно 3 изменения)

### 1.1 `.eslintignore` — создать новый файл

Причина: уже есть `ignorePatterns` в `.eslintrc.cjs` (строка 13:
`['dist', '.eslintrc.cjs', 'postcss.config.js', 'vite.config.ts',
'tailwind.config.ts', 'codegen.ts', 'e2e/**']`), но он не закрывает
генерируемые файлы и стандартные каталоги сборки. Аргумент в пользу
**отдельного `.eslintignore`** (а не расширения `ignorePatterns`):

- `.eslintignore` — стандартный конвенциональный файл, который
  видят все ESLint-инструменты (IDE, pre-commit, CI) одинаково.
- Разделение ответственности: `ignorePatterns` — для конфигурационных
  исключений (сам `.eslintrc.cjs` исключает себя); `.eslintignore` —
  для артефактов (dist, coverage, generated).
- При расширении `ignorePatterns` любая опечатка роняет весь парсинг
  конфига; `.eslintignore` — простой текстовый список, ломать нечего.

Содержимое (строго):

```
dist/
coverage/
node_modules/
src/api/generated/
public/mockServiceWorker.js
```

Пояснения:
- `src/api/generated/` — закрывает **всю папку**, не только
  `schema.d.ts`. Если codegen в будущем сгенерирует второй файл
  (например, `queries.ts`), он автоматически подпадёт под ignore.
- `public/mockServiceWorker.js` — сгенерированный MSW worker-файл,
  не должен линтиться (сейчас ESLint его не видит из-за `--ext ts,tsx`,
  но страховка не мешает и явнее показывает намерение).
- `node_modules/` — формально ESLint и так игнорирует, но явная строка
  защищает от будущих конфиг-ошибок.

### 1.2 `.eslintrc.cjs` — подключить `tsconfig.node.json` в parser

Причина: `tsconfig.node.json` (строки 2–11) уже **явно включает**
`vite.config.ts`, `vitest.config.ts`, `playwright.config.ts` через
`"include"`. Но ESLint parser (`.eslintrc.cjs` строка 18,
`project: ['./tsconfig.json', './tsconfig.test.json']`) этот файл
не подключает — отсюда parsing-errors.

**Минимальная хирургическая правка:**

```diff
-    project: ['./tsconfig.json', './tsconfig.test.json'],
+    project: ['./tsconfig.json', './tsconfig.test.json', './tsconfig.node.json'],
```

Один массивный элемент. Новые tsconfig-файлы **не создаём** —
существующий `tsconfig.node.json` уже содержит нужную конфигурацию
(composite + includes всех трёх конфигов сборки). Исправляем только
то, что ESLint о нём не знал.

Обоснование по принципу Владельца msg 817–818 «хирургические правки,
не over-engineering»: создавать отдельный `tsconfig.eslint.json` —
избыточно, когда подходящий tsconfig уже существует.

### 1.3 `src/components/ui/table.tsx` — починить 2 prop-types ошибки

Причина: ESLint-плагин `react/prop-types` имеет известный баг с
`React.ThHTMLAttributes<T>` / `React.TdHTMLAttributes<T>` в inline-дженериках
`forwardRef` — он не умеет извлекать `className` из типа и требует
явной prop-types декларации. Для обычного `React.HTMLAttributes<T>`
(которое используют TableHeader / TableRow / TableBody и т.д.) он
отрабатывает корректно. Поэтому бьют только `TableHead` (72) и
`TableCell` (87), а остальные 6 компонентов того же файла — нет.

**Рекомендованный подход** — выделить именованные интерфейсы для
проблемных компонентов по образцу `ButtonProps` (button.tsx, строки
36–40). Это шаблон shadcn, который в проекте уже применён как
стандарт для `Button`. Минимальный диф:

```tsx
// Перед TableHead (строка ~69):
export interface TableHeadProps
  extends React.ThHTMLAttributes<HTMLTableCellElement> {}

const TableHead = React.forwardRef<HTMLTableCellElement, TableHeadProps>(
  ({ className, ...props }, ref) => (
    <th ref={ref} className={cn(...)} {...props} />
  )
)

// Перед TableCell (строка ~84):
export interface TableCellProps
  extends React.TdHTMLAttributes<HTMLTableCellElement> {}

const TableCell = React.forwardRef<HTMLTableCellElement, TableCellProps>(
  ({ className, ...props }, ref) => (
    <td ref={ref} className={cn(...)} {...props} />
  )
)
```

Семантически эквивалентно оригиналу (чистый extends, никаких новых
полей). Остальные 6 компонентов **не трогаем** — у них правило не
бьёт, рефакторы «для единообразия» явно запрещены (правило Владельца
«хирургические правки»).

Альтернатива: `// eslint-disable-next-line react/prop-types` на
двух строках. **Отвергаю** — директивы отключения правил без
обоснования запрещены `CLAUDE.md`, да и шумнее в коде.

---

## 2. FILES_ALLOWED (строго, dev не выходит за этот список)

```
frontend/.eslintignore                         (новый файл, create)
frontend/.eslintrc.cjs                         (edit — только строка 18)
frontend/src/components/ui/table.tsx           (edit — только TableHead и TableCell)
```

**Запрещено трогать:**
- Любые файлы в `frontend/src/pages/`, `frontend/src/shared/`,
  `frontend/src/hooks/`, `frontend/src/providers/`,
  `frontend/src/mocks/` — это продакшн-код FE-W1-1, он только что
  прошёл round-1 APPROVE, не регрессировать.
- Любые другие shadcn-примитивы в `frontend/src/components/ui/`
  (alert-dialog, button, dialog, input и т.д.) — lint по ним чистый,
  правки не нужны.
- `backend/` — не наш пост.
- `tsconfig*.json` — **не меняем ни один**. Существующий
  `tsconfig.node.json` уже правильно включает нужные конфиги, нам
  достаточно подключить его в ESLint parser.
- `package.json`, `package-lock.json`, `vite.config.ts`,
  `playwright.config.ts`, `vitest.config.ts` — не меняем. Цель —
  починить линт **не трогая сами конфиги сборки**.
- `docs/agents/departments/frontend.md` — никаких новых стандартов,
  это тех-долг, а не источник паттернов.

---

## 3. Definition of Done

Четыре обязательных gate. Все должны быть зелёными до передачи
Директору. Head проверяет каждый по чек-листу:

| # | Gate | Команда | Ожидание |
|---|---|---|---|
| 1 | Lint | `npm run lint` | **exit 0**, 0 errors, 0 warnings |
| 2 | Typecheck | `npm run typecheck` | **exit 0**, 0 errors |
| 3 | Build | `npm run build` | успешен, bundle-delta = 0 (конфиг-изменения не влияют на бандл) |
| 4 | E2E compile | `npx playwright test --list` | Playwright успешно парсит spec-файлы (без запуска — браузеры могут отсутствовать) |

Дополнительные проверки для Head'а при review:
- `.eslintignore` не содержит лишних записей (строго 5 строк из §1.1).
- В `.eslintrc.cjs` изменена **ровно одна строка** (project-массив),
  больше ничего.
- В `table.tsx` изменены **ровно два компонента** (TableHead,
  TableCell), остальные 6 — без изменений (diff должен это показать
  явно).
- Bundle-delta = 0 подтверждается: до и после размер `AdminApp-*.js`
  и `index-*.js` совпадают байт-в-байт или отличаются на < 100 байт
  (изменения типа не должны влиять на runtime).
- `npm run test` (unit-тесты vitest) — остаётся зелёным. Конфиг-правки
  не должны ничего сломать, но проверить обязаны.

---

## 4. Процедура

Мини-батч, 1 dev, серийно (не параллельный split):

1. **Head** получает этот бриф от Координатора, раздаёт dev'у
   distribution-задачу со ссылкой на §1 и §2. Бриф dev'а — короткий
   (≤ 30 строк), просто переформулированная §1 + FILES_ALLOWED +
   DoD-команды.
2. **Dev** (`frontend-dev-1`):
   - читает `.eslintrc.cjs`, `tsconfig.node.json`,
     `src/components/ui/table.tsx`, `src/components/ui/button.tsx`
     (как образец для TableHeadProps / TableCellProps);
   - создаёт `.eslintignore`;
   - правит `.eslintrc.cjs` (одну строку);
   - правит `table.tsx` (два компонента);
   - прогоняет четыре DoD-команды локально;
   - отдаёт Head'у.
3. **Head** делает review по DoD-чек-листу (§3), проверяет diff на
   минимальность (по §2 FILES_ALLOWED), подтверждает bundle-delta = 0.
4. **Head** передаёт Директору.
5. **Директор** (я) принимает или возвращает.
6. **Координатор** коммитит + push.

Оценочная длительность: 20–40 минут чистого времени dev'а + 10 минут
review Head'а. Полный цикл ≈ 1 час.

---

## 5. Нужен ли отдельный reviewer round?

**Нет.** Head-review достаточно, по образцу FE-W1-1 round-1. Причины:

1. Скоуп ровно три файла, две из которых — конфигурация (тривиальный
   diff, минимальная когнитивная нагрузка на ревьюера).
2. Никакого продакшн-кода, никаких новых паттернов, никакого API.
3. DoD — четыре команды, любая из которых красная = автоматический
   reject Head'ом, без субъективной интерпретации.
4. Advisory `reviewer` — L4 советник, его цикл тяжеловат для
   конфиг-правок. Он нужен там, где есть неочевидная бизнес-логика
   или безопасность.

Head-review + мой вердикт Директора — достаточный уровень для
мини-батча чисто-инфраструктурного характера.

---

## 6. Что НЕ делаем в этом батче (явно)

- **Не** настраиваем CI-gate для `npm run lint`. Это отдельная работа
  infrastructure-director'а (когда он будет активирован) после того,
  как lint стабильно зелёный локально. Здесь — только локальная база.
- **Не** добавляем pre-commit hook. Это отдельная задача, сначала
  infrastructure-director должен согласовать подход (husky vs
  pre-commit vs нативный git hooks) — RFC-отдельно.
- **Не** рефакторим другие shadcn-компоненты «для единообразия».
  Правки только в `table.tsx`, только в двух местах.
- **Не** обновляем `departments/frontend.md` — это не новый стандарт,
  а фикс инфраструктуры. Регламент остаётся v1.1.
- **Не** ставим новые npm-зависимости. Чисто конфигурация.
- **Не** меняем `package.json` scripts — lint/typecheck/build уже
  настроены корректно, проблема была только в parser-project-массиве.

---

## 7. Gating-влияние на FE-W1-2

После close FE-INFRA-1 (lint зелёный локально) **FE-W1-2 Users**
может стартовать. До close — не стартует, т.к. он унаследует
сломанный lint-gate и не сможет пройти собственный DoD §6.5.

Вопрос о параллельности FE-W1-2 с backend-PR#2 RBAC v2 (MSW-моки vs
ожидание реального API) — выделен в ответ Координатору на входящий
вопрос Директора (не часть этого брифа).

---

## История версий

- v1.0 — 2026-04-18 — первая редакция брифа, основана на review
  `docs/reviews/fe-w1-1-companies-round-1-head-review.md` раздел
  «Pre-existing ESLint ошибки» и «Резюме для Директора».
