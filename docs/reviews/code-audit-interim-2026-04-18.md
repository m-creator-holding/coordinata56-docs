# Интерим-отчёт: аудит кода (Фаза 3 + Волна 1 Foundation)

**Автор:** quality-director (интерим-срез, не финальное ревью)
**Дата:** 2026-04-18 (19:57 MSK)
**Формат:** экспресс-обзор безопасности и ADR-compliance, не штатное pre-commit review
**Связанные документы:**
- ADR 0004 (слои), 0005 (ошибки), 0006 (пагинация), 0007 (аудит), 0011 (Foundation)
- `CLAUDE.md` (живой антипаттерник)
- `docs/agents/departments/backend.md` v1.2 и `quality.md` v1.0
- Последние финалы: `pr1-wave1-multicompany-round-2-review.md`, `pr2-wave1-rbac-consent-round-1-review.md`

---

## 1. Что просканировано

### Модули бэкенда

| Слой | Файлов | Сканер прошёл |
|---|---|---|
| `backend/app/api/` | 24 роутера | Да (pagination, аудит, RBAC декораторы) |
| `backend/app/services/` | 20 сервисов | Да (литералы SQL, аудит, company-scope) |
| `backend/app/repositories/` | 19 репозиториев | Частично (get_by_id_scoped + list_paginated) |
| `backend/app/models/` | 16 моделей | Да (company_id NOT NULL, audit поля) |
| `backend/alembic/versions/` | 10 миграций | Лёгкий просмотр имён, глубоко — не лез |
| `backend/tests/` | 28 тест-файлов, 461 def test_ | Grep на литералы паролей и шаблон |

### PR/Волны

- **Фаза 3 (Батч A / B / C)** — завершена, финалы в `docs/reviews/phase3-*`.
- **Волна 1 Foundation**:
  - PR #1 — Multi-company (ADR 0011 §1) — round-2 APPROVE.
  - PR #1 addon — Zero-version OpenAPI stub — APPROVE WITH CHANGES (P1 был устранён).
  - PR #2 — RBAC v2 + PD Consent (ADR 0011 §2 + ФЗ-152) — round-1 APPROVE.
  - PR #3 — Crypto Audit Chain (ADR 0011 §3) — **только stub `/audit/verify` 501**, реальная имплементация не начата.

### Чек-листы, которые прогонял

- OWASP Top 10 2021 (A01 Broken Access Control, A02 Crypto Failures, A03 Injection, A04 Insecure Design, A07 AuthN, A08 Data Integrity, A09 Logging).
- ADR 0004 MUST #1a/#1b (запрет `select/session.execute` вне repos; разрешены ColumnElement предикаты).
- ADR 0005 envelope ошибок (`{error: {code, message, details}}`).
- ADR 0006 pagination envelope (`{items, total, offset, limit}`), лимит 200.
- ADR 0007 аудит в той же транзакции + маскировка секретов.
- `backend.md` правила (IDOR на parent_id, литералы паролей, action-endpoints).

---

## 2. Top-5 наблюдений (severity-ordered)

### P1-A: функция `can()` в `services/rbac.py:237-242` — fail-open при `resource.company_id IS NULL`

**Файл:** `backend/app/services/rbac.py`, строки 237-242.
**Симптом:** сигнатура `not (resource_company_id is not None and resource_company_id != user_context.company_id)`. Если у ресурса `company_id is None` — возврат `True` для любого пользователя. Вызов `can()` на таком объекте вернёт «разрешено».
**Почему сейчас не эксплуатируется:** все затронутые модели (`Project`, `Contract`, `Contractor`, `Payment`) имеют `company_id: Mapped[int]` без `Optional` и `NOT NULL`. То есть в рантайме нулей не бывает.
**Риск:** при появлении любого будущего ресурса с nullable `company_id` (например, справочник shared across companies) — мгновенная дыра cross-tenant без какого-либо нарушения паттерна кода. «Тихий» fail-open по конструкции.
**Рекомендация:** перевернуть условие на fail-closed.
```python
if resource_company_id is None:
    return False  # неизвестный scope — не разрешать
return resource_company_id == user_context.company_id
```
Плюс тест-негатив для ресурса с company_id=None. **Не блокирует коммит** — логическая дыра без текущего эксплойт-пути, но правило Fail-Closed нарушается.

---

### P1-B: `require_permission` не сверяет `resource.company_id` с `ctx.company_id` — scope-проверка делегирована сервису

