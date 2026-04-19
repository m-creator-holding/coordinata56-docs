# Head-бриф: FE-W1-1B Companies Extension (M-OS-1.1B)

- **Версия:** 1.0-draft
- **Дата:** 2026-04-19
- **От:** frontend-director (L2)
- **Кому:** frontend-head (L3)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-1B-companies-ext
- **Под-фаза:** M-OS-1.1B Config/Admin Foundation
- **Статус:** draft — финальный wireframe v0.4 от design-director ожидается
  (отдельный бриф `design-brief-fe-w1-1b-companies-extension-2026-04-19.md`)
  **Head начинает разбор только после утверждения wireframes v0.4.**
- **Предыдущий батч:** FE-W1-1 Companies (базовый CRUD, коммит
  `9406cc0`/`4628cc0`)

---

## 0. Что именно расширяем

Базовая страница `/admin/companies` (List / Details / Form) — есть.
Этот батч добавляет:
1. 7 полей Решения Владельца Q7 (payment_overrun_limit_pct,
   approval_amount_threshold, bank_primary_account, vat_regime,
   company_director_id, business_segment, default_currency)
2. Версионирование через `configuration_entities` (v1/v2/v3 …)
3. Правую панель «История версий» + откат
4. Readonly-mode для роли accountant (row-level isolation)

Переработки существующих CompaniesListPage / CompanyFormPage — минимальные
и точечные; новые файлы — для вкладок и правой панели.

---

## 1. FILES_ALLOWED

**Создать:**
```
frontend/src/pages/admin/companies/tabs/CompanyFinanceTab.tsx
frontend/src/pages/admin/companies/tabs/CompanyAuditTab.tsx
frontend/src/pages/admin/companies/components/CompanyVersionHistoryPanel.tsx
frontend/src/pages/admin/companies/components/ReadonlyAccountantBanner.tsx
frontend/src/pages/admin/companies/dialogs/RollbackVersionDialog.tsx
frontend/src/shared/validation/companyExtendedSchemas.ts
frontend/src/components/ui/radio-group.tsx           (через npx shadcn@latest add radio-group)
frontend/e2e/admin-companies-extension.spec.ts
```

**Расширить:**
```
frontend/src/pages/admin/companies/CompaniesListPage.tsx      — колонки Сегмент/НДС/Версия/Статус, фильтры
frontend/src/pages/admin/companies/CompanyDetailsPage.tsx     — добавить Tabs Основные/Финансы/Аудит + правая панель
frontend/src/pages/admin/companies/CompanyFormPage.tsx        — 7 новых полей + условная видимость
frontend/src/pages/admin/companies/tabs/CompanyDetailsTab.tsx — business_segment, company_director_id
frontend/src/shared/api/companies.ts                          — хуки useCompanyVersions, useRollbackCompanyVersion
frontend/src/shared/validation/companySchemas.ts              — добавить 7 новых полей в Zod (НЕ ломать обратную совместимость)
frontend/src/mocks/handlers/companies.ts                      — endpoints /versions, /rollback, поддержка 7 полей
frontend/src/mocks/fixtures/companies.ts                      — добавить 7 полей, версии для 5 юрлиц
```

**Удалить:** нет.

## 2. FILES_FORBIDDEN

```
frontend/src/pages/admin/users/**
frontend/src/pages/admin/roles/**
frontend/src/pages/admin/permissions/**
frontend/src/pages/admin/rules/**                  (будущий batch)
frontend/src/shared/api/users.ts
frontend/src/shared/api/roles.ts
frontend/src/shared/api/rolePermissions.ts
frontend/src/shared/api/permissions.ts
frontend/src/shared/auth/**
frontend/src/mocks/handlers/{users,roles,permissions,role_permissions,auth}.ts
backend/**
docs/adr/**
.github/workflows/**
```

Особенно важно: `CompaniesListPage.tsx` и `CompanyFormPage.tsx` —
**только расширение**, не переписывание. Head проверяет diff построчно.

