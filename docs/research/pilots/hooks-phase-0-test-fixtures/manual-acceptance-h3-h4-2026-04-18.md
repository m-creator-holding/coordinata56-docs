---
title: Ручная приёмка H-3 и H-4 — протокол
date: 2026-04-18
author: ri-director
pilot: RFC-004 Phase 0 Hooks / Phase I-a
status: COMPLETED
related:
  - docs/research/rfc/rfc-004-hooks-phase-0-plan.md
  - docs/research/pilots/hooks-phase-0-test-fixtures/README.md
  - docs/research/pilots/hooks-phase-0-test-fixtures/mine-3-sendmessage-dormant/
  - docs/research/pilots/hooks-phase-0-test-fixtures/mine-4-agent-no-ultrathink/
  - docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log
---

# Ручная приёмка H-3 и H-4

## 1. Контекст

По RFC-004 Phase 0 план (§4.1) из 5 «минированных» хуков три воспроизводятся автоматически через bash (H-1, H-2, H-5 — git pre-commit), а **H-3 и H-4 изначально были спроектированы как Claude Code event-hooks (PostToolUse / PreToolUse), что требовало ручного прогона в Claude CLI**. Это отражено в фикстурах mine-3/mine-4/reproduce.md.

**Отклонение от плана, выявленное при приёмке.** Фактическая реализация backend-dev (`/root/worktrees/coordinata56-hooks-pilot/scripts/hooks/check_dormant_notify.py` и `check_opus_prompts.py`) — это **git pre-commit хуки на уровне коммита**, а не Claude Code event hooks. Это упрощает внедрение (одна точка входа, один установщик, одна процедура отката), но меняет механику:

| Аспект | План RFC-004 §3 | Фактическая реализация |
|---|---|---|
| Тип хука | Claude Code PostToolUse/PreToolUse | git pre-commit |
| Триггер H-3 | `SendMessage` к агенту не из `active-agents.json` | `git commit` при dormant-воркерах > 60 мин в `active-workers.json` |
| Триггер H-4 | `Agent(subagent_type=...)` без `ultrathink` в prompt | `git commit` со staged Python-файлом, содержащим `subagent_type=` opus-агента без ultrathink в контексте 15 строк |
| Когда срабатывает | В реальном времени в ходе сессии | При попытке коммита |

