# Weekly Sensing Brief for ri-scout — Round #3

- **Дата брифа:** 2026-04-19 (понедельник 10:00 МСК)
- **Автор:** ri-director (L2)
- **Исполнитель:** ri-scout (Sonnet)
- **Предыдущие раунды:** Round #1 2026-04-15 (пилотный); Round #2 2026-04-17 (фокус на transport/orchestration, 34 находок → 8 briefs).
- **Окно сканирования:** 2026-04-12 → 2026-04-19 (строго, отсечка по дате публикации/коммита).
- **Статус:** active.

---

## 1. Контекст (зачем этот раунд)

За прошлые две недели R&I залил в findings.md 70 строк. Ключевые треки:
- **RFC-003 (Mem0)** — pilot, ждёт backend-dev+qa.
- **RFC-004 (Hooks Phase 0 + TaskPacket)** — pilot-plan одобрен; Phase 0 ждёт старта; TaskPacket Phase I-b переносится (см. update в plan).
- **RFC-007 (Code review)** — v0.1, ждёт решения Координатора.
- **RFC-008 (Department automation)** — v1.0.
- **5 skills adopted** (`alembic-safe-migration-checker`, `api-contract-checker`, `test-secrets-hardening`, `git-staging-safety`, + `fz152-pd-checker` — живёт в `~/.claude/skills/`).

Дальше нужны не ещё 34 находки, а **узкий сигнал**: что **действительно нового** появилось у Anthropic/в экосистеме Claude Code за **одну неделю** — чтобы не пропустить перегиб индустрии (новый релиз SDK, новый `awesome-*`, новый skill-pattern).

---

## 2. Источники (приоритет сверху вниз)

| # | Источник | Что искать | Как часто сканировать |
|---|---|---|---|
| S1 | **Anthropic Release Notes** (`docs.anthropic.com/en/release-notes/claude-code`, `docs.anthropic.com/en/release-notes/api`) | Новые версии Claude Code CLI за 2026-04-12..19; новые hook-events; новые SDK-фичи; изменения в subagent API | ОБЯЗАТЕЛЬНО, 1 WebFetch |
| S2 | **Anthropic Blog** (`anthropic.com/news`) | Анонсы за неделю: managed agents, context capacity, новые модели | ОБЯЗАТЕЛЬНО, 1 WebSearch |
| S3 | **awesome-claude-code** + **awesome-claude-code-subagents** + **awesome-mcp-servers** на GitHub | Коммиты за неделю (`?since=2026-04-12`); новые записи в README | ОБЯЗАТЕЛЬНО, 1 WebFetch на каждый (до 3 вызовов) |
| S4 | **Simon Willison's Weblog** (`simonwillison.net/2026/Apr/`) | Заметки за 12-19 апреля: Claude Code case studies, новые паттерны, bug reports, comparisons | ОБЯЗАТЕЛЬНО, 1 WebFetch |
| S5 | **Hacker News** front page + `search.hn` за неделю | Story score >100, теги: `claude`, `mcp`, `agent`, `llm`, `prompt engineering`, `dev tools` | ОБЯЗАТЕЛЬНО, 1 WebSearch |
| S6 | **GitHub Trending weekly** (`github.com/trending?since=weekly`) | Репы с тегами `claude-code`, `mcp`, `ai-agents`, `llm` и ростом >500 звёзд/неделя | При бюджете, 1 WebFetch |

**Бюджет:** до 4 вызовов `WebFetch`+`WebSearch` согласно регламенту R&I §«Бюджет внимания». Приоритет S1→S5. S6 — только если бюджет остался.

---

## 3. Фильтры релевантности (что считается находкой)

Находка добавляется в `findings.md` только если соответствует **хотя бы одному** из критериев:

1. **Анти-регресс:** закрывает правило из нашего `CLAUDE.md` или ADR (пример: hooks-gate для правила «git add -A запрещён»).
2. **Ускорение существующего цикла:** code review, delegation, digest, pilot setup, testing.
3. **Покрытие пробела:** direction, где у нас пока пусто (observability, feature-flags, agent-to-agent native, voice prompt).
4. **Референс-кейс:** OSS-PR или блог-пост, где Claude Code решил задачу, типологически похожую на наши (multi-agent routing, security refactor, migration rollout).
5. **Нативное решение workaround'а:** Anthropic выпустил фичу, которая убирает нашу костыль-прослойку (пример: native subagent-to-subagent routing → Координатор-транспорт устаревает).

**НЕ находки (сразу в `_skipped.md`):**
- Duplicate за последние 30 дней.
- Self-promotion поста без кода/метрик.
- Коммерческие SaaS без open-source альтернативы (RFC-004 skipped по data-sovereignty).
- «Yet another todo-agent» без измеримой дельты.

---

## 4. Формат каждой находки (строго)

В `docs/research/findings.md` append-only строка:

```
| 2026-04-XX | <S1..S6> | <URL> | <Одной строкой: что делает + чем закрывает пробел> | <теги через запятую> | <кому адресовать> | Discovered |
```

**Обязательная расшифровка** (регламент R&I §«Обязательная расшифровка»): для каждой находки, которую Scout считает кандидатом на RFC — короткий mini-brief в `docs/research/briefs/brief-2026-04-19-<slug>.md` (5-15 строк) с тремя пунктами:
1. Что делает простым языком.
2. Чем полезно coordinata56 (конкретный сценарий).
3. Почему приоритет выше/ниже прочих.

---

## 5. Ожидания по объёму

- **Минимум:** 3 находки (если источники за неделю пустые — честный отчёт «за неделю новое: X, Y, Z», не больше).
- **Цель:** 5-10 находок + 2-3 mini-brief'а для кандидатов на RFC.
- **Максимум:** 15 (иначе Scout превысил бюджет внимания — см. регламент).

Если находок меньше 3 — приложить в отчёте Директору отдельную строку **«Candidate sources to add»** — какие источники Scout предлагает добавить в стартовый набор, чтобы в следующем раунде сигнал был плотнее (например, `lobste.rs`, `news.ycombinator.com/ask`, Anthropic Discord digest).

---

## 6. Приоритетные темы для этого раунда (tie-breaker)

При равной релевантности предпочесть находки по темам:
1. **Claude Code SDK изменения** — hook events, subagent lifecycle, routines, managed agents GA.
2. **Skill plugins / slash commands** — новые шаблоны, plugin marketplace обновления.
3. **MCP roadmap прогресс** — agent-to-agent native Q3 2026, можно ли уже тестировать.
4. **Memory layer** — обновления Mem0, LangGraph store, новые альтернативы (для RFC-003 pilot).
5. **Governance patterns** — policy engines, audit trails, compliance patterns (для RFC-005/008).

**Вне приоритета (skip):** prompt engineering tricks без кода, модели «от 7B до 400B» без связи с dev tools, general LLM research без воздействия на workflow субагентов.

---

## 7. Выход (deliverable)

Scout возвращает ri-director'у:
- Число добавленных строк в `findings.md` (append-only).
- Число mini-brief'ов в `docs/research/briefs/`.
- Рекомендации по 1-2 находкам для RFC (ri-analyst дальше разберёт).
- Если бюджет превышен / источники глухие — честная запись «на этой неделе пусто по источникам X, Y» + предложение расширить источники.

Срок — одна сессия (≤2 часа по регламенту). После сдачи ri-director формирует weekly digest Координатору.

---

*Бриф подготовлен ri-director 2026-04-19. Не является нормативным актом. Scout не спавнится этим документом — запуск решает Координатор.*
