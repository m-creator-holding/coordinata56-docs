# Ретро-заметки — Фаза 3, Батч C

**Дата закрытия:** 2026-04-16
**Длительность:** ~2 рабочих дня (2026-04-15 … 2026-04-16)
**Координатор:** Claude Opus 4.6 (1M)
**Директор по бэкенду:** backend-director
**Владелец:** Мартин

## Итог

Реализован полный CRUD для 4 сущностей финансов-факт:

- `Contractor` — подрядчики (SoftDelete, partial-unique ИНН)
- `Contract` — договоры (SoftDelete, жёсткие переходы статусов, partial-unique `(contractor_id, number)`)
- `Payment` — платежи (hard-delete, иммутабельность после approve/reject, action-endpoints, лимит перерасхода 120%)
- `MaterialPurchase` — закупки материалов (hard-delete, auto-compute total_price)

Итого по проекту: **351 тест, 351 passed** (263 из Батчей A+B + 88 новых в Батче C). `ruff check` чисто по коду Батча C (3 pre-existing ошибки в `seeds.py` — Фаза 1, не трогали, внесены в tech-debt). Swagger: 22 новых эндпоинта (5+5+5+7), 4 тэга, у всех summary/description/responses, где применимо — response_model.

Коммиты:
- `e08b9b8` — Шаг C.1 (Contractor) + Шаг C.4 (MaterialPurchase), параллельно
- `3e279ea` — Шаг C.2 (Contract)
- `bb1310f` — Partial UNIQUE INDEX `(contractor_id, number)` (docstring-долг C.2, P2)
- `6cd337e` — Шаг C.3 (Payment + approve/reject)

## Что сработало

1. **Декомпозиция под Директором.** backend-director впервые сам написал полную декомпозицию Батча (spec §1–§6, 529 строк), с графом зависимостей, параллелизмом C.1∥C.4, детальными RBAC/бизнес-правилами, рисками и митигациями. Это сэкономило Координатору ~2 часа анализа и позволило запустить шаги сразу.
2. **Параллелизм C.1 и C.4 — без конфликтов.** Риск R5 из decomposition (merge-конфликт по `main.py`) не сработал — оба worker-а ограничились одной строкой `include_router`, строки не пересеклись. Экономия ~30% времени на этапе.
3. **Эталон переиспользуется между шагами.** C.2 Contract брал C.1 Contractor как эталон, C.3 Payment — брал C.2 Contract. К C.3 паттерн `_make_service` + `extra_conditions` + audit-в-транзакции применялся без напоминаний.
4. **Action-endpoints `/approve` и `/reject`** реализованы строго по ADR 0004 Amendment. `PaymentUpdate.status` объявлен как `Literal["draft","pending"]` — смена статуса через PATCH заблокирована на уровне типа схемы. Иммутабельность после approve — тест на 5 полей × 2 статуса.
5. **Partial UNIQUE INDEX с учётом soft-delete.** Для Contractor и Contract использован паттерн `CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`. Race condition на дубликат (ИНН/номер) закрыт на уровне БД, мягко удалённая сущность не блокирует создание новой с тем же ключом.
6. **Ретроспективный docstring-долг закрыт отдельным коммитом.** После ревью C.2 поднялся P2 (docstring ссылался на несуществующий UNIQUE INDEX). Вместо переделки C.2 задача закрыта отдельной миграцией `bb1310f` — чистая история коммитов, без переписывания approved-кода.

## Что не сработало

1. **Dropped requirements в брифах Координатора (два случая).**
   - Шаг C.3 Round 1: audit meta приехала как `{"old_status", "new_status"}` вместо заданного спецификацией `{"transition", "from_status"}`. Backend-dev и review пропустили, потому что в промпте Координатора формат meta был указан, но **тест тоже проверял неверный формат** — расхождение всплыло только на финальном ревью reviewer-а (P2-2 major).
   - Шаг C.3 Round 1: три reject-сценария (pending→reject happy, approved→reject 409, rejected→reject 409) не были покрыты тестами, хотя DoD §C.3 прямо писал «Reject: аналогично approve» — бриф не раскрыл, что «аналогично» = параметрически весь набор, и backend-dev интерпретировал минимально (P3-1 major).
   - **Мера:** в `departments/backend.md` добавить правило: audit meta формат — каноническая структура `{"transition","from_status"[,"reason"]}`, явно в чек-листе самопроверки; action-endpoints (approve/reject/…) — обязательная параметризация тестов по полной матрице статусов.

