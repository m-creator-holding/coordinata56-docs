# Бриф для frontend-head: FE-W1-1 Companies — Round 1 Fix

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6 — Директор
  не вызывает Head напрямую)
- **Тип:** доработка (round 1) по результатам head-review
- **Батч-родитель:** `FE-W1-1-companies`
- **Review-файл (ссылочный):** `docs/reviews/fe-w1-1-companies-head-review.md`
- **Родительский бриф:** `docs/pods/cottage-platform/tasks/fe-w1-1-companies.md`
- **Вердикт Директора по round-0:** **request-changes** (не reject, не approve)

---

## 0. Кратко — что произошло и почему round-1

Батч FE-W1-1 выполнен качественно: все 5 состояний UI есть, архитектурный
паттерн (shared/api, Zod, RHF, TanStack Query, MSW, codegen) реализован
чисто. Head вынес условный APPROVE с 1 P1 и 5 P2, плюс не замерен bundle
delta (DoD §9).

Директор не может принять батч «как есть» по двум причинам:

1. **P1 блокирует E2E** — два теста `field-company-kpp` упадут. Commit
   батча, который не проходит свой же smoke-тест — автоматический брак.
2. **Bundle delta — требование DoD §9**. Без цифры нельзя подтвердить,
   что шаблон укладывается в бюджет +50 KB gzip — а следующие 6
   экранов будут мерить свой delta относительно baseline после этого
   батча. Без замера baseline плывёт.

Но этого мало. Батч задаёт **эталон для следующих 6 admin-экранов**
(Users, Roles, Permissions, Company Settings, Integration Registry,
System Config). Если пропустить в `main` P2, которые повторятся в
шаблоне — каждый из 6 будущих батчей унаследует дефект, и исправлять
придётся шестью PR вместо одного. Поэтому в round-1 забираем не только
блокер, но и **два P2, которые затронут паттерн**.

**Три P2 — чистая косметика/локальная специфика** — уходят в отдельный
P2-бэклог-батч и не блокируют merge FE-W1-1.

---

## 1. Разбиение P2 — что в round-1, что в бэклог

### Round-1 (в этом батче, до commit)

| Код | Пункт | Почему сейчас |
|---|---|---|
| **P1-1** | testid на поле КПП | Блокирует E2E, регрессия happy-path |
| **DoD §9** | Замер bundle delta | Обязательное требование DoD, задаёт baseline для FE-W1-2..7 |
| **P2-3** | Controlled Select в BankAccountDialog (`value` вместо `defaultValue`) | **Паттерн повторится на всех формах admin-экранов с Select** (Users — роль; Permissions — scope; Integration Registry — тип; Settings — валюта/часовой пояс). Если оставить uncontrolled как эталон — все 6 экранов унаследуют баг edit-синхронизации. Это не косметика, это архитектурный дефект шаблона. |
| **P2-1** | `<Link>` вместо `<Button onClick={navigate}>` на «Редактировать» | Семантика навигации vs действия — повторится на всех карточках (Users, Roles, Permissions, Integration Registry). Эталон должен быть правильный, иначе каждый из 6 экранов будет копировать антипаттерн. Также E2E уже ищет `role=link` — исправить сразу, чтобы не переписывать тесты в 6 будущих батчах. |

### P2-бэклог (отдельный мини-батч перед FE-W1-2 или внутри FE-W1-2)

| Код | Пункт | Почему не сейчас |
|---|---|---|
| **P2-2** | `type="search"` в поле поиска списка | Локальная правка одного инпута. Не влияет на эталон (на Roles/Permissions поиска может не быть), паттерн списков уже заложен. Исправим когда увидим второй список (Users) — там же проверим, что правка действительно переиспользуется. |
| **P2-4** | `beforeEach` сброс MSW-хранилища в E2E | Не критично при текущем объёме (1 spec-файл, ≤ 10 тестов). Починим при появлении второго spec-файла в FE-W1-2 — там же заложим единый тестовый helper `resetCompanyFixtures()`, вызываемый из `beforeEach` всех spec-файлов. |
| **P2-5** | `role="row"` на `<TableRow>` | Чистая косметика ARIA, не влияет на доступность и не повторяется как паттерн (лишний атрибут только в одном месте). Убрать при ближайшем касании файла. |