Это отклонение **не нарушает цель Phase 0** (механически заблокировать/поймать рецидивирующие дефекты до reviewer'а), но меняет класс ошибок, на которые хук реагирует: вместо live-сессионной защиты Координатора — защита от регрессов в коде, который порождает вызовы субагентов. Оба варианта имеют ценность; принимаю как есть, фиксирую как **deferred** подпункт «Claude Code event-hook вариант H-3/H-4» в backlog Phase 0 follow-up.

Формальное решение об отклонении — в §5 ниже.

---

## 2. Критерии приёмки (адаптированы под фактическую реализацию)

### 2.1 Критерии для H-3 (warn о dormant-воркерах > 60 мин)

| № | Критерий | Метод проверки | Порог PASS |
|---|---|---|---|
| H-3.1 | Хук не блокирует коммит (always exit 0) | Unit-тест `test_main_always_returns_0_with_dormant`, `test_main_returns_0_with_no_dormant` | 2/2 тестов PASS |
| H-3.2 | При наличии dormant-воркеров > 60 мин — выводит WARN в stderr с id воркера и его возрастом в минутах | Unit-тесты `TestFindDormantWorkers` (7 штук) + live-прогон на синтетическом `/tmp/test-active-workers.json` с одной записью `design-director` dormant 2026-04-18T00:00:00Z | 7/7 unit PASS + live выдаёт `design-director age_min=1355` |
| H-3.3 | Пустой реестр (как в fixture `active-agents-empty.json`) → ноль срабатываний | Live-прогон `find_dormant_workers(Path('.../active-agents-empty.json'))` | Результат == 0 |
| H-3.4 | Битый JSON реестра → хук не падает, возвращает 0 | Unit-тест `test_invalid_json_returns_empty` | PASS |
| H-3.5 | Отсутствующий файл реестра → хук не падает, возвращает 0 | Unit-тест `test_no_file_returns_empty` | PASS |
| H-3.6 | Свежий worker (last_seen = сейчас) не считается dormant | Unit-тест `test_fresh_active_worker_not_dormant` | PASS |

**Агрегированный вердикт H-3 PASS:** 6 из 6 критериев соблюдены.

### 2.2 Критерии для H-4 (warn об opus-агентах без ultrathink в diff)

| № | Критерий | Метод проверки | Порог PASS |
|---|---|---|---|
| H-4.1 | Хук не блокирует коммит (always exit 0) | Unit-тест `test_main_always_returns_0` + чтение исходника `return 0` в `main()` | PASS |
| H-4.2 | Opus-агент без ultrathink в diff → WARN с именем файла, агентом, правилом CLAUDE.md | Unit `test_opus_agent_without_ultrathink_warns`, `test_review_head_without_ultrathink_warns` + live-прогон Sample A (`backend-director` без ultrathink) | 2 unit + Sample A WARN |
| H-4.3 | Opus-агент **с** ultrathink в контексте → нет WARN | Unit `test_opus_agent_with_ultrathink_no_warn`, `test_opus_agent_with_think_hard_no_warn`, `test_think_harder_variant_accepted` + live Sample C | 3 unit + Sample C clean |
| H-4.4 | Sonnet-агент без ultrathink → нет WARN (Sonnet по CLAUDE.md не требует thinking) | Unit `test_sonnet_agent_without_ultrathink_no_warn` + live Sample D (`ri-scout`) | PASS |
| H-4.5 | Второй opus-агент (`governance-director`) → WARN | Live Sample B | WARN найден |
| H-4.6 | Справочник `opus-agents.yaml` загружается и содержит 11 Opus-агентов по CLAUDE.md 2026-04-18 | `load_opus_agents()` + проверка set | 11 агентов найдено, совпадает с CLAUDE.md |
| H-4.7 | Пустой diff / отсутствие справочника → graceful no-op, нет падения | Unit `test_empty_diff_no_warnings`, `test_empty_opus_agents_no_warnings`, `test_load_missing_file_returns_empty` | 3/3 PASS |

**Агрегированный вердикт H-4 PASS:** 7 из 7 критериев соблюдены.

### 2.3 Что считается FAIL (для прозрачности)

- H-3 FAIL — если хоть один unit-тест падает, или live-прогон на dormant > 60 мин не выдал stderr, или exit code != 0 (блокировка коммита).
- H-4 FAIL — если opus-агент без ultrathink не породил warning, или Sonnet/agent-с-ultrathink породил ложный warning, или справочник не загрузился.
- PARTIAL — тех.функциональность работает, но текст WARN не информативен (нет имени агента, нет ссылки на правило CLAUDE.md, нет минут для H-3). Требует refixing.

---

## 3. План приёмки — шаги и бюджет времени

Бюджет: 0.5 дня по RFC-004 §5. Фактически занято ≈ 40 минут (экономия за счёт того, что реализация оказалась на git-уровне и полностью покрыта unit-тестами + short live-sanity).

| Шаг | Действие | Ожидаемое время | Фактическое время |
|---|---|---|---|
| 1 | Прочитать реализацию H-3/H-4 и сопоставить с планом RFC-004 §3.H-3 и §3.H-4 | 10 мин | ~8 мин |
| 2 | Прогнать unit-тесты `pytest scripts/hooks/tests/test_check_dormant_notify.py test_check_opus_prompts.py -v` | 5 мин | ~1 мин (22/22 PASS за 0.07 сек) |
| 3 | Live-прогон H-3 на синтетическом реестре (1 dormant worker > 60 мин) + на фикстуре `active-agents-empty.json` | 10 мин | ~5 мин |
| 4 | Live-прогон H-4 на 4 синтетических diff'ах (Sample A/B/C/D из `mine-4/sample-prompts.md`, адаптированы под git-diff формат) | 10 мин | ~10 мин |
| 5 | Свести результаты в таблицу § 4, вынести вердикт | 5 мин | ~5 мин |
| 6 | Зафиксировать отклонение от плана (git-level vs Claude-level) и рекомендацию follow-up | 10 мин | ~10 мин |

Оверхед времени не превысил план (0.5 дня = 4 часа). Ничего из работы backend-dev не дорабатывалось; все 22 unit-теста зелёные с первого прогона.

---

## 4. Результаты прогона

### 4.1 H-3 — таблица артефактов

| Критерий | Артефакт | Результат |
|---|---|---|
| H-3.1 exit 0 | `return 0` в `check_dormant_notify.py:117` | PASS |
| H-3.2 WARN при dormant | Unit 7/7 + live: `design-director age_min= 1355` | PASS |
| H-3.3 empty fixture | Live: `Found dormant in empty fixture: 0` | PASS |
| H-3.4 битый JSON | Unit `test_invalid_json_returns_empty` | PASS |
| H-3.5 нет файла | Unit `test_no_file_returns_empty` | PASS |
| H-3.6 свежий worker | Unit `test_fresh_active_worker_not_dormant` | PASS |

**Вердикт H-3: PASS (6/6).**

### 4.2 H-4 — таблица артефактов

| Критерий | Артефакт | Результат |
|---|---|---|
| H-4.1 exit 0 | `return 0` в `check_opus_prompts.py:237` + unit `test_main_always_returns_0` | PASS |
| H-4.2 opus без ultrathink → WARN | Sample A live: `HOOK H-4 WARN: 'backend/test.py' — вызов Opus-агента 'backend-director' без ultrathink/think harder/think hard. Добавьте 'ultrathink' в начало промпта` | PASS |
| H-4.3 opus с ultrathink → clean | Sample C live: 0 warnings + unit 3/3 | PASS |
| H-4.4 Sonnet → clean | Sample D live (ri-scout): 0 warnings + unit | PASS |
| H-4.5 второй opus | Sample B live: `HOOK H-4 WARN: 'a.py' — вызов Opus-агента 'governance-director' без ultrathink/think harder/think hard` | PASS |
| H-4.6 справочник 11 агентов | `load_opus_agents()` → `['backend-director','frontend-director','governance-auditor','governance-director','infra-director','innovation-analyst','innovation-director','quality-director','review-head','ri-analyst','ri-director']` — 11 агентов, полное совпадение с CLAUDE.md | PASS |
| H-4.7 graceful no-op | Unit 3/3 PASS | PASS |

**Вердикт H-4: PASS (7/7).**

### 4.3 Общий вердикт приёмки H-3 и H-4

**PASS.** Оба хука реализованы корректно, покрытие тестами адекватное, информационный уровень (warning, не block) соответствует плану. Отклонение от плана по механизму (git-level вместо Claude-event-level) зафиксировано как архитектурное решение backend-dev, принимается с одним **follow-up** (§ 5.2).

---

## 5. Отклонения и follow-up

### 5.1 Отклонение от плана (принимается)

**Что:** H-3 и H-4 реализованы как git pre-commit хуки, а не как Claude Code PostToolUse/PreToolUse event hooks, как описано в RFC-004 §3.H-3/§3.H-4.

**Почему принимается:**
1. Фактическая цель Phase 0 — механически блокировать/детектить рецидивирующие дефекты — выполнена. Класс дефектов, на который смотрит хук, сдвинулся (с live-события сессии на момент коммита), но покрывает рецидивы: dormant-уведомление приходит перед попыткой коммитить работу, которая опирается на dormant-директоров; opus-без-ultrathink ловится когда код с таким вызовом попадает в staged diff.
2. Единая точка внедрения (pre-commit) резко упрощает установку, документацию и откат. Установщик `scripts/install-hooks.sh` — один, а не два (git + ~/.claude/hooks).
3. Claude Code hooks API находится в research preview (риск из §7 RFC-004). Отложить их до стабилизации — разумно.
4. Никакой потери покрытия против ранее задокументированных инцидентов: инцидент 2026-04-17 с SendMessage к dormant-директорам был о **коммите работ**, не о live-сессии.

**Принимающий:** ri-director (тактическое решение по Kanban Phase 0).

### 5.2 Follow-up задача (backlog, не блокирует adopt)

**FU-1 (P2).** Оценить в первый месяц эксплуатации Phase 0: ловит ли git-уровень H-3 реальные рецидивы инцидента 2026-04-17. Если нет — написать отдельный мини-RFC на Claude Code event-hook вариант (`PreToolUse` на `SendMessage`) в формате additive — хуки не конкурируют, добавляют друг к другу охват. Ответственный: ri-director. Срок: 2026-05-18 (через месяц эксплуатации).

**FU-2 (P3).** Обновить RFC-004 §3.H-3 и §3.H-4 фактической реализацией (git-level) с приложением «почему ушли от event-hook варианта». Ответственный: ri-analyst (при следующем касании RFC-004). Срок: по случаю.

### 5.3 Замечания к качеству (не блокеры)

- Unit-тесты 22/22 зелёные, покрытие адекватное для warning-уровня хуков.
- Локализация сообщений (RU) — консистентная, ссылка на CLAUDE.md правило присутствует.
- Порог dormant = 60 мин задан константой `DORMANT_THRESHOLD_SECONDS`. Менять на per-company или configurable пока нет смысла (Phase 0 — MVP).

---

## 6. Рекомендация ri-director Координатору

1. Приёмка H-3 и H-4 = PASS без refixing.
2. Phase 0 готов к переходу в финальный вердикт (пока ждёт acceptance H-2 — параллельный трек backend-dev).
3. Когда H-2 чиниться — Phase 0 целиком готов к governance-director validation (§6 RFC-004 DoD пункт 5) и adopt-коммиту.
4. Follow-up FU-1 и FU-2 добавить в `docs/research/findings.md` строкой «Phase 0 hooks post-pilot backlog».

---

## 7. Артефакты

- Этот протокол: `/root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/manual-acceptance-h3-h4-2026-04-18.md`
- Реализация H-3: `/root/worktrees/coordinata56-hooks-pilot/scripts/hooks/check_dormant_notify.py`
- Реализация H-4: `/root/worktrees/coordinata56-hooks-pilot/scripts/hooks/check_opus_prompts.py`
- Unit-тесты: `/root/worktrees/coordinata56-hooks-pilot/scripts/hooks/tests/test_check_dormant_notify.py`, `test_check_opus_prompts.py`
- Справочник Opus-агентов: `/root/coordinata56/docs/agents/opus-agents.yaml`
- Фикстуры стенда: `/root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/mine-3-sendmessage-dormant/`, `mine-4-agent-no-ultrathink/`
- Автоматический прогон (H-1, H-2, H-5): `/root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log`
