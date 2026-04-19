# Бриф для ri-analyst — skill `rbac-permission-wiring-checker`

**Автор брифа:** ri-director
**Дата:** 2026-04-19
**Бюджет Analyst:** до 4 часов (регламент R&I §«Бюджет внимания»)
**Финальный артефакт:** `~/.claude/skills/rbac-permission-wiring-checker/SKILL.md` + эталонный прогон на живом API-роутере (`backend/app/api/companies.py` или US-03 эндпоинте).

---

## Почему этот скил сейчас

Sprint 1 M-OS-1.1A: US-03 (backend-dev-3) ставит RBAC-матрицу 7 actions × 22 resources + seed. ADR-0011 требует: каждый write-эндпоинт защищён через `require_permission(resource, action)`, не через `require_role`. «Голый» `require_role('admin')` или проверка в теле функции — нарушение модели RBAC (privilege escalation риск при появлении ролей типа «site-manager»).

Сейчас Claude Code при генерации нового эндпоинта (B-1 scaffold) не подсвечивает этот контракт — он указан только в регламенте `departments/backend.md` текстом. Итог: reviewer ловит нарушения постфактум. По RFC-007 это причина 2-го порядка для PR#2 Волны 1 (consent, rbac). Скил закрывает gap: Claude Code перед сохранением эндпоинта проверяет, что dependency-injection на permission подключён.

Прямой эффект на Sprint 1: US-03 + B-1 scaffold-crud не создают PR с «забыл `require_permission`» — экономия 1-2 раундов reviewer на Волне 2.

## Что скил должен делать (scope)

1. **Триггер.** User-invocable=false, auto-invoke при редактировании файлов в `backend/app/api/**/*.py`.
2. **Вход.** Путь к файлу-роутеру + список изменённых строк (`git diff HEAD -- <file>`).
3. **Шаги (в SKILL.md).**
   - Шаг 1: распарсить файл AST, найти все декораторы `@router.<method>(...)` кроме `@router.get` без query-params (read-only публичные — отдельная ветка).
   - Шаг 2: для каждого write-эндпоинта (`post`, `put`, `patch`, `delete`) проверить что в сигнатуре функции есть `Depends(require_permission(...))` или `Depends(require_permission_factory(...))`. Если вместо — `Depends(require_role(...))`, `Depends(get_current_user)` без permission, или ничего — FAIL P0.
   - Шаг 3: проверить что `require_permission` аргументы соответствуют паре `(resource_type, action)` из каталога ADR-0011 §2.1. Resource_type должен совпадать с именем модели (`Company`, `House`, `Consent`, ...), action из {create, read, update, delete, approve, reject, list}. Несовпадение — WARN P2.
   - Шаг 4: проверить наличие `UserContext` в сигнатуре (dependency `get_user_context` из `services/company_scoped.py`) — если эндпоинт мутирует данные, но user_context не получен, audit_service.log не сможет записать — FAIL P1.
   - Шаг 5: проверить что эндпоинт вызывает `audit_service.log(...)` в той же транзакции (ADR-0007). Если отсутствует — WARN P1.
   - Шаг 6: вывод PASS / WARN / FAIL со списком замечаний и цитатами ADR-0011 / ADR-0007.
4. **Выход.** Markdown-отчёт с таблицей «endpoint → permission_wired → audit_wired → user_context».

## Что скил НЕ делает

- Не валидирует seed матрицы RBAC (это отдельная задача US-03 backend-dev-3).
- Не проверяет frontend permissions-matrix UI (FE-W1-4 — другой домен).
- Не заменяет reviewer — только подсвечивает до сохранения файла.
- Не проверяет сам код `require_permission` в `backend/app/api/dependencies.py`.

## Источники для Analyst

- `docs/adr/0011-foundation-multi-company-rbac-audit.md` (обязательно; §2.1 каталог actions; §2.3 контракт `require_permission`).
- `docs/adr/0007-audit-log.md` — обязательность audit в той же транзакции.
- `backend/app/services/rbac.py` — реализация сервиса (как `require_permission` устроен).
- `backend/app/services/company_scoped.py` — UserContext.
- `backend/app/api/companies.py` — эталонный правильный роутер для валидации скила.
- `docs/agents/departments/backend.md` §RBAC — текстовые правила, которые скил кодифицирует.
- `~/.claude/skills/fz152-pd-checker/SKILL.md` — шаблон структуры.
- `docs/research/rfc/rfc-007-code-review-acceleration.md` §«Первопричины» — связь скила с reviewer-причинами.

## Ограничения

- Не менять регламент backend — через governance-director.
- Не коммитить.
- Не ставить задачу backend-dev-3 — только SKILL.md + эталонный прогон.

## DoD брифа

1. `~/.claude/skills/rbac-permission-wiring-checker/SKILL.md` создан в стиле `fz152-pd-checker`.
2. На живом `backend/app/api/companies.py` скил выдаёт PASS на 100% эндпоинтов (эталон).
3. На синтетическом bad-endpoint (с `require_role` вместо `require_permission`) скил выдаёт FAIL P0 с цитатой ADR-0011.
4. Отчёт Analyst'а Координатору: ≤500 слов, формат «что сделано / как валидировано / открытые вопросы».

## Метрика успеха после adopt

За Волну 2 M-OS-1.1A (US-03 Permissions + 3-5 новых API-роутеров): 0 PR-замечаний reviewer'а класса «require_permission missing» или «audit missing» на файлах, написанных с включённым скилом.