**Файл:** `backend/app/api/deps.py:302-369`.
**Симптом:** декоратор `require_permission(action, resource_type)` проверяет только наличие у пользователя права `(resource_type, action, pod_id)` в его матрице. Проверка принадлежности конкретного объекта к компании пользователя выполняется отдельно — в `CompanyScopedService._scoped_query_conditions` через `extra_conditions`. Это работает **только** для ручек, которые действительно проходят через `BaseService.get_or_404(id, extra_conditions=...)` или `list_paginated(extra_conditions=...)`.
**Почему важно:** если разработчик новой ручки добавит `require_permission("read", "contract")` но забудет передать `user_context` в сервис (или напишет свой сервисный метод без `extra_conditions`) — RBAC-декоратор пропустит запрос, а company-scope фильтр не сработает. Cross-company IDOR возвращается.
**Статус сейчас:** все 4 проверенных сервиса (`project`, `contract`, `contractor`, `payment`) действительно используют паттерн — в round-2 PR#1 это явно закрыто (см. P0-1 «IDOR закрыт»).
**Риск на будущее:** защита держится на дисциплине разработчика. При добавлении новой сущности (особенно в новом pod) легко регрессировать. Нет CI-проверки «если роутер использует `require_permission` на пути `/{id}`, то сервис должен принимать `user_context`».
**Рекомендация:** добавить архитектурный тест `test_company_scope_enforced.py`, который:
1. Собирает все роутеры с path-param `{id}` и `require_permission`.
2. Через introspection проверяет, что соответствующий сервисный метод в сигнатуре имеет `user_context: UserContext`.

Не блокирует коммит — замечание уровня «inch-wide moat». Пометил в backlog quality.

---

### P2-A: дублирование `UserCompanyRoleRepository` (публичный + приватный `_UserCompanyRoleRepository`)

**Файл:** `backend/app/api/user_roles.py:37-73` vs `backend/app/repositories/user_company_role.py`.
**Симптом:** в роутере `user_roles.py` объявлен приватный класс `_UserCompanyRoleRepository(BaseRepository[UserCompanyRole])` с методом `list_by_user(offset, limit) -> tuple[list, int]`, параллельно существует публичный `UserCompanyRoleRepository` с методом `list_by_user(user_id) -> list` без пагинации. Причина: API нужна пагинация, `deps.py` — нет.
**Отмечено в round-1 PR#2** как плановый технический долг (`TODO-SERVICE`). Согласовано.
**Риск:** при изменении логики фильтрации (например, скрыть soft-deleted UCR) нужно править оба места — одно обязательно забудут. Классический shotgun surgery.
**Рекомендация:** объединить в публичный репозиторий с двумя методами: `list_by_user_all(user_id)` и `list_by_user_paginated(user_id, offset, limit)`. Отдельный батч чистки.

---

### P2-B: `import ColumnElement` внутри метода вместо уровня модуля

**Файл:** `backend/app/api/user_roles.py:65`.
**Симптом:** `from sqlalchemy import ColumnElement` внутри `list_by_user`.
**Последствие:** кеш Python модулей скрывает реальную нагрузку, но статический анализ (ruff, mypy) хуже понимает тип-переменные. Нестандартно для стайл-гайда проекта.
**Рекомендация:** поднять на уровень модуля при следующем касании файла (micro-commit). Не блокер.

---

### P2-C: хардкод `created_by_user_id=1` в тестовой фикстуре `test_company_scope.py:574`

**Симптом:** фикстура предполагает наличие seed-пользователя с id=1. При изменении порядка seed (который уже несколько раз менялся в foundation) фикстура падает с FK violation.
**Отмечено в round-2 PR#1** как P2-5, оставлено в backlog quality.
**Рекомендация:** заменить на `user_fixture.id` из актуальной фикстуры.

---

## URGENT секция (P0)

**Пусто.** Критических P0 (немедленный блокер поставки по безопасности) в просканированной части не найдено.

