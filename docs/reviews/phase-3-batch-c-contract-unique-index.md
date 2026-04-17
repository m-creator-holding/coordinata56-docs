# Ревью: партиальный UNIQUE INDEX договоров (Батч C, Шаг C.2 — фикс P2 race condition)

**Дата:** 2026-04-16  
**Reviewer:** reviewer (quality-direction, L4)  
**Вердикт:** `approve` с одним замечанием уровня nit (P3)  
**Регламент:** regulations_addendum_v1.3 §1 (reviewer до git commit)

---

## Summary

Staged-изменения закрывают race condition P2, зафиксированный в ревью Шага C.2: проверка `get_by_number()` в `ContractService.create` перед INSERT не атомарна, что позволяло двум одновременным запросам оба пройти проверку и вставить дублирующую пару `(contractor_id, number)`. Решение реализовано правильно: атомарная гарантия вынесена на уровень СУБД через партиальный UNIQUE INDEX. Все три файла соответствуют требованиям задания, критических и серьёзных замечаний нет.

Единственное отклонение — отсутствие поясняющего текста после `# noqa: E402` в миграции, что нарушает правило CLAUDE.md. Замечание классифицировано как P3 (nit), не блокирует коммит.

---

## Файлы и изменения

| Файл | Тип изменения | Scope |
|---|---|---|
| `backend/alembic/versions/2026_04_16_1450_contract_contractor_number_unique_partial.py` | новый | партиальный UNIQUE INDEX |
| `backend/app/repositories/contract.py` | правка docstring | `get_by_number` |
| `backend/tests/test_contracts.py` | добавление тестов | 2 новых теста в конце |

Unstaged-файлы (`backend/app/main.py`, `backend/app/{api,repositories,schemas,services}/payment*.py`, `backend/tests/test_payments.py`) в staged отсутствуют — параллельная работа по Шагу C.3 корректно изолирована.

---

## Критерии проверки и результаты

### 1. Scope (ровно 3 файла)

**Результат: PASS.**  
В staged ровно три заявленных файла. Посторонних файлов нет.

---

### 2. Миграция

| Критерий | Ожидание | Факт | Статус |
|---|---|---|---|
| revision — 12-символьный hex | `[0-9a-f]{12}` | `9be2c634d3d9` — 12 символов, hex | PASS |
| down_revision | `'e1f2a3b4c5d6'` | `'e1f2a3b4c5d6'` | PASS |
| `op.create_index` с `unique=True` | присутствует | строки 34–40 миграции | PASS |
| `postgresql_where=sa.text('deleted_at IS NULL')` | присутствует | строка 39 | PASS |
| downgrade симметричный | `op.drop_index` с `table_name` | строки 43–46 | PASS |
| PRODUCTION-NOTE про CONCURRENTLY | в docstring | строки 11–13 | PASS |
| Стиль по эталону `e1f2a3b4c5d6_contractor_inn_partial_unique.py` | структура, импорты, тип аннотации | соответствует | PASS |
| `# noqa: E402` с комментарием | требование CLAUDE.md | только `# noqa: E402`, без пояснения | FAIL (P3/nit) |

**Имя индекса** `uq_contracts_contractor_id_number_active` — соответствует конвенции именования проекта (`uq_` + таблица + поля + суффикс `_active`).

**Round-trip**: подтверждён отчётом db-engineer (upgrade → downgrade → upgrade = OK) — зафиксировано в docstring миграции строка 14.

---

### 3. Docstring contract.py

**Результат: PASS.**  
Изменён абзац про защиту на уровне БД (строки 31–37 файла). Остальные части файла (`__init__`, `has_payments`, импорты) не тронуты. Новый docstring корректно описывает двухуровневую защиту: UX-проверка через `get_by_number()` для понятного 409, и гарантия на уровне СУБД через UNIQUE INDEX для race condition.

---

### 4. Тесты test_contracts.py

#### Тест 1: `test_contract_duplicate_number_db_constraint` (строки 926–978)

| Критерий | Ожидание | Факт | Статус |
|---|---|---|---|
| `begin_nested()` / SAVEPOINT | использован корректно | строка 965 — `async with db_session.begin_nested()` | PASS |
| `pytest.raises(IntegrityError, match=...)` | имя индекса в match | `match="uq_contracts_contractor_id_number_active"` | PASS |
| Raw SQL параметризован через `text()` + bind-dict | без f-string с переменными | `text(_insert_sql)` + dict, f-string содержит только литеральные колонки и placeholders | PASS |
| Тест добавлен в конец файла | ничего выше не переписано | строка 926, раздел начинается после строки 920 | PASS |

