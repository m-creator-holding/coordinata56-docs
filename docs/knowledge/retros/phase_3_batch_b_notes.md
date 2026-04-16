# Ретро-заметки — Фаза 3, Батч B

**Дата закрытия:** 2026-04-15
**Длительность:** 1 рабочий день
**Координатор:** Claude Opus 4.6 (1M)
**Владелец:** Мартин

## Итог

Реализован полный CRUD для 2 сущностей финансового планирования:
- `BudgetCategory` — категории статей бюджета (CRUD + soft-delete)
- `BudgetPlan` — плановые строки бюджета (CRUD + soft-delete + bulk upsert)

Итого: **263 теста, 263 passed** (211 из Батча A + 52 новых). Alembic round-trip чистый. Swagger: все эндпоинты присутствуют (`/api/v1/budget/categories/*`, `/api/v1/budget/plans/*`, `/api/v1/budget/plans/bulk`).

## Что сработало

1. **Паттерн из Батча A заморожен и переиспользован без трений.** BudgetCategory и BudgetPlan реализованы строго по эталону: `BaseCRUDService`, `BaseRepository`, `extra_conditions`, аудит в транзакции. Никаких отклонений от паттерна.

2. **PG partial unique + ON CONFLICT — чистый upsert без race condition.** Вместо GET-then-INSERT (N транзакций) — один `INSERT ... ON CONFLICT (house_id, budget_category_id, plan_year) WHERE deleted_at IS NULL DO UPDATE`. Конкурентные вставки безопасны на уровне БД. Паттерн закреплён в коде bulk-роутера и достоин переиспользования в Батче C.

3. **xmax::text::bigint как детектор upserted/inserted.** PostgreSQL хранит `xmax=0` для новых строк и `xmax=<txid>` для обновлённых. Приём `RETURNING xmax::text::bigint > 0 AS was_updated` позволяет в одном запросе вернуть клиенту точный счётчик `created`/`updated` без дополнительного SELECT. Нетривиальный, но надёжный паттерн.

4. **RBAC-покрытие на каждом эндпоинте.** Все write-операции защищены `require_role(...)`, тесты на 403 присутствуют для каждого роутера.

5. **Аудит в той же транзакции.** Ни один write-эндпоинт не прошёл без `audit_service.log()`. Проверено через интеграционные тесты.

## Что не сработало

1. **Литеральный пароль в тестах — снова (3-й батч подряд).** Тесты Батча B содержат хардкод `change_me` в дефолтном TEST_DATABASE_URL вместо `change_me_please_to_strong_password`. Это третье подряд появление литерального пароля (Phase 2 Round 2, Batch A step 2 Round 1, теперь Batch B). CLAUDE.md содержит явное правило, backend-dev его игнорирует. Требует эскалации правила в departments/backend.md как обязательный пункт самопроверки перед сдачей.

2. **N+1 в bulk house_id валидации.** При bulk upsert (до 1000 строк) каждый `house_id` валидируется отдельным SELECT. На 1000 строк — 1000 запросов к БД. Принято как tech-debt, не блокирует MVP, но должно быть исправлено до production (один `SELECT id FROM houses WHERE id = ANY(:ids)`).

3. **Отсутствует тест idempotency для bulk.** Повторная отправка того же bulk-запроса должна возвращать те же `created=0, updated=N` без дублей — этот сценарий не покрыт тестом. ON CONFLICT гарантирует корректность на уровне БД, но поведение API явно не верифицировано.

4. **Тест include_deleted=403 покрывает только read_only роль.** Параметр `?include_deleted=true` защищён `require_role(OWNER, ACCOUNTANT, CONSTRUCTION_MANAGER)`, но тест проверяет только один случай отклонения (read_only). Полная матрица ×4 роли не сделана.

## Новые паттерны для переиспользования

| Паттерн | Где применено | Применять в |
|---|---|---|
| PG partial unique + ON CONFLICT upsert | `budget_plans` bulk роутер | Батч C (MaterialPurchase bulk) |
| `xmax::text::bigint > 0` для upserted/inserted | `budget_plans` bulk | Любой bulk upsert |
| `INSERT ... ON CONFLICT ... RETURNING *` | `budget_plans` миграция | Новые сущности с bulk |

## Повторяющиеся ошибки backend-dev

| Ошибка | Батч A | Батч B | Итого | Действие |
|---|---|---|---|---|
| Литеральный пароль в тестах | ✓ (P0-2) | ✓ | 3 раза в 3 батчах | Добавить в departments/backend.md как пункт обязательной самопроверки |
| Тест 403 неполная матрица ролей | — | ✓ | 1 раз | Наблюдать, при повторе — в backend.md |

## Метрики

| Метрика | Значение |
|---|---|
| Тестов в Батче B (новых) | 52 |
| Итого тестов проекта | 263 |
| Сущностей реализовано | 2 (BudgetCategory, BudgetPlan) |
| Эндпоинтов добавлено | 7 |
| Alembic round-trip | чистый |
| Swagger coverage | 100% эндпоинтов Батча B присутствуют |

## Открытый tech-debt

См. обновлённый `docs/phases/phase-3-tech-debt.md` — позиции P3-7 — P3-10.

## Следующий шаг

Батч C — финансы-факт: Contractor, Contract, Payment, MaterialPurchase. Включает иммутабельность Payment (статусы DRAFT→PENDING→APPROVED/REJECTED), bulk для MaterialPurchase, и проверку N+1 house_id валидации (tech-debt P3-7).
