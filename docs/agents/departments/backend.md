# Регламент работы отдела бэкенда

> Все агенты этого отдела имеют тип `core_department` по ADR 0010.

**Директор:** backend-director
**Версия:** 1.0
**Дата:** 2026-04-15
**Утверждено Координатором:** ✅ 2026-04-15 (bootstrap-редакция, уточняется backend-director по итогам Батча B)
**Источник первой редакции:** Координатор (бутстрап — новые роли ещё не подгружены в сессию). Будет уточнён backend-director на первой реальной задаче Батча B.

---

## Сферы ответственности отдела

- Серверный код на Python 3.12
- FastAPI: эндпоинты, middleware, exception handlers, dependency injection
- SQLAlchemy 2.0: модели, репозитории, сессии, транзакции
- Pydantic v2: схемы, валидация
- Alembic: миграции (простые — самостоятельно, сложные — через инженера БД)
- Бизнес-логика в сервисном слое
- REST API контракты (Swagger / OpenAPI)
- Юнит и интеграционные тесты бэкенда

## Правила работы (выросшие из ошибок)

Полный список общефирменных правил — в `/root/coordinata56/CLAUDE.md`. Здесь — уточнения и расширения для бэкенда:

1. **Слои строго по ADR 0004**: router → service → repository. Сервис не знает SQLAlchemy. Роутер не делает бизнес-логику. *(BUG: P0-1 step 4 round 1 — service делал прямой select.)*
2. **Фильтры коллекций — только в SQL WHERE через `extra_conditions`**, никогда в Python после LIMIT. *(BUG: P0-1 step 2 round 1 — total в пагинации врал.)*
3. **Вложенные ресурсы — обязательная проверка `child.parent_id == parent_id`**, при несовпадении 404 (не 403). *(BUG: P1-1 step 4 round 1 — IDOR в HouseConfiguration.)*
4. **Action-endpoints для нестандартных операций** (например, `POST /payments/{id}/approve`, `PATCH /houses/{id}/stage`) — отдельные ручки, не generic update. Понятнее, аудитируется проще.
5. **Аудит-лог в одной транзакции с записью** (ADR 0007). Каждая write-операция должна вызывать `audit_service.log()` явно, в сервисном слое. Проверка маскировки секретов через Pydantic Read-схемы.
6. **Soft-delete**: если у модели есть `SoftDeleteMixin` — DELETE выставляет `deleted_at`, GET list по умолчанию исключает удалённые. Повторный DELETE на soft-deleted → 404.
7. **Никаких литералов секретов** ни в коде, ни в тестах, ни в фикстурах. `secrets.token_urlsafe(N)` или `os.environ.get(...)`. *(Повторяющийся дефект: 3 раза за 2 фазы.)*
8. **Перед `git add` — пред-коммит чек-лист** (см. ниже).
9. **Отклонения от ADR — стоп работы и эскалация Начальнику**. Не молча.
10. **Bulk-операции — atomic**: всё или ничего. При ошибке в одном элементе откат всего батча. Лимит — 200 строк (Pydantic max_length).

## Стандарты качества

- **Покрытие тестами**: ≥85% строк, ≥80% веток (по pytest-cov)
- **Линтер**: `ruff check` чисто, 0 ошибок
- **Типизация**: type hints на всех публичных функциях, возвращаемых типах сервисов
- **Swagger покрытие**: 100% эндпоинтов имеют summary, description, response_model, минимум 1 пример в schema_extra
- **Время на типовую CRUD-сущность** (Sonnet-сотрудник, замороженный паттерн): ориентир 30-45 минут
- **Время на нетривиальную задачу** (новый паттерн, бизнес-логика): 1-2 часа
- **Pre-commit pass**: 100% перед сдачей Начальнику отдела

## Шаблон промпта для backend-dev (CRUD-сущность)

```
Реализуй CRUD для сущности <Name> по эталону Project (см. backend/app/services/project.py).

ОБЯЗАТЕЛЬНО прочти:
1. /root/coordinata56/CLAUDE.md
2. /root/coordinata56/docs/agents/departments/backend.md
3. /root/coordinata56/docs/adr/0004,0005,0006,0007
4. backend/app/services/project.py — паттерн

Реализуй:
- backend/app/schemas/<name>.py: <Name>Create, <Name>Update, <Name>Read
- backend/app/repositories/<name>.py: <Name>Repository(BaseRepository[<Name>])
- backend/app/services/<name>.py: <Name>Service
- backend/app/api/<name>s.py: 5 endpoints
- backend/tests/test_<name>s.py: ≥10 тестов (happy/403/404/422 + аудит + RBAC × 4 роли)
- Регистрация в backend/app/main.py

RBAC: <уточнить кто может что>
Бизнес-правила: <уточнить специфику>

FILES_ALLOWED: backend/app/schemas/<name>.py, backend/app/repositories/<name>.py, backend/app/services/<name>.py, backend/app/api/<name>s.py, backend/tests/test_<name>s.py, backend/app/main.py
FILES_FORBIDDEN: всё остальное

Самопроверка перед сдачей — по чек-листу.
git add только изменённые файлы. Не коммить.
Отчёт ≤200 слов: что сделал, тесты, ruff.
```

## Чек-лист самопроверки backend-dev (перед сдачей)

- [ ] Прочитан CLAUDE.md и этот регламент?
- [ ] Соответствие ADR 0004 (router → service → repository)?
- [ ] Все ли write-эндпоинты имеют `audit_service.log()`?
- [ ] Все ли write-эндпоинты имеют `require_role(...)` с правильными ролями?
- [ ] Фильтры — в SQL, не Python после LIMIT?
- [ ] Вложенные ресурсы — проверка parent_id?
- [ ] Никаких литералов секретов в коде / тестах?
- [ ] Pydantic Read-схемы не возвращают sensitive fields?
- [ ] Soft-delete семантика корректна (если применимо)?
- [ ] Все эндпоинты в Swagger имеют summary, description, response_model?
- [ ] `pytest backend/tests` зелёный?
- [ ] `ruff check backend/app` чисто?
- [ ] `git status` показывает только то, что я делал?

## Шаблон commit-message (для Координатора)

```
feat(api): <краткое описание> — <фаза/батч/шаг>

<1-3 параграфа: что сделано, почему так, ссылка на ревью>

<Если были раунды ревью: краткий итог замечаний>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

## Метрики отдела (отслеживаются Директором)

| Метрика | Цель | Текущее (Батч A) |
|---|---|---|
| Среднее время на CRUD-сущность | ≤45 мин | ~10 мин по эталону, ~5 мин на тиражируемых |
| % ревью прошедших с первого раза | ≥50% | 0/2 на эталоне (P0×2), 0/2 на тиражировании (P0×2). Критично улучшать. |
| Среднее число P0/P1 на ревью | ≤1 | 4 P0 + 5 P1 за Батч A. Критично. |
| % покрытия (бэкенд) | ≥85% | TBD |
| Trend размера CLAUDE.md | стабильный | растёт (5 → 13 правил за Батч A) |

**Главный риск Батча B**: повторение тех же ошибок (литералы паролей, фильтры в Python, IDOR во вложенных). Мера: чек-лист самопроверки сверху каждого промпта + явное упоминание этих правил.

## История версий

- v1.0 — 2026-04-15 — первая редакция (бутстрап от Координатора, на основе опыта Фазы 2 + Батча A Фазы 3)
