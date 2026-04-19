# CLAUDE.md → Skills: top-3 кандидатов на lazy-load

**Автор:** ri-director
**Дата:** 2026-04-19
**Параллельно:** governance-auditor (общий аудит CLAUDE.md), ri-analyst (skill #1 `alembic-safe-migration-checker` уже в работе).
**База:** CLAUDE.md M-OS v2026-04-18, 79 строк, 8 разделов.

---

## Линза R&I

Martin Fowler (2026): правила, применяемые <5% сессий, раздувают always-on контекст (context rot). Лучший формат — skill: лежит в `~/.claude/skills/<name>/SKILL.md`, подгружается Claude Code только когда описание (`description:`) матчится keyword'ами задачи. CLAUDE.md остаётся навигатором на 30-40 строк, а не справочником на 150+.

## Оценка разделов CLAUDE.md

| Раздел | Строк | Частота применения | Keyword-триггеры | Кандидат? |
|---|---|---|---|---|
| Нормативная база (9-19) | 11 | Всегда | — | Нет (навигатор) |
| Процесс (22-34) | 13 правил | Часто (meta) | — | Нет (Координатор-уровень, всегда нужно) |
| Данные / ПД (36-39) | 4 | При ПД | — | Уже skill `fz152-pd-checker` |
| **Данные и БД (42-45)** | 3 | **При БД/миграции/пагинации** | `миграция`, `alembic`, `LIMIT`, `пагинация`, `enum` | **Частично** (миграции → `alembic-safe-migration-checker`; остаток → кандидат #2) |
| **Секреты и тесты (48-51)** | 4 | **При тестах/conftest/паролях** | `pytest`, `conftest`, `fixture`, `password`, `token`, `secret` | **Да — #3** |
| **API (54-58)** | 4 | **При API-роуте/эндпоинте** | `router`, `endpoint`, `@app.`, `APIRouter`, `HTTPException`, `pagination`, `audit` | **Да — #2 (главный)** |
| Код (61-64) | 3 | Всегда | `type: ignore`, `# noqa` | Нет (слишком короткий + `routers/` — навигация) |
| **Git (67-70)** | 3 | **При git-операциях** | `git add`, `git commit`, `git status` | **Да — #4 (второстепенный)** |

## Top-3 рекомендаций (порядок приоритета)

### #2 — `api-contract-checker` (API раздел)
**Зачем:** самое частое нарушение Sprint 1 — `{"detail": "..."}` вместо ADR-0005 envelope, голый массив вместо `{items, total, offset, limit}`, write-эндпоинт без `audit_service.log()`. Ловится только в ревью, а Claude Code мог бы подсказать при написании роутера.
**Триггеры:** работа в `backend/app/api/*.py`, создание FastAPI-роутера, `@router.get/post/put/delete`, `HTTPException(`, `return {...}` в handler'е.
**Размер:** 4 строки CLAUDE.md → SKILL.md ~120-150 строк (с примерами ADR-0005/0006/0007 + IDOR-кейс).

### #3 — `test-secrets-hardening` (Секреты и тесты)
**Зачем:** правило ловилось **трижды** (Phase 2 Round 2 BLOCKER-1, Phase 3 Batch A step 2 Round 1 P0-2, регламент v1.3 §3). Повторная ошибка = кандидат на автоматизацию.
**Триггеры:** работа в `backend/tests/**`, `conftest.py`, `fixtures/`, `pytest.fixture`, grep на `password = "..."` / `token = "..."` в тестах.
**Размер:** 4 строки CLAUDE.md → SKILL.md ~80-100 строк (чек-лист `secrets.token_urlsafe` + пример фикстуры с random + ПД-маскирование в логах тестов).

### #4 — `git-staging-safety` (Git раздел)
**Зачем:** `git add -A` уже ловился (2026-04-15 qa батча A попал в чужой коммит). При параллельной работе 5-15 субагентов (msg 1433) риск только растёт.
**Триггеры:** `git add`, `git commit -a`, `git stash`, перед любым коммитом из Claude Code; вспомогательно — работа при активных фоновых Agent-вызовах.
**Размер:** 3 строки CLAUDE.md → SKILL.md ~60-80 строк (алгоритм: `git status --short` → выбор файлов → запрет `-A` при running background agents + шаблон commit message «почему, не что»).

## Не рекомендую в skills (осознанно)

- **Процесс §Координатор-транспорт, SendMessage, verify-before-scale** — это meta-правила Координатора, активны всегда, не специфичные. Место в `docs/agents/regulations/coordinator.md`, не в skill.
- **Код §`# type: ignore`** — слишком короткий (3 строки), триггер `# type: ignore` покрыт ruff.
- **Данные/ПД** — уже skill.

## Эффект на CLAUDE.md после выноса 4 skills (#1-#4)

- Сейчас: 79 строк.
- После (ожидание): 30-35 строк. Остаются: нормативная база (11) + Процесс (meta-правила Координатора, 13) + заголовки-указатели на skills (6-8). Context rot -50%.

## Next steps для Координатора

1. Утвердить top-3 с Владельцем (≤200 слов на вход).
2. Спавн ri-analyst x3 (параллельно, бюджет 4ч каждый) по брифам:
   - `skill-brief-api-contract-checker.md`
   - `skill-brief-test-secrets-hardening.md`
   - `skill-brief-git-staging-safety.md`
3. Координатор (после ревью SKILL.md review-head) обновляет CLAUDE.md — удаляет вынесенные разделы, оставляет ссылки: «см. skill `<name>`».
4. governance-auditor фиксирует прецедент в `docs/agents/CODE_OF_LAWS.md` — правило «Если раздел CLAUDE.md применяется <20% сессий и имеет чёткий keyword-триггер, он выносится в skill».