**Head обязан зафиксировать бэклог-пункты** в `project_tasks_log.md`
(раздел «Frontend — technical debt»), с ссылкой на этот бриф и на
review-файл round-0. Это не должно потеряться.

---

## 2. Скоуп round-1 — закрытый список правок

Любое «заодно и X» запрещено. Если dev увидит что-то сверх списка —
через Head к Директору с эскалацией.

### Правка 1. P1-1: data-testid на поле КПП

**Файл:** `frontend/src/pages/admin/companies/CompanyFormPage.tsx`
(~строка 300, блок КПП)

Добавить `data-testid="field-company-kpp"` на `<Input id="kpp" ...>`.

Паттерн конвенции §2.8 родительского брифа — `field-company-<поле>`.
Head проверяет: все остальные поля формы уже следуют конвенции,
убедиться что они уже с testid (проверка уязвимая — если dev забыл
на КПП, мог забыть и на другом поле). Беглый аудит всех полей формы
по конвенции — обязателен, не ограничиваться одним КПП.

### Правка 2. P2-3: Controlled Select в BankAccountDialog

**Файл:** `frontend/src/pages/admin/companies/dialogs/BankAccountDialog.tsx`
(строки 263-270 и 293-302)

Заменить:
```tsx
<Select defaultValue="RUB" ...>
<Select defaultValue="main" ...>
```

На controlled-паттерн через RHF `Controller` **или** через
`value={watch('currency')}` + `onValueChange={(v) => setValue('currency', v, { shouldValidate: true, shouldDirty: true })}`.

**Head выбирает конкретный паттерн** (Controller vs watch/setValue) и
**фиксирует его в `docs/agents/departments/frontend.md`** как обязательный
стандарт отдела для Radix Select + RHF. Этот стандарт пойдёт в следующие
6 экранов, поэтому выбранный вариант должен быть продуман: какой короче
по коду, какой меньше ре-рендерит дерево, какой понятнее читается.

**Acceptance:** открыть BankAccountDialog в режиме редактирования
существующего счёта с `currency='USD'` (добавить в фикстуру если нет)
— Select показывает «USD», не «RUB». То же для `purpose='reserve'`.

### Правка 3. P2-1: `<Link>` вместо `<Button onClick>` на «Редактировать»

**Файл:** `frontend/src/pages/admin/companies/CompanyDetailsPage.tsx`
(строки 154-160)

Заменить:
```tsx
<Button onClick={() => navigate(`/admin/companies/${id}/edit`)}>
  Редактировать
</Button>
```

На:
```tsx
<Button asChild>
  <Link to={`/admin/companies/${id}/edit`}>Редактировать</Link>
</Button>
```

Паттерн `<Button asChild><Link>` — shadcn-канон для «кнопка-ссылка». Head
фиксирует этот паттерн в `docs/agents/departments/frontend.md` (рядом с
Select-паттерном), чтобы все 6 будущих карточек использовали то же.

Правило: **если действие меняет URL — используем `<Link>` (обёрнутый в
Button asChild при необходимости button-стиля). Если действие мутирует
state/data — используем `<Button>`.** Это семантика, WCAG, и правильное
поведение middle-click / Ctrl+click (открыть в новой вкладке).

**Acceptance:** E2E-тест `getByRole('link', { name: /редактировать/i })`
находит элемент и клик по нему переводит на `/admin/companies/:id/edit`.

### Правка 4. DoD §9: Замер bundle delta

Dev обязан:

