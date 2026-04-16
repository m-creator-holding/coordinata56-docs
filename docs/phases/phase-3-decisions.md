# Фаза 3 — Решения Владельца на открытые вопросы

**Дата**: 2026-04-15
**Источник**: Telegram msg #454, Мартин, «согласен продолжай работу»
**Статус**: утверждено

## Решения

### Q12 — Иммутабельность Payment
**Принято**: enum `PaymentStatus {draft, pending, approved, rejected}` + отдельный эндпоинт `POST /payments/{id}/approve`.
- Редактирование/удаление `Payment` с `status = approved` → 409 `IMMUTABLE_RESOURCE`.
- Переходы статусов: draft ⇄ pending → approved/rejected; approved — терминальный.
- Потребуется миграция Alembic: добавить поле `status` в `payments`.

### Q9 — Bulk-загрузка бюджета
**Принято**: upsert по композитному ключу `(project_id, category_id, stage_id, house_id)`.
- Повторная загрузка — перезапись существующих строк.
- ~~Аудит фиксирует diff before/after для каждой перезаписанной строки.~~ **Отменено, см. уточнение ниже.**
- Версионирование плана — вне MVP.

**Уточнение от Владельца (Мартин, 2026-04-15, Telegram msg #572):**
Аудит bulk-загрузки — **одна запись** `audit_service.log()` на всю операцию с summary-объектом в `meta`: `{"project_id": ..., "created": N, "updated": M, "total": N+M}`. Поэлементный diff before/after **не пишем** (избыточная нагрузка на audit_log, неинформативно для пользователя). `action = "bulk_upsert"`, `entity = "BudgetPlan"`, `entity_id = null`.

Это уточнение отменяет строку про «diff before/after для каждой перезаписанной строки» выше.

### Q6 — Смена стадии дома
**Принято**: разрешён любой переход вперёд (пропуск стадий допустим). Переход назад — запрещён (409 `BUSINESS_RULE_VIOLATION`).
- В `HouseStageHistory` пишется каждая смена с пометкой «прыжок» если пропущены стадии.
- Отдельный эндпоинт `PATCH /houses/{id}/stage` (не через generic update).

### Q1 — Bulk создания домов
**Принято**: оба эндпоинта.
- `POST /houses` — одиночное создание.
- `POST /houses/bulk` — массовое, лимит 200 строк за запрос (консистентно с ADR 0006).

## Действия по решениям

1. Миграция Alembic: `payments.status` (enum).
2. В `backend/app/models/enums.py` — добавить `PaymentStatus`.
3. ADR 0004 amendment: зафиксировать эндпоинты `/approve` и `/bulk` как паттерн «action endpoints» (не generic CRUD).
4. User Stories обновить: AC для Q12, Q9, Q6, Q1 → конкретика по решениям.
