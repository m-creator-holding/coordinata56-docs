---
name: M-OS-1.1 Admin Foundation — Sync Contract
description: Единая таблица синхронизации работ между Design / Backend / Frontend на экранах M-OS-1.1 Admin. Источник правды для статусов, блокировок, ETA.
type: sync-contract
phase: M-OS-1.1 Admin Foundation
owner: Координатор
created: 2026-04-18
last_updated: 2026-04-18
---

# M-OS-1.1 Admin Foundation — Sync Contract

## Зачем этот документ

На экранах M-OS-1.1 Admin (7 разделов) сходятся **4 параллельных потока работы**: design (wireframes), backend (API + миграции), frontend (React + MSW-моки), quality (E2E + RBAC тесты). Без единой таблицы координации каждый поток работает «вслепую» — риски:

- Frontend закладывает моки, не соответствующие реальному API (fe-w1-1 Companies — осторожно протестировано, но future экраны рискуют)
- Wireframe не учитывает consent-модалку (легко пропустить PD-блокер)
- Admin API готов раньше UI — не показываем владельцу готовую функциональность
- UI готов раньше API — приходится мокировать весь flow, потом переделывать

Этот документ — **единая точка правды** для 7 admin-экранов.

## Таблица синхронизации

| № | Экран | Wireframe | Backend API | Frontend | RBAC permission | Статус | Owner | Блокеры |
|---|---|---|---|---|---|---|---|---|
| 1 | **Companies** | ✅ `wireframes-m-os-1-1-admin.md` §Companies (rev.2) | ✅ OpenAPI stub `/api/v1/companies` (PR#1 base + RBAC в PR#2) | ✅ FE-W1-1 Companies (`9406cc0`, `4628cc0`) | `company.read/write/admin` | **FE DONE / BE stub** | Координатор | — |
| 2 | **Users** | ✅ `wireframes-m-os-1-1-admin.md` §Users | 🟡 PR#2 RBAC v2 (Фаза 2 dev) — реальный CRUD | ⏸️ FE-W1-2 (ждёт FE-INFRA-1 close, MSW-моки по OpenAPI stub) | `user.read/write/admin` | **IN PROGRESS** | frontend-director + backend-director | FE-INFRA-1 lint cleanup |
| 3 | **Roles** | ⏸️ `wireframes-m-os-1-1-admin.md` (нужен review 2 с consent-модалкой) | 🟡 PR#2 RBAC v2 — `GET /roles`, `PATCH /roles/{id}/permissions` | ⏸️ FE-W1-3 | `role.read/admin` | **WIREFRAME PENDING** | designer + backend-head | design v2 + PR#2 approve |
| 4 | **Permissions** | ⏸️ wireframe fragmentarно (под matrix UI) | 🟡 PR#2 — `GET /permissions` read-only | ⏸️ FE-W1-4 (часть экрана Roles) | `permission.read` | **WIREFRAME PENDING** | designer | — |
| 5 | **Integration Registry** | ✅ `wireframes-m-os-1-1-admin.md` §Integrations | ⏸️ OpenAPI stub (integration endpoints, real CRUD в M-OS-1.2+) | ⏸️ FE-W1-5 | `company.admin` | **BACKLOG** | backend-director, позже | — |
| 6 | **Settings** (company_settings) | ✅ `wireframes-m-os-1-1-admin.md` §Settings | ⏸️ OpenAPI stub `/api/v1/companies/{id}/settings` | ⏸️ FE-W1-6 | `company.write` | **BACKLOG** | backend-director, позже | — |
| 7 | **Audit Log** | ✅ `wireframes-m-os-1-1-admin.md` §Audit | ⏸️ ADR 0011 §3 (в PR#3 Crypto Audit) | ⏸️ FE-W1-7 | `audit.read/admin` | **BACKLOG** | backend-director + architect | PR#3 |

## Cross-cutting требования

### PD Consent (ФЗ-152 C-1) — блокирует все экраны

- Backend: `require_consent` middleware из PR#2 блокирует любой admin-роут кроме `/auth/*`, `/health`
- Frontend: все страницы проверяют JWT-claim `consent_required` → показывают модалку «Принять политику конфиденциальности» → `POST /api/v1/auth/accept-consent` → обновить JWT
- Design: модалка consent — единый паттерн для всех экранов (spec в wireframes revision 3)
- Текст политики: v1.0 draft из `docs/legal/drafts/privacy-policy-draft.md`, плейсхолдеры заменяются при рендере

**Owner sync cross-cutting consent:** `PR#2 RBAC + PD consent = единая история` (backend-director брифом утверждено).

### Design System (для всех admin экранов)

- Компоненты из `frontend/src/components/ui/` (shadcn) — канон
- 4 стандарта FE-W1-1 retrospective в `docs/agents/departments/frontend.md` v1.1 обязательны для следующих 6 экранов
- Design System Initiative v1.0 в работе (design-director) — финальная версия к M-OS-1.1 close

## Правила использования этого документа

1. **Источник правды для статусов** — этот документ имеет приоритет над `project_tasks_log.md` для M-OS-1.1 Admin.
2. **Обновляется Координатором** при переходе статуса (стартовал/готов/заблокирован).
3. **Проверяется при каждом Agent-вызове к design/backend/frontend директору** по M-OS-1.1 задаче — включать фрагмент таблицы в prompt.
4. **Блокеры эскалируются Владельцу через Telegram** сразу как появляются (не ждать retrospective).
5. **Читается перед стартом каждого нового FE-W1-X, PR-x, wireframe revision** — обязательно.

## Блокеры (на 2026-04-18 16:30 UTC)

1. **FE-INFRA-1 lint cleanup** — блокирует FE-W1-2 Users. Запущен в работе frontend-director → frontend-head → frontend-dev.
2. **PR#2 RBAC v2 + PD consent** — блокирует реальный функционал Users/Roles/Permissions экранов. В работе Фаза 2 backend-dev.
3. **Wireframes Roles + consent-модалка revision 2** — ожидают design-director (в работе Design System Initiative).

## Ближайший критический путь

```
PR#2 RBAC v2 Фаза 2 (backend-dev)
  ↓ Фаза 3 (роутеры + E2E)
  ↓ reviewer round-0 → round-1 (при need)
  ↓ director final approve
  ↓ commit + push
  ↓ [РАЗБЛОКИРУЕТ] FE-W1-2 Users реальный
       ║ параллельно
       ║ FE-INFRA-1 (в работе сейчас) → разблокирует FE-W1-2 UI
       ║ wireframes Roles + consent (design-director)
```

ETA: 3-5 рабочих дней на критический путь (PR#2 + FE-W1-2 + design Roles).

## Связанные документы

- `docs/pods/cottage-platform/specs/wireframes-m-os-1-1-admin.md` — design wireframes (rev.2)
- `docs/pods/cottage-platform/tasks/pr2-wave1-rbac-v2-pd-consent.md` — бриф PR#2
- `docs/pods/cottage-platform/tasks/fe-infra-1-lint-cleanup.md` — бриф FE-INFRA-1 (в работе)
- `docs/agents/departments/frontend.md` v1.1 — 4 стандарта FE-W1-1 retrospective
- `docs/legal/m-os-1-1-foundation-legal-check.md` — legal check C-1 блокер
- `docs/adr/0011-foundation-multi-company-rbac-audit.md` — RBAC архитектура

---

*Создано Координатором 2026-04-18 по рекомендации process-monitor отчётов 2-6. Живой документ — обновляется при каждом изменении статуса.*