2. **Test DB migration drift.** Перед прогоном C.5 Координатор получил бы `test_contract_duplicate_number_db_constraint` FAILED, если бы не применил `alembic upgrade head` на test-БД явно. Миграция `bb1310f` создала `uq_contracts_contractor_id_number_active` — без upgrade тест ожидал бы 409 там, где БД ещё не имела ограничения.
   - **Мера:** в `conftest.py` автоматизировать `alembic upgrade head` перед сессией pytest (P3-6 уже в tech-debt, но теперь критично до CI). Либо зафиксировать «перед pytest обязательно `alembic upgrade head`» в `departments/backend.md` как обязательный пункт pre-run.

3. **Три раунда ревью на Шаге C.3.** Ожидалось 1–2. Причина — два независимых дефекта: формат meta и неполный reject-матрица. Не критично (не P0), но трендует в сторону роста круга «меньше замечаний — больше раундов». Корень: бриф Координатора был точный, но проверка его исполнения backend-head прошла по формальному чек-листу, не сверяя попадание в конкретные строки спецификации.
   - **Мера:** в `head.md` (регламент Начальника отдела) — при приёме работы backend-head делает явный cross-check «строка DoD → тест-доказательство». Это возможно усложнит роль Head, но закроет класс дефектов «DoD сказал X, код делает ~X».

4. **Ruff не был зелёным на старте Батча C.** 3 ошибки в `seeds.py` (I001, B007, UP017) существовали с Фазы 1 и в Батче A не ловили, потому что ruff запускали только на `backend/app` (без `tests/`) — а `seeds.py` хотя и в `app/`, но не в hot-path CRUD. При Шаге C.5 я впервые запустил `ruff check app/ tests/` — вывалились. Не влияет на Батч C, но сигнал: ruff в проекте не строгий.
   - **Мера:** в DevOps-скоупе Фазы 4 — `ruff check` на всё `backend/` как pre-commit hook. До CI — зафиксировать P3-1-NEW в `phase-3-tech-debt.md`.

## Новые паттерны для переиспользования

| Паттерн | Где применено | Применять в |
|---|---|---|
| Partial UNIQUE `WHERE deleted_at IS NULL` | `contractors.inn`, `contracts.(contractor_id, number)` | Любая soft-delete сущность с уникальным бизнес-ключом |
| `Literal["status1","status2"]` в *Update-схеме для блокировки write-перехода | `PaymentUpdate.status` | Любая сущность с action-endpoints (approve/reject/cancel) |
| `_check_*_*` helpers в сервисе с чистым разделением NotFoundError vs DomainValidationError | `services/contract.py::_check_house_project_match` | Любая FK-валидация с IDOR-защитой |
| Numeric threshold в Settings + динамическое сообщение ошибки | `PAYMENT_OVERRUN_LIMIT_PCT` + `f"лимит {100+limit_pct}%"` | Любой бизнес-лимит, который Владелец может захотеть поменять без деплоя |
| Audit meta каноническая структура `{transition, from_status[, reason]}` | `services/payment.py` approve/reject | Все action-endpoints со сменой статуса |
| `xmax::text::bigint > 0` как маркер upserted (из Батча B) | `budget_plans` bulk | Переносим в Фазу 4 для MaterialPurchase bulk |

## Повторяющиеся ошибки backend-dev

| Ошибка | Батч A | Батч B | Батч C | Итого | Действие |
|---|---|---|---|---|---|
| Литеральный пароль в тестах | ✓ (P0-2) | ✓ | — | 3 из 3 до Батча C | Правило в `departments/backend.md` §7 сработало: в Батче C ни одного литерального пароля, все через `secrets.token_urlsafe(16)`. **Закрыто.** |
| IDOR во вложенных ресурсах | ✓ (P1-1) | — | — (тест добавлен Round 2) | 1 раз + 1 регрессионно-тестовый пропуск | Правило в CLAUDE.md работает; в Батче C тест HOUSE_PROJECT_MISMATCH пропустили **в первом раунде** (P1-2), добавили во втором. Мера: чек-лист «тест на IDOR обязателен для каждого FK в create/update» — в `departments/backend.md`. |
| Docstring vs фактический HTTP-код | — | — | ✓ (P1-3 в C.1+C.4, P2-1 в C.2) | 2 раза в Батче C | Мера: в `departments/backend.md` — «docstring `Raises:` сверяется с фактическим типом исключения (ConflictError→409, DomainValidationError→422, NotFoundError→404)». |
| `assert` в Pydantic-валидаторе (сломается при `python -O`) | — | — | ✓ (P1-1 в C.1) | 1 раз | Правило: «в валидаторах — `raise ValueError`, не `assert`». Добавить в CLAUDE.md одной строкой. |
| Dropped requirements в брифе Координатора → тест проверяет неверный формат | — | — | ✓ (P2-2 и P3-1 в C.3) | 2 раза в одном шаге | См. §«Что не сработало» п.1 — мера в `departments/backend.md`. |