**Дополнительная проверка порядка контекст-менеджеров**: `pytest.raises` — внешний, `begin_nested()` — внутренний, `flush()` — внутри `begin_nested`. IntegrityError поднимается из `flush()`, что позволяет SAVEPOINT откатиться, а `pytest.raises` поймать исключение до того, как оно разрушит основную сессию. Это корректный паттерн для PostgreSQL SAVEPOINT.

#### Тест 2: `test_contract_duplicate_number_allowed_after_soft_delete` (строки 981–1033)

| Критерий | Ожидание | Факт | Статус |
|---|---|---|---|
| INSERT → soft-delete через UPDATE → повторный INSERT | доказывает партиальность индекса | строки 1007–1033 | PASS |
| Raw SQL параметризован | `text()` + bind-dict | использован `text(...)` + `common_params` | PASS |
| `flush()` после каждого шага | сессия видит изменения до commit | строки 1017, 1023, 1033 | PASS |
| Тест добавлен в конец файла | ничего выше не переписано | строка 981 | PASS |

---

### 5. Правила CLAUDE.md

| Правило | Статус |
|---|---|
| Нет литеральных секретов/паролей | PASS — `secrets.token_urlsafe(16)` во всех фикстурах |
| `# noqa` без обоснования запрещены | FAIL (P3) — строка 25 миграции: `# noqa: E402` без пояснения |
| `# type: ignore` без обоснования запрещены | N/A — отсутствуют |
| Round-trip миграции подтверждён | PASS — docstring строка 14 |

---

### 6. OWASP Top 10 (релевантные пункты)

**A03 — Injection (SQL):**  
В обоих новых тестах Raw SQL передаётся через `text()` с bind-dict. F-string используется только для склейки литеральных имён колонок и Named placeholders (`:param`) — пользовательского ввода нет. Риска SQL-инъекции нет. PASS.

**A01 — Broken Access Control:**  
Миграция не изменяет API-слой. Новые тесты работают напрямую с DB-сессией, минуя RBAC. Это допустимо для constraint-тестов. PASS.

**A02 — Cryptographic Failures / A05 — Security Misconfiguration:**  
PII и секреты не вводятся. PASS.

**A04 — Insecure Design (race condition):**  
Задача этого коммита — именно закрытие race condition через атомарный DB-constraint. Решение корректно. PASS.

**Прочие пункты (A06–A10):** не применимы к данному набору изменений.

---

### 7. Прочее

**Отсутствие `print()` и debug-следов:** PASS — ни в миграции, ни в тестах.  
**Комментарии «что» вместо «почему»:** в тестах комментарии описывают намерение (`# Создаём Payment напрямую через ORM`, `# Физически запись есть, но deleted_at выставлен`) — это пограничный случай; в тестовом коде допустимо для читаемости. P3/nit не заводится — не нарушение CLAUDE.md буквально.

---

## Найденные замечания

### P3 (nit) — `# noqa: E402` без пояснения в миграции

**Файл:** `backend/alembic/versions/2026_04_16_1450_contract_contractor_number_unique_partial.py`  
**Строка:** 25  
**Код:** `from alembic import op  # noqa: E402`  
**Требование:** CLAUDE.md — «Никаких `# type: ignore` / `# noqa` без комментария-обоснования».  
**Эталон:** в `e1f2a3b4c5d6_contractor_inn_partial_unique.py` строка 20 написано `# noqa: E402 — alembic convention: op before sa in version files`.  
**Влияние:** нулевое на безопасность и функциональность. Только ухудшает читаемость для нового разработчика, который не знает, почему noqa.  
**Рекомендация:** при следующей правке файла добавить пояснение после `# noqa: E402`. Не блокирует коммит.

---

## Вердикт

**approve**

Все три staged-файла проверены. Scope корректен. Миграция синтаксически и структурно верна, закрывает race condition атомарно на уровне СУБД, round-trip подтверждён. Docstring обновлён точечно, без побочных правок. Оба новых теста покрывают ровно то, что требовалось: constraint-нарушение при одновременной вставке и корректную работу soft-delete семантики с партиальным индексом. SQL параметризован, секретов нет, debug-следов нет.

Единственное замечание P3/nit (`# noqa: E402` без комментария) не является блокером согласно классификации quality.md (P0–P1 блокируют, P2–P3 не блокируют). Исправить при первой же правке миграционного файла.

**Коммит санкционирован.**
