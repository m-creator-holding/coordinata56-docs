# Ретроспективное код-ревью Wave 11 — 2026-04-19

**Ревьюер:** `reviewer` (субагент Quality, L4)
**Дата:** 2026-04-19
**Вердикт:** `request-changes`
**Коммиты:** `9bca6c8`, `37d951a`, `57077b9`, `db22ead`, `723acd1`

---

## Итоговая оценка

Wave 11 содержит качественную UI-работу с хорошим покрытием accessibility. Архитектурно коммиты выровнены по ADR-0005/0006. Однако выявлены три проблемы: одна P1 (хардкод пароля), одна P1 (критическое рассинхронение схемы настроек), одна P2 (неверная единица в фикстуре), плюс несколько minor/nit замечаний. Регрессионная угроза для production отсутствует (все затронутые эндпоинты — MSW-стабы или zero-version 501), но перед переводом в live-режим эти проблемы обязаны быть устранены.

---

## P1 — Критические (блокируют переход к live-имплементации)

### P1-1: Хардкод пароля в MSW-обработчике
**Файл:** `frontend/src/mocks/handlers/auth.ts:19`
**Проблема:** Литерал `'password123'` сравнивается с полем `body.password` в условии авторизации MSW. Это нарушение CLAUDE.md §«Секреты и тесты» («Никогда не литералить пароли») и OWASP A02/A07. Хотя это MSW-мок, файл находится в src/ и коммитится в git. При случайном включении в prod-bundle (misconfigured vite build) или при проверке кода третьими лицами — это явный вектор атаки. Кроме того, формирует плохой паттерн для всей команды.

**Требование:** Заменить на `process.env.TEST_ADMIN_PASSWORD` или сгенерировать через `crypto.randomUUID()` со статичным тест-сидом. Альтернатива: убрать password-check из MSW совсем (мок не обязан проверять пароль, достаточно e-mail).

**Ссылка:** CLAUDE.md §«Секреты и тесты», Конституция ст. 79, CODE_OF_LAWS ст. 40.

---

### P1-2: Рассинхронизация контракта company_settings между backend и frontend
**Файлы:**
- `backend/app/schemas/company_settings.py` — 7 полей: `vat_mode`, `currency`, `timezone`, `work_week`, `units_system`, `logo_url`, `brand_color`
- `frontend/src/shared/api/companies.ts` (CompanySettings) — 7 полей: `payment_overrun_limit_pct`, `approval_amount_threshold`, `bank_primary_account`, `vat_regime`, `company_director_id`, `business_segment`, `default_currency`
- `frontend/src/pages/admin/companies/tabs/CompanySettingsTab.tsx` — использует frontend-тип

**Проблема:** Два совершенно разных набора полей под одним именем `company_settings`. Backend по-прежнему возвращает `vat_mode`/`currency`/`timezone`/`work_week`. Frontend ожидает `vat_regime`/`approval_amount_threshold` и т.д. Комментарий `TODO(cross-vertical-backend-sync)` зафиксирован в трёх местах, но не создан трекинговый тикет.

**Почему P1:** Когда backend-stub будет заменён реальной имплементацией (следующая волна), форма в production молча сломается: frontend получит поля, которых нет в его типах → TypeScript это не поймает (оба типа `CompanySettings` и `CompanySettingsRead` локально корректны). Это незаявленное архитектурное отклонение от M-OS-1 decisions.

**Требование:** До начала live-имплементации company_settings — согласовать единый контракт (какой набор полей победит: frontend v1.1 или backend v0). Оформить ADR amendment или явный task в backlog с блокером на merge живого backend.

---

## P2 — Значимые (не блокируют текущий спринт, но создают долг)

### P2-1: Неверная единица `unit: 'rub'` для HR и Process правил в фикстурах
**Файл:** `frontend/src/mocks/fixtures/rules.ts`, строки 363, 402 (правила `probation_period_days` и `invoice_approval_days`)

**Проблема:** Правила с категориями `hr` (испытательный срок, дни) и `process` (срок согласования счёта, дни) используют `unit: 'rub'`. Это семантическая ошибка — дни не являются рублями. `formatValue()` в `RulesListPage.tsx:34-38` рендерит таблицу с суффиксом `₽` для этих значений, что вводит пользователя в заблуждение.

**Требование:** Добавить тип `'days'` в `RuleUnit` или использовать подходящий тип. Обновить фикстуры.

---

### P2-2: `company_director_id` помечен обязательным (звёздочка), но schema допускает null
**Файл:** `frontend/src/pages/admin/companies/tabs/CompanySettingsTab.tsx:482`

**Проблема:** Поле `Подписант (директор)` имеет `*` (обязателен) в Label, однако в Zod-схеме: `company_director_id: z.number().nullable().optional()`. Это противоречие: форма говорит пользователю «поле обязательно», но позволит сохранить с пустым значением. Нарушение UX-консистентности, потенциально — скрытая бизнес-ошибка (платёж без подписанта).

**Требование:** Либо убрать `*` из Label, либо добавить `.min(1)` к схеме и обязательную проверку.

---

## Minor (рекомендации, не блокируют)

### M-1: `aria-selected` на `<TableRow>` без `role="row"` в контексте `role="grid"`
**Файл:** `frontend/src/pages/admin/rules/RulesListPage.tsx:247`

