# Ревью: FE-W1-1 Companies — Head Review

- **Дата:** 2026-04-18
- **Ревьюер:** frontend-head (L3)
- **Батч:** FE-W1-1-companies
- **Статус:** УСЛОВНЫЙ APPROVE — 1 замечание P1 требует правки до коммита, 5 замечаний P2

---

## Итоговый вердикт

Батч в целом выполнен качественно. Архитектурный паттерн (shared/api, shared/validation, shared/data, MSW, RHF+Zod, TanStack Query) реализован корректно и пригоден как эталон для следующих шести экранов. Все 5 состояний UI покрыты, структура файлов соответствует брифу, codegen-типы актуальны, оба optimistic update реализованы с откатом при ошибке, BIK autocomplete работает, breadcrumb присутствует.

Одно замечание уровня P1 (data-testid для поля КПП отсутствует — E2E-тест обращается к несуществующему атрибуту и гарантированно упадёт). Остальные замечания — P2, технический долг.

---

## Чек-лист DoD (§5.3 брифа)

| Пункт | Статус | Примечание |
|---|---|---|
| Все 4 роута открываются, back-navigation работает | OK | `/admin/companies`, `/new`, `/:id`, `/:id/edit` — все в routes.tsx |
| Codegen-типы актуальны | OK | schema.d.ts содержит CompanyRead, CompanyCreate, BankAccountRead, BankAccountUpdate, CompanyUpdate |
| Структура файлов соответствует §2.2 | OK | Все 11 файлов на месте, CompanyFormWrappers.tsx — обоснованное дополнение для lazy() |
| Все 5 состояний UI на каждом экране | OK | loading (Skeleton), empty (иконка+CTA), error (Banner+Refetch), success (toast+redirect), dialog-confirm (AlertDialog) |
| Zod-схемы валидируют ИНН/КПП/ОГРН/БИК | OK | checkInn10/checkInn12 по алгоритму ФНС, superRefine для условной логики |
| BIK-каталог — 10 записей, автозаполнение | OK | 10 банков, findByBik(), useEffect в BankAccountDialog |
| MSW-хэндлеры покрывают весь CRUD + ошибки | OK | ADR 0005 envelope, 404 и 422 реализованы, проверка ALREADY_INACTIVE |
| Все aria-labels на месте, testid по конвенции | P1 | `field-company-kpp` отсутствует (см. замечание P1-1) |
| npm run lint / typecheck / build | OK | По условию задачи — зелёные |
| npm run test:e2e проходит локально | РИСК | Тест обращается к `field-company-kpp` — упадёт (см. P1-1) |
| Bundle delta ≤ +50 KB gzip | НЕ ПРОВЕРЯЛОСЬ | Dev обязан замерить и приложить delta к коммиту |
| Нет изменений в forbidden-файлах | OK | DashboardPage, HousesPage, FinancePage и прочие запрещённые файлы не тронуты |

---

## Замечания P1 (до коммита)

### P1-1. `data-testid="field-company-kpp"` отсутствует в CompanyFormPage.tsx — E2E упадёт

**Файл:** `frontend/src/pages/admin/companies/CompanyFormPage.tsx`, строки 300-317 (блок КПП)  
**Файл:** `frontend/e2e/admin-companies.spec.ts`, строки 167 и 177

E2E-тест содержит два обращения к `page.getByTestId('field-company-kpp')`:
- тест «для ИП поле КПП скрыто» (строка 167) — ожидает `not.toBeVisible()`
- тест «для ООО поле КПП присутствует» (строка 177) — ожидает `toBeVisible()`

В реализации поле КПП (`<Input id="kpp" ...>`) не имеет `data-testid`. По конвенции §2.8 брифа поле формы должно иметь `data-testid="field-company-kpp"`. Без этого оба теста завершатся с ошибкой «locator not found».

**Правка:** добавить `data-testid="field-company-kpp"` на `<Input id="kpp"`.

---

## Замечания P2 (технический долг, не блокируют коммит)

### P2-1. Кнопка «Редактировать» в CompanyDetailsPage — `<Button>`, а не `<Link>`; E2E ищет `role=link`

**Файл:** `frontend/src/pages/admin/companies/CompanyDetailsPage.tsx`, строки 154-160  
**Файл:** `frontend/e2e/admin-companies.spec.ts`, строка 128

