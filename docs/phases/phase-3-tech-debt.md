# Технический долг Фазы 3

Позиции, зафиксированные по результатам ревью 2026-04-15 и отложенные до завершения MVP.

---

## P3-1 — `# type: ignore[attr-defined]` в `base.py` для `self.model.id`

**Файл**: `backend/app/repositories/base.py`, строка с `self.model.id.asc()`

**Проблема**: `Base` не гарантирует наличие поля `id`. `# type: ignore` скрывает типовую проблему.

**Решение**: добавить `id: Mapped[int]` в базовый класс `Base` (в `app/db/base.py`) или ввести протокол `HasId`. Требует согласования с `db-engineer` — изменение базового класса модели.

**Приоритет**: после завершения Батча A (остальные 7 сущностей).

---

## P3-2 — Явная фиксация Python 3.12+ в ADR 0002

**Файлы**: `pagination.py`, `repositories/base.py`, `services/base.py`

**Проблема**: используется синтаксис PEP 695 (`class Foo[T]`), доступный только с Python 3.12. В ADR 0002 минимальная версия Python не зафиксирована явно.

**Решение**: добавить в ADR 0002 раздел с явным указанием `python_requires = ">=3.12"` и соответствующей записью в `pyproject.toml`.

**Приоритет**: до деплоя в production (критично для CI-образа).

---

## P3-3 — `print()` в `seeds.py`

**Файл**: `backend/app/db/seeds.py`, строки с `print()`

**Проблема**: `print()` вместо `logger.info()`. При следующем коммите этого файла потребует исправления.

**Решение**: заменить все `print()` на `logger.info()` / `logger.warning()` в seeds.py.

**Приоритет**: при следующем касании seeds.py.

---

## P3-4 — Тест на повторное создание с тем же code после soft-delete

**Файл**: `backend/tests/test_projects.py`

**Проблема**: `get_by_code` фильтрует `deleted_at IS NULL`, поэтому создание проекта с тем же `code` после его soft-delete проходит успешно. Поведение не покрыто тестом и не задокументировано явно.

**Решение**: добавить тест `test_create_project_after_soft_delete_same_code` с явным assert на ожидаемое поведение (допустимо или запрещено — уточнить у Координатора).

**Приоритет**: до Фазы 5 (бизнес-логика уникальности кодов).

---

## P3-5 — StageRepository.has_references: silent except без логирования

**Файл**: `backend/app/repositories/stage.py`, строки 57–67

**Проблема**: `except Exception: pass` (с комментарием `# noqa: BLE001`) при проверке BudgetPlan
глотает любую ошибку — включая неожиданные, не связанные с отсутствием таблицы.
В тест-среде это корректно (таблица Батча B может не существовать).
В production silent-except скроет реальный дефект.

**Решение**: заменить голый `except Exception: pass` на `except Exception as e: logger.warning(...)`.
Либо использовать явную проверку существования таблицы через `inspect`.

**Приоритет**: до выхода в production (Фаза 9).

---

## P3-6 — Тесты запускаются только с явным TEST_DATABASE_URL

**Файл**: `backend/tests/` (все файлы)

**Проблема**: дефолтный TEST_DATABASE_URL использует пароль `change_me`,
который не совпадает с реальным паролем тест-БД (`change_me_please_to_strong_password`).
При запуске `pytest` без явного `TEST_DATABASE_URL` тесты падают с ошибкой аутентификации.

**Решение**: создать `backend/.env.test` с правильным TEST_DATABASE_URL
и настроить `conftest.py` для автоматической загрузки (через `python-dotenv` или `pytest-dotenv`).
Либо добавить в pyproject.toml `[tool.pytest.ini_options] env = [...]`.

**Приоритет**: до подключения CI (Фаза 9).

---

## P3-7 — N+1 запросов при валидации house_id в bulk (BudgetPlan)

**Файл**: `backend/app/api/budget_plans.py` (или service), bulk upsert endpoint

**Проблема**: при bulk upsert (до 1000 строк) каждый `house_id` проверяется
отдельным SELECT-запросом к таблице `houses`. На 1000 строк — 1000 запросов.
На MVP с малым объёмом данных некритично, но неприемлемо для production.

**Решение**: заменить поштучную валидацию на один запрос:
`SELECT id FROM houses WHERE id = ANY(:ids) AND deleted_at IS NULL`.
Затем сверить множество входящих id с результатом — разница даёт невалидные.

**Приоритет**: до выхода в production (Фаза 9), при объёме >100 строк в bulk.

---

## P3-8 — Отсутствует тест idempotency bulk upsert (BudgetPlan)

**Файл**: `backend/tests/test_budget_plans.py`

**Проблема**: повторная отправка идентичного bulk-запроса должна возвращать
`created=0, updated=N` без дублей. ON CONFLICT гарантирует корректность на уровне БД,
но поведение API через повторный HTTP-вызов явно не верифицировано тестом.

**Решение**: добавить тест `test_bulk_upsert_idempotency` — два идентичных POST,
второй вызов должен вернуть `created=0, updated=<кол-во строк первого>`.

**Приоритет**: до Фазы 5 (бизнес-логика финансов).

---

## P3-9 — Тест include_deleted=403 покрывает только роль read_only

**Файл**: `backend/tests/test_budget_categories.py`, `backend/tests/test_budget_plans.py`

**Проблема**: эндпоинты с `?include_deleted=true` защищены проверкой роли,
но тест проверяет только один случай отклонения (роль `read_only`).
Полная матрица ×4 роли не сделана. Роли `accountant` и `construction_manager`
не проверены на допуск к удалённым записям.

**Решение**: параметризовать тест по всем 4 ролям — owner и accountant
должны получать 200, read_only — 403.

**Приоритет**: до финального ревью Фазы 3 (перед закрытием).

---

## P3-10 — UP042 в enums.py (исправлено в замыкании Батча B)

**Файл**: `backend/app/models/enums.py`

**Статус**: ЗАКРЫТО — все 6 enum-классов переведены с `(str, enum.Enum)` на
`enum.StrEnum` в коммите замыкания Батча B (2026-04-15).

**Было**: `class UserRole(str, enum.Enum):`
**Стало**: `class UserRole(enum.StrEnum):`