1. Сделать `npm run build` на **baseline** (ветка до FE-W1-1 или
   commit `72b00bd` FE-W1-0). Зафиксировать размер `admin-companies`
   chunk (если его ещё нет — общий размер `admin.*.js` gzip).
2. Сделать `npm run build` на **после этого батча (round-1)**.
   Зафиксировать размер `admin-companies` chunk.
3. Вычислить delta в KB gzip. Формат отчёта:
   ```
   Baseline (commit 72b00bd):
     admin bundle (combined): XX KB gzip
   After FE-W1-1 round-1:
     admin-companies chunk: YY KB gzip
     delta: +ZZ KB gzip (budget: +50 KB gzip)
   ```
4. Приложить отчёт к commit message (или в PR description, или
   в review-файл round-1 head'а — Head выбирает канал).

**Инструменты:** `rollup-plugin-visualizer` (уже в scaffold, проверить);
либо `vite build --mode production` + ручной замер `du -b` на gzip-версии
chunk'а. Head даёт dev конкретную команду, не оставляет на усмотрение.

**Если delta > 50 KB:** round-1 отклоняется, dev профилирует. Типичные
виновники — `date-fns` с полным локалем, `lucide-react` с tree-shake
проблемами, случайный `lodash` вместо нативного, дублирование кода
между `src/shared/api` и `src/api/generated`.

### Правка 5. Повтор E2E после правок 1-3

После правок 1-3 — прогнать `npm run test:e2e admin-companies.spec.ts`
локально. **Все тесты зелёные** (включая два теста `field-company-kpp`
и тест с `getByRole('link')` если он есть).

Если Playwright ранее не настроен в CI — локальный прогон со
скриншотом / лог-файлом `test-results.json` прикладывается к
commit/review. Head проверяет, что все тесты passed (не skipped,
не timeout).

---

## 3. Обязательства Head'а по документации эталона

Этот round-1 — **последняя возможность зафиксировать эталон** для
следующих 6 admin-экранов без «догоняющих» правок. После merge round-1
следующие батчи будут копировать эти паттерны, и менять их будет
в 6 раз дороже.

Head до закрытия round-1 обновляет или создаёт:

1. **`docs/agents/departments/frontend.md`** — секции «Стандарты отдела»:
   - паттерн Controlled Select + RHF (из правки 2)
   - паттерн `<Button asChild><Link>` для навигации (из правки 3)
   - паттерн `companyKeys` — query key factory (хорошее решение dev'а,
     зафиксировать как обязательный стандарт для api-слоёв всех сущностей:
     `all / lists / list(filters) / details / detail(id) / nested(id)`)
   - конвенция testid: `page-<entity>-<mode>`, `field-<entity>-<name>`,
     `btn-<entity>-<action>`, `dialog-<name>`, `row-<entity>-{id}`
   - конвенция 5 состояний UI (loading/empty/error/success/dialog-confirm)
     как обязательная матрица

2. **`project_tasks_log.md`** — внести 3 P2-бэклог-пункта
   (P2-2 search, P2-4 MSW reset, P2-5 role="row") с привязкой к
   этому брифу.

3. **Round-1 review-файл** — `docs/reviews/fe-w1-1-companies-round-1-head-review.md`
   по образцу round-0, с чек-листом: P1-1 fixed, P2-3 fixed, P2-1 fixed,
   bundle delta measured, E2E green. Head распределяет работу dev'у,
   потом ревьюит сам, потом передаёт Директору на финальную приёмку.

Если `docs/agents/departments/frontend.md` ещё в версии v0.1 — Head
предупреждает Директора, и обновление до v1.0 с этими стандартами
идёт отдельной заявкой в комиссию Governance (не блокирует round-1,
но фиксируется как задача Head'а на ближайшую неделю).

---

## 4. Жёсткие ограничения (red zones)

- **Не трогать** файлы, не перечисленные в §2. Даже рефакторинги имен.
  Если dev увидит что-то сверх — эскалация через Head.
- **Не добавлять новые зависимости.** Никакой `npm install X` в этом
  round-1 — только правки существующего кода и конфигов.
- **Не менять архитектуру shared/api/validation/data.** Она уже
  согласована, правки round-1 — только то, что в §2.
- **Backend — FORBIDDEN.** Любые `.py` в diff → reject.
- **Не менять `src/pages/admin/*` кроме указанных трёх файлов**
  (CompanyFormPage, BankAccountDialog, CompanyDetailsPage).
- **MSW-фикстуры** — можно расширить на 1 счёт с `currency='USD'` для
  проверки правки 2 (acceptance), если такого счёта ещё нет. Любые
  другие изменения фикстур — эскалация.

---

## 5. DoD round-1 (чек-лист Директора для финальной приёмки)

Директор примет round-1 только если **все пункты зелёные**:

- [ ] **P1-1:** `data-testid="field-company-kpp"` присутствует на
  `<Input id="kpp">` в CompanyFormPage.tsx
- [ ] **Аудит testid:** Head подтвердил в review, что все остальные
  поля формы следуют конвенции `field-company-<name>` (не только КПП)
- [ ] **P2-3:** BankAccountDialog использует controlled Select для
  валюты и назначения; паттерн задокументирован в
  `docs/agents/departments/frontend.md`
- [ ] **P2-3 acceptance:** открытие диалога в edit-режиме с USD/reserve
  показывает USD/reserve, не дефолты; (ручной / E2E-тест)
- [ ] **P2-1:** «Редактировать» на CompanyDetailsPage — `<Button asChild><Link>`;
  паттерн задокументирован в `docs/agents/departments/frontend.md`
- [ ] **P2-1 acceptance:** `getByRole('link', { name: /редактировать/i })`
  находит элемент; middle-click работает (ручная проверка Head)
- [ ] **Bundle delta измерена** и приложена к round-1 (числа + метод);
  delta ≤ +50 KB gzip
- [ ] **E2E:** `npm run test:e2e admin-companies.spec.ts` — все тесты
  passed (скрин/лог прилагается Head)
- [ ] **Lint / typecheck / build** проходят без warnings
- [ ] **`companyKeys` паттерн** занесён в `docs/agents/departments/frontend.md`
  как обязательный стандарт query key factory
- [ ] **P2-бэклог (P2-2, P2-4, P2-5)** занесён в `project_tasks_log.md`
  с ссылкой на round-0 review и этот бриф
- [ ] **Файлы diff** — только те, что в §2; ни одного forbidden
- [ ] **Коммит ещё не сделан** — ждём финального вердикта Директора
  после round-1 head-review

---

## 6. Процедура

1. **Координатор** получает этот бриф от Директора, передаёт Head
   (паттерн «Координатор-транспорт» v1.6).
2. **Head** распределяет правки dev'у с явными FILES_ALLOWED:
   - `frontend/src/pages/admin/companies/CompanyFormPage.tsx`
   - `frontend/src/pages/admin/companies/dialogs/BankAccountDialog.tsx`
   - `frontend/src/pages/admin/companies/CompanyDetailsPage.tsx`
   - `frontend/src/mocks/fixtures/companies.ts` (опционально, только для acceptance P2-3)
   - `frontend/e2e/admin-companies.spec.ts` (если нужно добавить тест edit-режима USD)
3. **Dev** выполняет правки, замеряет bundle, прогоняет E2E.
4. **Head** ревьюит, пишет `round-1-head-review.md`, передаёт
   Координатору → Директору.
5. **Директор** финальная приёмка по чек-листу §5 — approve / новая
   итерация round-2.
6. **Координатор** делает commit (включая auto-push на GitHub по
   правилу Владельца msg 1325), только после approve Директора.

## 7. История версий

- v1.0 — 2026-04-18 — frontend-director, round-1 fix-бриф после
  round-0 head-review с 1 P1 + 5 P2 + отсутствующим bundle delta.