## Уроки для regulations v1.x (кандидаты в `departments/backend.md`)

1. **Numeric thresholds → Settings.** Любая бизнес-константа, которую Владелец может захотеть откорректировать без редеплоя (`PAYMENT_OVERRUN_LIMIT_PCT`, лимиты пагинации, пороги эскалации), живёт в `app/core/config.py` через Pydantic Settings, не в коде. Сообщение об ошибке — динамическое, использует актуальное значение Settings.

2. **Audit meta — каноническая структура.** Для action-endpoints (смена статуса): `{"transition": "<new_status>", "from_status": "<old_status>"[, "reason": "..."[, ...]]}`. Никаких `old_status`/`new_status`/`before`/`after`. Тест на audit — проверяет ровно эту структуру по ключам.

3. **`Literal[...]` в Update-схеме для блокировки запрещённых переходов.** Если поле статуса не должно меняться через PATCH (только через action-endpoint) — декларировать `Literal["allowed1","allowed2"]`. Pydantic блокирует на уровне валидации схемы, до сервиса.

4. **Partial UNIQUE для soft-delete сущностей.** Не `unique=True` на колонке, а миграция с `CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`. `unique=True` в SQLAlchemy-модели — убрать, чтобы не было расхождения между декларацией и фактом.

5. **Docstring `Raises:` — обязательная сверка с HTTP-кодом.** `ConflictError`→409, `DomainValidationError`→422, `NotFoundError`→404, `PermissionError`→403. При ревью — cross-check docstring vs фактический raise.

6. **Action-endpoint — параметризованное покрытие матрицы статусов.** Для approve/reject/cancel/close: тест покрывает каждую пару (allowed_from_status → target_status = 2xx) и (disallowed_from_status → target_status = 409). Plus тест audit-записи на каждый allowed-переход.

**Статус утверждения:** кандидаты 1–6 — backend-director готовит amendment к `departments/backend.md` v1.1, согласует с backend-head, передаёт Координатору на утверждение.

## Метрики

| Метрика | Значение |
|---|---|
| Тестов в Батче C (новых) | 88 (27 Payment + 26 Contract + остальные C.1/C.4) |
| Итого тестов проекта | 351 |
| Сущностей реализовано | 4 (Contractor, Contract, Payment, MaterialPurchase) |
| Эндпоинтов добавлено | 22 (5+5+5+7) |
| Раундов ревью | 2 (C.1+C.4) + 2 (C.2) + 1 (bb1310f) + 3 (C.3) = 8 |
| Новых миграций | 3 (`contractor_inn_partial_unique`, `payment_approve_reject_audit`, `contract_contractor_number_unique_partial`) |
| Alembic round-trip | чистый |
| Swagger coverage | 22/22 (100%) summary + description; 18/22 с response_model (4 DELETE — 204 No Content) |
| ruff check backend/app Батча C | чисто |
| ruff check backend/app/db/seeds.py | 3 pre-existing (не Батч C) |
| Коммитов в main | 4 |

## Открытый tech-debt (добавить в phase-3-tech-debt.md)

- **P3-NEW-1**: `ruff check` в проекте неполный — `seeds.py` содержит 3 ошибки (I001, B007, UP017), поймано на Шаге C.5. Приоритет: до DevOps-скоупа Фазы 4.
- **P3-NEW-2**: `conftest.py` не запускает `alembic upgrade head` автоматически — test DB migration drift может ронять тесты при добавлении миграций между сессиями. Приоритет: до CI (усиление P3-6).
- **P3-NEW-3**: `Payment.amount_cents` нет верхнего лимита. На MVP не критично, но при production-нагрузке overflow возможен. Приоритет: до Фазы 5.

## Следующий шаг

После reviewer-approve на consolidated Batch C и согласования Владельца — закрытие Фазы 3. Переход к Фазе 4 (фронтенд MVP) — согласно ROADMAP.

Параллельно: фаза M-OS-0 Reframing — обсуждается Координатором и Владельцем как реструктуризация проекта (coordinata56 → cottage-platform domain pod внутри M-OS).

---

*Автор: backend-director | coordinata56 | Phase 3 Batch C retro | 2026-04-16*