---

## 3. Декомпозиция (ориентир для Head)

### Задача A — Zod, MSW, API-слой (фундамент)
- Расширить `companySchemas.ts`: добавить 7 новых полей как optional в
  базовой схеме + extended-схема со всеми 7 как required
- Расширить fixtures: 5 юрлиц Владельца (Координата 56 / АЗС / Карьер /
  Металл / МКД) с правильными сегментами и НДС-режимами; 2-3 версии на
  каждое (archived + active)
- MSW handlers:
  - `GET /api/v1/companies/:id/versions` → envelope ADR 0006, items из
    configuration_entities mock
  - `POST /api/v1/companies/:id/rollback` body `{version: N}` → создаёт
    новую версию с данными из указанной archived; 404 если версия не
    найдена; 403 если accountant
- Хуки: `useCompanyVersions(id)`, `useRollbackCompanyVersion()`
- Тесты handlers: +4 кейса (GET versions envelope, POST rollback happy,
  POST rollback 404, POST rollback 403 for accountant)

### Задача B — UI (после A)
- `CompanyFinanceTab.tsx` — RadioGroup vat_regime, Input bank_primary_account
  (маска 20 цифр), Input+суффикс payment_overrun_limit_pct (% 1–100),
  Input+₽ approval_amount_threshold, Select default_currency
- `CompanyDetailsPage.tsx` — Tabs Основные/Финансы/Аудит, сверху
  `ReadonlyAccountantBanner` (условный рендер)
- `CompanyVersionHistoryPanel.tsx` — Card + ScrollArea справа, список
  версий, активная с точкой, кнопки «Откатить» у archived
- `RollbackVersionDialog.tsx` — AlertDialog с датой/автором целевой версии,
  кнопки «Отмена» / «Да, откатить»
- `CompaniesListPage.tsx` — добавить колонки, Select-фильтр «Сегмент»
- E2E spec — сценарии AC-1..AC-4 из design-брифа

---

## 4. Acceptance Criteria (≥3 теста, AC из design-брифа)

AC-1 List View (accountant row-isolation), AC-2 Detail Save new version,
AC-3 Accountant readonly mode, AC-4 Rollback. Полные Given/When/Then
см. design-бриф §5. E2E spec `admin-companies-extension.spec.ts` должен
покрыть все 4 сценария.

## 5. Стандарты (frozen из FE-W1-1..FE-W1-4)

- Query Key Factory `companyKeys` — добавить новый sub-key `versions(id)`
- Envelope ADR 0006 на все list-responses
- Ошибки ADR 0005
- data-testid: `page-company-details`, `tab-details`, `tab-finance`,
  `tab-audit`, `panel-version-history`, `version-entry-{n}`,
  `btn-rollback-version-{n}`, `dialog-rollback-version`,
  `banner-readonly-accountant`, `field-payment-overrun-limit-pct`,
  `field-approval-amount-threshold`, `field-bank-primary-account`,
  `field-vat-regime`, `field-company-director-id`, `field-business-segment`,
  `field-default-currency`
- `<Can action="company.admin">` оборачивает кнопки Save / Rollback
- Readonly-mode: компоненты формы принимают prop `readOnly: boolean`,
  пробрасывают в Input/Select/Radio disabled + banner сверху; кнопки —
  через условный рендер (`readOnly && null`), не через disabled

---

## 6. Open Questions — будут уточнены после wireframes v0.4

OI-1. Layout правой панели на узких экранах — Sheet или всегда видимый?
OI-2. Вкладка Аудит — scope плоского списка vs полного log с фильтрами.
OI-3. Иконки для сегментов — рисуем или нет.

Head получает wireframes v0.4 от Координатора (после design-director) и
уточняет эти пункты в dev-брифе.

---

## История версий

- v1.0-draft — 2026-04-19 — frontend-director. Черновой head-бриф до
  получения wireframes v0.4. Финализация — после утверждения wireframes.