Тест `getByRole('link', { name: /редактировать/i })` не найдёт `<Button onClick={navigate(...)}>`. Сейчас тест не запускается в CI, но при первом прогоне упадёт. Рекомендуется либо заменить Button на `<Button asChild><Link ...>`, либо изменить локатор теста на `getByRole('button', { name: /редактировать/i })`. Семантически правильнее — `<Link>` (навигация, не действие).

### P2-2. Поиск в CompaniesListPage не имеет `role="search"` — тест использует `getByRole('searchbox')`

**Файл:** `frontend/src/pages/admin/companies/CompaniesListPage.tsx`, строки 156-164  
**Файл:** `frontend/e2e/admin-companies.spec.ts`, строка 53

`getByRole('searchbox')` находит `<input type="search">`. Сейчас поле рендерится как `<Input>` без явного `type="search"`, что даёт `type="text"`. Playwright найдёт его по `getByRole('textbox')`, но не по `getByRole('searchbox')`. Либо добавить `type="search"` к Input, либо поставить `data-testid` и использовать его в тесте.

### P2-3. Валюта и назначение в BankAccountDialog используют `defaultValue`, а не `value` — состояние не синхронизируется при редактировании

**Файл:** `frontend/src/pages/admin/companies/dialogs/BankAccountDialog.tsx`, строки 263-270 и 293-302

`<Select defaultValue="RUB">` и `<Select defaultValue="main">` — uncontrolled. При открытии диалога в режиме edit `reset({...currency: 'USD'...})` обновит RHF-поле, но Select останется на дефолте «RUB», потому что Radix Select не реагирует на `defaultValue` повторно после монтирования. Нужно заменить `defaultValue` на `value={watch('currency')}` и `value={watch('purpose')}`. Это паттерн, который войдёт в следующие шесть экранов — зафиксировать как обязательный.

### P2-4. `resetCompanyFixtures()` не вызывается между E2E-тестами — тесты могут влиять друг на друга

**Файл:** `frontend/e2e/admin-companies.spec.ts`

Тест «успешное создание компании» (строка 181) мутирует in-memory хранилище MSW через POST. Если тесты запускаются в одном браузерном процессе без перезагрузки страницы между suite, состояние хранилища переносится. Стандартное решение — добавить `test.beforeEach` с `page.goto('/')` или API-вызов `/_reset` (MSW-хэндлер для тестов). Для текущего объёма не критично, но при росте числа тестов создаст нестабильность.

### P2-5. `TableRow` с `role="row"` внутри `<tbody>` — дублирование ARIA-роли

**Файл:** `frontend/src/pages/admin/companies/CompaniesListPage.tsx`, строка 276

`<TableRow role="row" ...>` — `<tr>` уже имеет implicit role `row` в контексте таблицы. Явное `role="row"` не нарушает доступность, но является избыточным по ARIA-spec. Убрать явный атрибут.

---

## Отдельные наблюдения для Директора

**1. Bundle budget — не замерен.** Dev не приложил delta gzip. Это пункт DoD §9 брифа. Директор при финальном вердикте должен потребовать замер перед merge.

**2. Паттерн `companyKeys` (query key factory) — хорошее решение, рекомендуется зафиксировать как обязательный стандарт** для следующих шести экранов. Структура `all/lists/list(filters)/details/detail(id)/bankAccounts(id)` чистая и позволяет гранулярную инвалидацию.

**3. TODO-поля (ogrn/legal_address/director_name) оформлены правильно** — через `CompanyReadExtended` / `CompanyCreateExtended` с явными TODO-комментариями. Когда backend расширит схему — правка в одном месте. Паттерн пригоден для тиражирования.

**4. Вопрос 1 из §8 брифа (механика деактивации DELETE vs POST /deactivate)** — реализован вариант A (DELETE → 200 + CompanyRead), что соответствует тому, как обозначено в коде комментарием «решение Координатора». Если Координатор не давал явного ответа — это замечание для Директора, не блокер батча.

---

## Резюме для Директора

Батч готов к коммиту при условии:
- Исправлен P1-1 (`data-testid="field-company-kpp"` в CompanyFormPage.tsx)
- Dev предоставляет замер bundle delta (требование DoD §9)

P2-замечания фиксируются в журнале задач (project_tasks_log.md) как технический долг — рекомендую добавить в backlog FE-W1-2 или вынести отдельным быстрым батчем перед следующим экраном, чтобы не копировать дефектный паттерн (особенно P2-3 с uncontrolled Select).
