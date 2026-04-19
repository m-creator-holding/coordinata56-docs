---
name: RFC-004 Phase I-a Hooks pilot — формальная ratification
description: Формальное одобрение перехода RFC-2026-004 из ready-for-director в pilot на основе одобрения Владельца (Telegram msg 1469, 2026-04-18) и результатов прогона мин 2026-04-18
type: governance-request
date: 2026-04-18
applicant: Координатор (backup-approver governance-auditor, резервный режим)
decision: approved-pilot-with-gate
reviewer: governance-auditor (backup-approver, force-majeure)
related:
  - docs/research/rfc/rfc-004-coordinator-routing-optimization.md
  - docs/research/rfc/rfc-004-hooks-phase-0-plan.md
  - docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log
  - docs/governance/CHANGELOG.md (запись Ретроспективный вердикт 2026-04-18 — Системная находка о backup-approver)
  - docs/adr/0017-hooks-defense-in-depth.md
---

# Заявка: RFC-004 Phase I-a Hooks pilot — ratification

## Контекст

RFC-2026-004 «Оптимизация маршрутизации Координатора» предлагает три трека:
- **Трек 1 Hooks (Phase I-a)** — 5 pre-commit и Claude Code хуков (H-1…H-5), 2 рабочих дня.
- Трек 2 TaskPacket — следующий шаг после Hooks.
- Трек 3 Orchestration Layer — отдельный пакет M-OS-1+.

Phase 0 plan пилота (`rfc-004-hooks-phase-0-plan.md`) подготовлен ri-director; Владелец одобрил 2 дня backend-dev + ri-analyst; прогон на 5 минах выполнен 2026-04-18 (`run-all-mines.log`). Данная заявка формализует перевод RFC-004 в статус `pilot`.

## Решение Владельца

**Telegram msg 1469 (2026-04-18):** Владелец одобрил включение 5 Claude Code Hooks (RFC-004 Phase I-a) как системы автоматических проверок перед действиями Claude Code.

Решение по существу принято Владельцем. Данная заявка — процессуальная формализация (frontmatter RFC-004 + CHANGELOG) в резервном режиме governance-auditor.

## Force-majeure обоснование

`governance-director` недоступен через Agent tool. Это 6-я force-majeure заявка за 2026-04-18. Прецедент backup-approver governance-auditor установлен ретроспективным вердиктом 2026-04-18 (Системная находка) и применён в заявке `2026-04-18-adr-0014-ratification.md`.

## Статус прогона мин 2026-04-18

Файл-источник: `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log` (прогон 2026-04-18T21:20:30+00:00).

| Мина | Хук | Результат | Комментарий |
|------|-----|-----------|-------------|
| Mine 1 — env-secret | H-1 | **PASS** | Блокировка `.env.production` по паттерну; exit 1; substring найден |
| Mine 2 — git-add-all | H-2 | **FAIL** | Пропустил 15 файлов с чужими workers молча; эвристика недоработана |
| Mine 3 — sendmessage-dormant | H-3 | MANUAL | Требует ручного прогона по `mine-3/reproduce.md` (Claude Code hook) |
| Mine 4 — agent-no-ultrathink | H-4 | MANUAL | Требует ручного прогона по `mine-4/reproduce.md` (Claude Code hook) |
| Mine 5 — ruff-unused-import | H-5 | **PASS** | ruff format --check заблокировал; exit 1 |

