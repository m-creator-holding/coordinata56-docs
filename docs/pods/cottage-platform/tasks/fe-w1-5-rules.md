# Head-бриф: FE-W1-5 Business Rules (Limits) с версионированием

- **Версия:** 1.0-draft
- **Дата:** 2026-04-19
- **От:** frontend-director (L2)
- **Кому:** frontend-head (L3)
- **Через:** Координатор (паттерн «Координатор-транспорт» v1.6)
- **Батч-ID:** FE-W1-5-rules
- **Под-фаза:** M-OS-1.1B Config/Admin Foundation
- **Статус:** draft — финальный wireframe v0.4 от design-director ожидается
  (бриф `design-brief-fe-w1-5-rules-2026-04-19.md`).
  **Head начинает разбор только после утверждения wireframes v0.4.**
- **Новая страница:** `/admin/rules` — не существует, строится с нуля

---

## 0. Что строим с нуля

Категория 3 Admin UI: страница управления per-company бизнес-правилами
(payment_overrun_limit_pct, approval_amount_threshold и future) с
обязательным версионированием `configuration_entities` (rule_v1/v2/v3)
и снапшотами `payment_rule_snapshots`.

Список → Detail/Edit → Rollback → Snapshot drawer (из detail платежа).

---

## 1. FILES_ALLOWED

**Создать:**
```
frontend/src/pages/admin/rules/index.ts
frontend/src/pages/admin/rules/RulesListPage.tsx
frontend/src/pages/admin/rules/RuleEditPage.tsx
frontend/src/pages/admin/rules/CreateRulePage.tsx
frontend/src/pages/admin/rules/components/RuleValueInput.tsx          (Input + Select единицы)
frontend/src/pages/admin/rules/components/RuleVersionHistoryPanel.tsx
frontend/src/pages/admin/rules/components/BpmImpactBlock.tsx          (Alert warning + список процессов)
frontend/src/pages/admin/rules/components/ReadonlyAccountantBanner.tsx (или reuse из companies-ext)
frontend/src/pages/admin/rules/dialogs/RollbackRuleDialog.tsx
frontend/src/pages/admin/rules/dialogs/CreateRuleDialog.tsx           (если вариант Dialog vs Page)
frontend/src/pages/admin/rules/drawers/RuleSnapshotDrawer.tsx
frontend/src/pages/admin/rules/lib/ruleCatalog.ts                     (справочник rule_key → title / unit / range)
frontend/src/shared/api/rules.ts
frontend/src/shared/api/ruleSnapshots.ts
frontend/src/shared/validation/ruleSchemas.ts
frontend/src/mocks/handlers/rules.ts
frontend/src/mocks/handlers/rule_snapshots.ts
frontend/src/mocks/fixtures/rules.ts
frontend/src/mocks/fixtures/rule_snapshots.ts
frontend/e2e/admin-rules.spec.ts
```

**Расширить:**
```
frontend/src/routes.tsx                              — /admin/rules, /admin/rules/:id, /admin/rules/new
frontend/src/mocks/handlers/index.ts                 — подключить rules + rule_snapshots
frontend/src/mocks/__tests__/handlers.test.ts        — +8 кейсов
```

**Удалить:** нет.

## 2. FILES_FORBIDDEN

```
frontend/src/pages/admin/companies/**
frontend/src/pages/admin/users/**
frontend/src/pages/admin/roles/**
frontend/src/pages/admin/permissions/**
frontend/src/shared/api/{companies,users,roles,permissions,rolePermissions}.ts
frontend/src/shared/auth/**
frontend/src/mocks/handlers/{companies,users,roles,permissions,role_permissions,auth}.ts
backend/**
docs/adr/**
```

---

## 3. Декомпозиция

### Задача A — API-слой + MSW
- `fixtures/rules.ts`: ≥10 записей (5 юрлиц × 2 ключа: payment_overrun_limit_pct,
  approval_amount_threshold); у каждой — 1-3 версии (archived + active)
- `fixtures/rule_snapshots.ts`: ≥15 записей snapshots по 5-7 разным
  платежам (ссылки rule_id + rule_version + payment_id)
- `ruleCatalog.ts`: статичный реестр rule_key →
  `{ title, unit: '%' | '₽' | 'дней', range: [min, max], description,
  bpm_processes: string[] }`
- MSW handlers:
  - `GET /api/v1/rules` envelope + фильтры `?company_id=`, `?rule_key=`
  - `GET /api/v1/rules/:id` → текущая активная версия
  - `GET /api/v1/rules/:id/versions` envelope всех версий
  - `GET /api/v1/rules/:id/active-approvals-count` → `{ count: N }`
    (для BPM-warning)
  - `POST /api/v1/rules` создание нового правила — 201 + Rule
  - `PATCH /api/v1/rules/:id` (body с value + commit_comment) →
    создаёт новую версию, 200 + новая Rule; 422 если comment пустой;
    403 если accountant
  - `POST /api/v1/rules/:id/rollback` body `{version: N}` → новая версия
    с данными из указанной archived; 403 если accountant
  - `GET /api/v1/rule-snapshots/:snap_id` → полный snapshot с rule_json