Ранее идентифицированные P0 (multicompany round-1: IDOR через `require_role` без scope; seeds.py литерал пароля; `select` в deps.py) — все подтверждены закрытыми в round-2 ревью. Рецидивов в новом коде не обнаружено. Крипто-цепочка аудита (ADR 0011 §3) пока stub — это **ожидаемое** состояние (PR #3 не начат), не P0.

---

## 3. Что осталось

### По объёму

| Область | Прогресс | Осталось |
|---|---|---|
| OWASP Top 10 статический обзор | 7/10 категорий | A05 Security Misconfig, A06 Vulnerable Components, A10 SSRF — не прошёл |
| ADR-compliance (0004/0005/0006/0007/0011) | спот-чеки | Полный проход по всем 24 роутерам не сделан |
| Модели миграций | имена прочитаны | round-trip downgrade проверить локально, CI-job `round-trip` доверяю |
| Покрытие тестами (факт %) | 461 тест насчитал | `pytest --cov` не гонял — метрика покрытия не сняли |
| RBAC матрица (4 роли × N write-эндпоинтов) | не просканировал | Табличную проверку через параметризованные тесты — нужно отдельно |
| Crypto audit chain (ADR 0011 §3) | только stub | Полный аудит при реализации PR #3 |
| Consent middleware (ФЗ-152) | spot-check | Интеграционный прогон по списку эндпоинтов-исключений |
| Frontend Волны 1 (companies UI) | **не смотрел** | Фронт-ревью отдельной задачей |

### Что не лез

- Секреты в `.env.example`, CI-конфиге, Docker-файлах.
- Infra-код (`docker-compose`, Helm, terraform — если есть).
- Frontend-код целиком (`fe-w1-1-companies-*` review есть, но independent pass не делал).
- Legal-артефакты (`docs/legal/`) на актуальность.

---

## 4. ETA финального отчёта

**Оценка:** 1–2 рабочих дня после закрытия текущих активных задач Координатора. Объём оставшейся работы:

| Шаг | Часы |
|---|---|
| Coverage-метрика (`pytest --cov=backend/app --cov-report=term-missing`) | 0.5 |
| RBAC-матрица табличной формой (4 роли × все write-ручки) | 2 |
| Роутер-за-роутером ADR 0005/0006/0007 compliance sweep | 2 |
| OWASP A05/A06/A10 | 1 |
| Legal/ФЗ-152 spot-check по consent middleware paths | 0.5 |
| Сводка + рекомендации | 0.5 |
| **Итого** | **~6.5 часов чистой работы** |

При параллельной работе с ревьюером (`review-head` → `reviewer-1/2`) можно сжать до 1 дня. Сроков жёстких нет (правило Владельца «без жёстких дедлайнов»); лимитирующий фактор — наличие Agent-слота для делегирования.

### План финала

1. Делегировать `qa-head` → `qa-1`: coverage-отчёт по `backend/app` с разбивкой по модулям.
2. Делегировать `review-head` → `reviewer-1`: full-sweep ADR-compliance по 24 роутерам (чек-лист из backend.md).
3. Quality-director агрегирует в `docs/reviews/code-audit-final-2026-04-XX.md`.
4. Обновить метрики в `docs/agents/departments/quality.md` (секция «Метрики отдела»).
5. Если найдутся паттерны системных дефектов — добавить в CLAUDE.md или в `quality.md` как правило.

---

## 5. Тренд качества (короткая сводка)

| Метрика | Батч A | Волна 1 Foundation | Тренд |
|---|---|---|---|
| P0 на батч / PR | 4 | 2 (multi-company) + 2 (PR #2 pre-commit) + 1 (stub) | Стабильно ~2 |
| P1 на батч / PR | 5 | 1 (PR #1 round-1) + 1 (PR #1 addon) + 3 (PR #2) | Снижение |
| % PR с APPROVE с первого прогона | 0% | ~50% (PR #2 round-0 → round-1 approve) | Рост |
| Литералы паролей в коде | 2 случая | 1 случай (PR #1 addon, устранено) | Остаётся рецидивирующим классом |
| SQL вне репозиториев | 1 случай (step 4 Батч A) | 1 случай (PR #2 round-0 в deps.py, устранено) | Остаётся рецидивирующим классом |
| Крипто-цепочка аудита | N/A | stub | PR #3 впереди |

**Системные дефекты, повторяющиеся через фазы:**
1. Литералы паролей в тестах (3-й раз; правило есть в `CLAUDE.md` и `backend.md`, но фикс не автоматизирован).
2. `select/execute` утекает в сервисный/deps-слой при первом проходе (2-й раз).

**Рекомендация системная:** автоматизировать оба через pre-commit hook и lint-правило в `ruff`:
- Запрет `import secrets; secrets.token_urlsafe` обязательно используется при слове `password` в тестах.
- Запрет импорта `sqlalchemy.select/insert/update/delete/func` в модулях `app/services/*` и `app/api/*`.

Это уберёт два самых частых рецидива — соответствующее предложение отдельной задачей qa-head + infra-director.

---

*Интерим-отчёт подготовлен quality-director. Финальный отчёт — по ETA выше. Прогресс фиксируется в task-log Координатора.*
