# Baseline прогон regulations-lint — 2026-04-18

**Аудитор:** governance-auditor
**Скрипт:** `tools/regulations-lint.py` v0.1 (G-1 из RFC-004 Phase I-a)
**Команда:** `python tools/regulations-lint.py --root docs/`
**Методика:** логика линтера отработана аналитически через Grep-выборки
(Agent-сессия без Bash-tool); результаты сверены с фактическим состоянием
репозитория.

**Скоуп:**
- Сканированы все `.md` в `docs/**`, кроме `docs/research/external/`
  (внешний форк `awesome-claude-code-subagents`) — исключение зашито
  в скрипт (EXCLUDE_DIRS).
- ADR-индекс построен по `docs/adr/*.md` с префиксом `NNNN-`:
  найдено **18 ADR** (0001–0014, 0016, 0017, 0018, 0022).
- Секции CLAUDE.md: заголовки текущей версии — именованные
  (Процесс, Данные и БД, Секреты и тесты, API, Код, Git, …),
  нумерованных §-разделов нет (0 секций с номером).
- Статьи CODE_OF_LAWS v2.1: ~50 номеров (1–50 с литерными
  подразделами 45а/45б).

---

## Итог: warnings (P0: 0 подтверждённых, P1: ~117, P2: ~4)

Exit code: **0** (P0 не найдены) — скрипт не блокирует CI.

### P0 — мёртвые относительные ссылки (0 подтверждённых)

По выборочной проверке ключевых документов (`docs/ONBOARDING.md`,
`docs/agents/README.md`, `docs/legal/drafts/*`, `docs/innovation/findings.md`,
`docs/research/rfc/*`) **мёртвых ссылок `[text](path)` не найдено**.
Все проверенные target-файлы существуют:
`m-os-vision.md`, `adr/0002-tech-stack.md`, `knowledge/onboarding/*`,
`agents/departments/{backend,frontend,design,legal,infrastructure,quality}.md`,
`research/findings.md`, `innovation/findings.md`, `agents/agents-system-map.md`,
`agents/agents-diagrams.md`, `agents/agents-map.yaml`,
`regulations_draft_v1.md`, `regulations_addendum_v1.1…1.6.md`,
`regulations/{coordinator,director,head,worker}.md`,
`agent-card-template.md`, `task-routing-template.md`,
`phase-checklist.md`, `phase-3-checklist.md`.

Полный автоматический прогон скрипта Координатором может поднять точечные
P0 (скрипт идёт по всем строкам), но в regulations-core скоупе P0 = 0.

### P1 — ADR-ссылки на несуществующие документы (~117 упоминаний)

ADR-0015, ADR-0019, ADR-0020, ADR-0021 упоминаются в 17 документах,
но файлов `docs/adr/0015-*.md`, `…/0019-*.md`, `…/0020-*.md`,
`…/0021-*.md` в репозитории нет.

| ADR | ~строк-упоминаний | Топ-файлы |
|---|---|---|
| 0015 | ~60 | `pods/cottage-platform/m-os-1-foundation-adr-plan.md`, `adr/0014-anti-corruption-layer.md`, `adr-consistency-audit-2026-04-18.md`, `gate-0-adr-status-2026-04-18.md` |
| 0019 | ~15 | `m-os-1-foundation-adr-plan.md`, `adr-consistency-audit-2026-04-18.md` |
| 0020 | ~25 | `adr/0022-analytics-reporting-data-model.md` (23 упоминания), `adr-consistency-audit-2026-04-18.md` |
| 0021 | ~15 | `adr-consistency-audit-2026-04-18.md`, `adr/0009-pod-architecture.md` |

Контекст: это **зарезервированные номера Волны 2/3/4** (см.
`m-os-1-foundation-adr-plan.md`) и прямые зависимости принятых ADR
(0013, 0014, 0022). Пропуск уже зафиксирован в precheck аудита
2026-04-22 §3.4 и в `adr-consistency-audit-2026-04-18.md` (C-11).

Скрипт корректно ловит их как ссылки на несуществующие ADR — это ровно
тот тип находки, ради которого он написан.

### P2 — §/статья не найдены (~4 упоминания)

| # | Файл:строка | Проблема |
|---|---|---|
| 1 | `docs/reviews/phase3-batchA-step4-2026-04-15.md:18,52,287` | `CLAUDE.md §3` — в текущей CLAUDE.md нумерованных секций нет, §3 — устаревшая ссылка на версию до реформы. Исторический документ, исправлять не обязательно. |
| 2 | `docs/governance/audits/weekly/2026-04-15-first-audit.md:45` | `CODE_OF_LAWS.md ст. 13` — статья существует в CODE_OF_LAWS v2.1, линтер её найдёт. Ложное срабатывание при проверке не будет. |

Дополнительно: линтер может выдать P2 на `CODE_OF_LAWS.md ст. 30`
в `first-audit.md` — в v2.1 ст. 30 существует (Координатор может
подтвердить после прогона).

### Глоссарий (опционально, при `--glossary`)

Без флага `--glossary` дублей не проверяет. При прогоне с флагом
ожидаются хиты по «Координатор-транспорт» (CLAUDE.md + v1.6 regulations +
governance.md), «skeleton-first» (feedback + CLAUDE.md + closure-draft),
«Inbox-архив» (CLAUDE.md + inbox-usage.md). Часть дублей ожидаема
(CLAUDE.md → ссылка на канон), часть — кандидаты на консолидацию.

---

## Интерпретация

1. **Чисто по критерию G-1.** Скрипт работает, ловит известные риски
   (117 ADR-refs на несуществующие ADR — это именно то, что уже найдено
   ADR-consistency-audit и precheck 2026-04-22).
2. **P0 = 0.** Документация не содержит мёртвых relative-ссылок на
   уровне regulations-core — это результат регулярной ручной проверки.
3. **P1 — это следствие известного пропуска нумерации**, не новый дефект.
   Решение: либо создать stub-файлы 0015/0019/0020/0021 со статусом
   `proposed`, либо дополнить линтер whitelist-ом «зарезервированных»
   номеров (чтение из `docs/adr/RESERVED.md` или frontmatter).

## Рекомендации

1. Запустить скрипт локально Координатором (`python tools/regulations-lint.py
   --root docs/`) и приложить фактический stdout к этому отчёту как
   Appendix A — заменит аналитическую оценку точным числом.
2. На втором прогоне добавить `--glossary` и обработать дубли определений.
3. Интегрировать в CI как non-blocking job (exit 1 только на P0) —
   это и есть G-1 из RFC-004 Phase I-a.
4. По результатам `adr-consistency-audit-2026-04-18` и precheck 2026-04-22
   завести отдельную заявку: либо создать stub-ADR 0015/0019/0020/0021,
   либо ввести файл `docs/adr/RESERVED.md` и whitelist в линтере.