**Итог:** 2 PASS / 1 FAIL / 2 MANUAL. DoD-критерий §4.1 плана Phase 0 («минимум 4 из 5 мин заблокированы/поймаются warning'ом») **не выполнен** на автоматическом прогоне. Требуется: (1) фикс H-2, (2) ручная приёмка H-3/H-4 от ri-director.

## Обоснование перехода в `pilot` (не `adopted`)

1. Владелец одобрил сам факт включения (msg 1469) — это разблокирует дальнейшую работу по треку.
2. H-1 и H-5 — реальная ценность подтверждена (закрывают Б-01 литеральные секреты — топ-1 класс дефектов 38% по RFC-007, и ruff/format — основной источник nit-замечаний раунда 0).
3. H-2 требует доработки эвристики (оценка 0.5 дня backend-dev) — не блокирует старт пилота в боевом режиме, но блокирует переход `pilot → adopted`.
4. H-3, H-4 по природе Claude Code hooks не тестируются через bash-скрипт `run-all-mines.sh`; их приёмка — ручные сценарии через живую Agent-сессию, выполняется ri-director/ri-analyst отдельной задачей.
5. Статус `pilot` означает: хуки установлены на рабочей машине, работают, собирают метрики ложно-положительных срабатываний и времени коммита; adopt-решение выносится после прохождения gate.

## Gate до перевода в `adopted`

Переход `pilot → adopted` выносится отдельной заявкой только после одновременного выполнения:

1. **Все 5 мин PASS стабильно на 3 независимых прогонах.** Прогоны делает ri-analyst, лог каждого сохраняется рядом с `run-all-mines.log`. H-2 получает фикс эвристики; H-3/H-4 — ручные сценарии проходят приёмку ri-director (отчёт в `docs/research/pilots/`).
2. **Ложно-положительные ≤1/20** по §4.2 плана Phase 0 (замер ri-analyst на 20 легитимных операциях).
3. **Оверхед коммита ≤2 с** по §4.3 (замер через `measure-overhead.sh`).
4. **Отчёт ri-analyst** опубликован в `docs/research/pilots/YYYY-MM-DD-hooks-phase-0-report.md` (пока отсутствует).
5. **Вердикт governance** при adopt-заявке: clean / warnings (не critical).
6. **Обновление CLAUDE.md** раздел «Git» (удаление пункта «`git add -A` запрещён без просмотра» — переведено в хук H-2) выполняется одновременно с ratification adopt, не раньше.

Если gate не пройден в течение 7 календарных дней после начала пилота — заявка на `pilot → refine` с конкретным списком правок либо `pilot → reject` с мотивировкой.

## Скоуп правок по данной заявке

1. **`docs/research/rfc/rfc-004-coordinator-routing-optimization.md` frontmatter** — `status: ready-for-director → pilot`; добавить строку `pilot_started: 2026-04-18`; в related оставить как есть.
2. **`docs/governance/CHANGELOG.md`** — новая запись «RFC-004 Phase I-a Hooks pilot — ratification».
3. **Артефакты пилота (H-1, H-5) остаются в worktree** `/root/worktrees/coordinata56-hooks-pilot/` до фикса H-2 и ручной приёмки H-3/H-4.

**Что НЕ меняется этой заявкой:**
- CLAUDE.md (раздел «Git» — обновляется только при adopt).
- `departments/backend.md`, `departments/quality.md` (правила автоматизированных проверок — обновляются при adopt).
- ADR 0017 (Hooks Defense in Depth) — отдельный трек, статус не меняется этой заявкой.

## Согласованность с каноном

| Документ | Проверка | Результат |
|---|---|---|
| CLAUDE.md раздел «Процесс» | Reviewer до commit — хуки не заменяют reviewer, это доп. защитный слой; не противоречит | clean |
| CLAUDE.md раздел «Секреты и тесты» | H-1 прямо реализует правило про литералы секретов — согласован | clean |
| CLAUDE.md раздел «Git» | Правило `git add -A` реализуется H-2 — параллельно, не противоречит (правило остаётся действующим до adopt) | clean |
| CODE_OF_LAWS ст. 45а/45б | Интеграционный шлюз — хуки вне этой зоны (внутренний инструментарий) | clean |
| ADR 0017 (Hooks Defense in Depth) | Этот ADR — архитектурная рамка; pilot реализует Phase 0 рамки | clean |
| Конституция M-OS ст. 6 | Порядок изменения — через заявку + CHANGELOG, соблюдён | clean |
| departments/governance.md раздел «Исключение быстрый путь» | Force-majeure паттерн применим по прецеденту ADR 0014 | clean |

Противоречий не обнаружено.

## Вердикт

**APPROVED-PILOT-WITH-GATE** (governance-auditor backup-mode, force-majeure, 2026-04-18).

RFC-2026-004 переведён в статус `pilot`. Хуки H-1 и H-5 работают на pilot-worktree. Переход в `adopted` — отдельной заявкой после прохождения gate (6 условий выше).

**Ключевой аргумент:** Владелец одобрил прямо (msg 1469); H-1/H-5 PASS подтверждают ценность; H-2 фикс и H-3/H-4 ручная приёмка не блокируют pilot — они блокируют `adopted`. Разделение `pilot` vs `adopted` защищает от преждевременного раскатывания на основной worktree.

## Ретроспективное ревью

При восстановлении `governance-director` через Agent tool — заявка подаётся на ретроспективный approve (аналогично треку ADR-0013, ADR-0014).

## Открытые замечания (не блокируют ratify)

1. **DoD §4.1 формально не выполнен на прогоне 2026-04-18** (2 PASS вместо 4). Это причина статуса `pilot`, не `adopted`. Фиксируется явно, чтобы при ретроспективном ревью Директор видел trade-off.
2. **Процедура backup-approver** всё ещё не формализована в `departments/governance.md` раздел «Исключение быстрый путь» (тот же пробел, что в precheck 2026-04-22 §3.5 и в заявке ADR-0014). Рекомендация: отдельная заявка после стабилизации governance-director.
3. **CLAUDE.md раздел «Git»** остаётся неизменным до adopt — это корректно, но создаёт временное дублирование правила (в CLAUDE.md и в H-2). При adopt — правило переносится в автоматизированный слой.
4. **Worktree пилота** `/root/worktrees/coordinata56-hooks-pilot/` — не основная ветка; до adopt никакие хуки не коммитятся в main.

---

*Заявка подана и решена Координатором через governance-auditor (backup-mode) 2026-04-18. Основание: одобрение Владельца Telegram msg 1469 + прецедент backup-approver по Системной находке ретроспективного вердикта 2026-04-18 + неуспех Agent-вызова governance-director.*