`aria-selected` корректен только на элементах с `role="option"`, `role="row"` (в grid/treegrid), `role="gridcell"` и т.п. Стандартный `<tr>` имеет implicit role `row`, но только внутри `role="grid"` или `role="treegrid"`. Текущая таблица использует стандартный `<table>` без `role="grid"`, поэтому скринридер может проигнорировать `aria-selected`. Рекомендуется добавить `role="grid"` на `<Table>` или использовать `data-state="selected"` (shadcn-паттерн).

### M-2: Двойная ошибка в FieldError + sr-only дублирует сообщение
**Файл:** `frontend/src/pages/admin/companies/tabs/CompanySettingsTab.tsx`, блок `payment_overrun_limit_pct` (строки 287–292)

Ошибка отображается дважды: визуально через `<FieldError>` и через `<span id="err-overrun" className="sr-only">`. Скринридер объявит текст ошибки дважды (один раз через `aria-describedby`, второй — через `<FieldError role="alert">`). Рекомендуется объединить: `FieldError` сам получает `id` и ссылается через `aria-describedby`.

### M-3: `treeitem` без `aria-level` в RulesTree
**Файл:** `frontend/src/pages/admin/rules/RulesTree.tsx:119`

`role="treeitem"` на div без `aria-level` — скринридер не знает глубину элемента. По WAI-ARIA 1.2: `aria-level` обязателен для вложенных `treeitem`. Добавить `aria-level={1}` на group-кнопки и `aria-level={2}` на leaf-кнопки правил.

### M-4: `UserAdminUpdate` не содержит `contact_email`
**Файл:** `backend/app/schemas/user_admin.py`

Коммит `57077b9` называется `feat(users-v1.1): inline Select роли + contact_email`, однако в backend-схеме `UserAdminUpdate` поле `contact_email` отсутствует. Фронтенд в тесте `users-v1.1.test.tsx:252` тестирует только mock-инпут, не реальное API. Когда будет live-имплементация — поле будет молча игнорироваться бекендом.

---

## Nit

### N-1: `companyFilter` в `RulesListPage.tsx` — ID хранится как строка, не как число
**Файл:** `frontend/src/pages/admin/rules/RulesListPage.tsx:65`

`companyFilter` — строка из searchParams, но `company_id` в `rulesFilters` передаётся как строка (а не `number`). Если backend ожидает `int` — сломается при переходе на live API. TypeScript не поймает — `useRules` принимает `company_id: string | number | undefined`.

### N-2: Тест AC-R3 «комментарий из пробелов» содержит неверное утверждение
**Файл:** `frontend/src/pages/admin/rules/__tests__/RuleFormValidation.test.tsx:32-38`

Тест называется «отклоняет комментарий из одних пробелов», но проверяет `comment: ''` (пустая строка), а не `comment: '   '`. Это ложный тест — он не проверяет заявленное поведение. Согласно комментарию внутри теста — разработчик сам это признаёт, но оставил.

### N-3: Множественные `version` в теле ответа `company_settings` — только в MSW, не в backend
**Файл:** `frontend/src/shared/api/companies.ts:84`

Тип `CompanySettings` содержит поле `version: number`. В `CompanySettingsRead` (backend) это поле отсутствует. `toast.success(...)` в `CompanySettingsTab.tsx:209` читает `result.version.toString()`. При переходе на live API — `result.version` будет `undefined`, toast покажет `v undefined`.

---

## ADR compliance

| ADR | Статус | Замечание |
|-----|--------|-----------|
| ADR-0005 (error format) | Соответствует | `main.py` корректно регистрирует все 4 exception handlers |
| ADR-0006 (pagination) | Соответствует | `PaginatedUserResponse` правильно реализует envelope `{items, total, offset, limit}` |
| ADR-0007 (audit same-tx) | N/A для Wave 11 | Все backend-эндпоинты — заглушки 501, аудит не применяется |
| CLAUDE.md Git | Частично | Коммит `57077b9` описывает `contact_email`, которого нет в backend-схеме — несоответствие commit message и реального изменения |

---

## OWASP Top 10

| Пункт | Статус |
|-------|--------|
| A01 Broken Access Control | Backend-стабы не имеют `require_role`. Допустимо только как zero-version stubs (501) — до live-имплементации MUST добавить `Depends(require_role(...))` |
| A02 Crypto Failures | P1-1 выше |
| A03 Injection | Нет SQL/f-string в Wave 11 backend |
| A05 Security Misconfiguration | Swagger/docs открыты в dev (`docs_url="/docs"`) — acceptable для skeleton, закрыть перед production gate |
| A09 Logging | Аудит не применим к стабам — OK |

---

## Требования к устранению

1. **P1-1** — Убрать хардкод `password123` из `frontend/src/mocks/handlers/auth.ts` до следующего спринта.
2. **P1-2** — Завести явный backlog-тикет «Синхронизация контракта company_settings backend↔frontend» с блокером на live-имплементацию.
3. **P2-1** — Исправить `unit` в фикстурах HR/Process правил.
4. **P2-2** — Устранить противоречие обязательности `company_director_id`.
5. **M-4** — Добавить `contact_email` в `UserAdminUpdate` до live-имплементации users API.