- Хуки: `useRules(filters)`, `useRule(id)`, `useRuleVersions(id)`,
  `useRuleActiveApprovalsCount(id)`, `useCreateRule()`, `useUpdateRule()`,
  `useRollbackRule()`, `useRuleSnapshot(snapId, {enabled})`
- Zod: `ruleUpdateSchema = { value: z.number(), commit_comment:
  z.string().min(1, 'Комментарий обязателен') }`
- Query Key Factory: `ruleKeys.all`, `.list(filters)`, `.detail(id)`,
  `.versions(id)`, `.activeApprovalsCount(id)`; `ruleSnapshotKeys.detail(id)`
- Тесты handlers: +8 кейсов (GET list filter, GET detail, GET versions
  envelope, PATCH happy, PATCH 422 no comment, PATCH 403 accountant,
  POST rollback happy, GET snapshot)

### Задача B — UI (после A)
- `RulesListPage.tsx` — таблица из wireframe §3.1, фильтры
- `RuleEditPage.tsx`:
  - `RuleValueInput` с unit из catalog
  - `BpmImpactBlock`: список из ruleCatalog.bpm_processes + Alert
    «Изменение применится к N текущим заявкам» (N из
    useRuleActiveApprovalsCount)
  - Textarea обязательного commit_comment
  - `RuleVersionHistoryPanel` справа
  - `ReadonlyAccountantBanner` + `readOnly` prop пробрасывает disabled
    и скрывает кнопки/поле комментария
- `RollbackRuleDialog` — AlertDialog с датой/автором/комментарием цели,
  кнопки «Отмена» / «Да, откатить»
- `RuleSnapshotDrawer` — Sheet справа (wireframe §3.2а) с полным
  `pre`-блоком JSON и Badge «Архивная/Актуальная»; открывается через
  route `/admin/rules/snapshots/:snap_id` или `?snapshot=:id`
- `CreateRulePage.tsx` или Dialog — выбор rule_key из catalog + юрлицо +
  начальное значение + описание (решение design-director DQ-4)
- E2E spec — сценарии AC-1..AC-4 из design-брифа

---

## 4. Acceptance Criteria (≥3 теста, AC из design-брифа)

AC-1 List filter by company, AC-2 Save with BPM warning + required
comment, AC-3 Accountant readonly, AC-4 Snapshot drawer from payment
detail. Полные Given/When/Then см. design-бриф §5.

## 5. Стандарты (frozen)

- Envelope ADR 0006 / Errors ADR 0005 — все endpoints
- Query Key Factory — оба `ruleKeys` и `ruleSnapshotKeys`
- 5 состояний UI на каждой странице (loading / empty / error / success /
  edit-mode или dialog-confirm)
- Readonly-pattern — как в FE-W1-1B: prop `readOnly` пробрасывается,
  banner + disabled inputs + скрытые кнопки
- data-testid матрица: `page-rules-list`, `rules-table`, `row-rule-{id}`,
  `filter-rule-type`, `filter-company`, `btn-rule-create`,
  `page-rule-edit`, `field-rule-value`, `field-rule-value-unit`,
  `field-rule-commit-comment`, `bpm-impact-block`,
  `warning-active-approvals`, `panel-rule-versions`,
  `version-entry-{n}`, `btn-rollback-version-{n}`,
  `dialog-rollback-rule`, `banner-readonly-accountant`,
  `sheet-rule-snapshot`, `snapshot-json-block`
- `<Can action="rule.admin">` оборачивает Save / Rollback / Create
- Compatibility с payment detail: badge rule_v1 (snap #N) в
  `PaymentDetailPage` должен быть `<Button asChild><Link>` с deep-link
  `/admin/rules/snapshots/:snap_id` — но сам payment detail не в этом
  batch'e, backend-head-бриф для PaymentDetailPage обновления — отдельно

---

## 6. Open Items — до финализации

OI-1. Snapshot — Sheet (drawer) или отдельная страница? Рекомендация:
  Sheet с deep-link через route `/admin/rules/snapshots/:id`.
OI-2. «+ Добавить правило» — Dialog или Page? Ждём решения design-director
  DQ-4.
OI-3. Цвет Badge per-company — sequential palette tailwind или семантика?
  Рекомендация: sequential (5 цветов) в sprint 1.1B, семантика — M-OS-2.
OI-4. Backend OQ-2/OQ-3 (см. §7 родительского отчёта Директора) — влияют
  на MSW-контракт snapshot endpoint и active-approvals-count.

---

## История версий

- v1.0-draft — 2026-04-19 — frontend-director. Черновой head-бриф на
  новую страницу `/admin/rules` с версионированием и снапшотами.
  Финализация — после wireframes v0.4 и ответов backend-director.
