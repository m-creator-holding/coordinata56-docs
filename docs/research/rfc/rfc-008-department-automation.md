---
id: RFC-2026-008
title: Department Automation & Acceleration — ускорение 9 департаментов через шаблоны, скрипты, SKILL.md, хуки и CI
status: v1.0
date: 2026-04-18
author: ri-director (совмещение с ri-analyst — Analyst dormant, регламент R&I §«Совмещение ролей»)
reviewers:
  - coordinator (решение по Top-5 quick-wins, выделение исполнителей)
  - backend-director (подтверждение B-1…B-3)
  - frontend-director (подтверждение F-1…F-3)
  - quality-director (подтверждение Q-1…Q-3)
  - governance-director (изменения регламентов при adopt)
  - infra-director (dormant — Координатор решает активацию под этот RFC)
  - design-director, innovation-director, tech-writer (информирование)
source_findings: findings.md 2026-04-17 (R&I-cross-audit) + интерим-анализ работы 2026-04-15..2026-04-18
related:
  - docs/research/rfc/rfc-005-cross-audit-departments.md (предшественник — что есть в индустрии)
  - docs/research/rfc/rfc-004-hooks-phase-0-plan.md (H-1..H-5, фундамент для многих пунктов)
  - docs/research/rfc/rfc-007-code-review-acceleration.md (adopted — Code review закрыт)
  - docs/research/rfc/rfc-001-claude-code-routines.md (cron-автоматизация digest/reviewer)
  - docs/agents/departments/*.md (9 файлов)
---

# RFC-2026-008: Department Automation & Acceleration

## 0. Расшифровка простым языком для Владельца (обязательный раздел)

### Что делаем

Представьте холдинг, где девять отделов: бухгалтерия, юристы, служба безопасности, прорабы, дизайнеры, техотдел, архив, разведка и отдел новых идей. Каждый отдел пишет отчёты, проверяет чек-листы, готовит типовые документы. Если каждый инженер руками заполняет одно и то же поле в десятом отчёте — это потеря часов в неделю и путь к ошибкам.

Этот RFC — карта, где именно у нас в каждом из девяти программных отделов coordinata56 сейчас живут **ручные операции, которые можно превратить в шаблон, скрипт или автоматическую проверку**. Не «внедрим что-нибудь модное», а **«возьмём повторяющуюся ручную работу и заменим её на автомат»**. RFC-005 показал, чего индустрия умеет, а у нас нет. Этот документ — следующий шаг: **что из того, что мы уже умеем, можно делать быстрее и без ошибок**.

### Зачем это нам

Три конкретных эффекта:

1. **Скорость работы субагентов.** При M-OS-1 одновременно работают шесть Директоров. Если каждый бриф пишется с нуля — Координатор тратит 20-30 минут на каждый, вместо 5. Шаблоны брифов и типовых отчётов возвращают 2-3 часа Координатора в день.
2. **Меньше ошибок.** Сейчас 60% круглой повторяющейся работы (литералы секретов, забытые проверки parent_id, drift миграций) ловится reviewer'ом постфактум. Автоматическая проверка на уровне git-hook или CI ловит то же самое за 0.3 секунды до того, как оно попадёт в код.
3. **Снижение порога входа нового субагента.** Когда в июле 2026 активируем второго backend-dev или infra-director — у них будет не 168-страничный регламент, а **скелет, шаблон, работающий пример и автоматический чек-лист**. Первая задача закроется не за неделю ввода в контекст, а за один рабочий день.

### Что предлагаем внедрить

Top-5 quick-wins, каждый с ясной оценкой часов и ответственным (детали — §5):

1. **Hooks Phase 0 (5 скриптов) — старт пилота** по уже готовому плану RFC-004 phase-0. 2 дня backend-dev + ri-analyst. Закрывает 3 из 5 первопричин RFC-007. Уже одобрено Владельцем 2026-04-18.
2. **SAST в CI (Bandit + pip-audit)** — из RFC-005 Top-10 #3. 1 день qa + devops. Ловит CVE зависимостей и hardcoded secrets автоматически.
3. **Шаблон backend-dev CRUD-задачи как Makefile-цель** — `make scaffold-crud ENTITY=<name>` генерирует 6 файлов-скелетов (schema, repository, service, api, tests, registration). 1 день backend-dev. Экономит 15-20 минут на каждую новую сущность.
4. **Docs-validation в CI** — lychee (битые ссылки) + markdownlint + валидация frontmatter по JSON-схеме. 1 день qa. Закрывает drift-риск Doc-2 из RFC-005.
5. **Weekly digest как Claude Code Routine** — автозапуск по cron, не на памяти Координатора. 0.5 дня Координатора (настройка в веб-интерфейсе). Делает RFC-001 живым.

Общая оценка первых пяти: ~6 рабочих дней в течение 2-3 недель, не блокирует M-OS-1. Ещё 15 пунктов P1-P3 — в §4.

---

## §1. Задача и скоуп

Запрос Координатора 2026-04-18: по девяти программным отделам coordinata56 разобрать, **что в их работе можно автоматизировать через шаблоны, скрипты, SKILL.md-файлы, workflow-хуки и CI-интеграции**. Это **не то же самое**, что RFC-005: RFC-005 закрывал риски и пробелы относительно индустрии. RFC-008 — **про ускорение уже работающих процессов** нашими силами, без внешних инструментов.

**Входы:** 9 регламентов `docs/agents/departments/*.md`, 30 существующих скилов в `~/.claude/skills/`, 2 CI-workflow, RFC-001/004/005/007, findings.md (75+ строк), опыт Фаз 0-3 + M-OS-0 (зафиксирован в `docs/reviews/`).

**Выход:** единый документ с as-is по автоматизации каждого отдела + 1-3 предложения на отдел + сводный Top-10 + план первых 5.

**Не входит в скоуп:**
- Внедрение нового стека (fetch новых фреймворков — это RFC-005-линия).
- Автоматизация бизнес-логики M-OS (BPM, BPMN) — это ADR 0012 / Фаза 4+.
- Автоматизация для Advisory-субагентов (architect, legal, memory-keeper и т.д.) — они работают по запросу Координатора, им шаблоны не нужны в том же смысле.

---

## §2. Методология

Для каждого из 9 отделов — единая таблица:

| Блок | Что смотрю |
|---|---|
| **as-is** | Что уже автоматизировано (скрипты, скилы, CI-jobs, шаблоны). Что делается руками. |
| **Кандидаты** | Какие повторяющиеся операции имеют потенциал автоматизации. |
| **Рекомендации** | 1-3 конкретных предложения: артефакт, эффект, затраты, риск, приоритет. |

Оценки — экспертные (я не запускал замеры). Базис:
- «Эффект high» = экономия ≥ 2 часов субагента в неделю ИЛИ закрытие повторяющегося P0/P1-дефекта.
- «Эффект med» = экономия 0.5-2 часа в неделю ИЛИ P2-дефект.
- «Эффект low» = экономия < 0.5 часа или удобство без измеримого выигрыша.
- «Затраты» — в человеко-часах на внедрение силами одного backend-dev / qa / devops.
- **Приоритет:**
  - **P0** — внедрить в течение 2 недель, закрывает живой риск или явное узкое место.
  - **P1** — внедрить в течение месяца, улучшение среднего уровня.
  - **P2** — хорошо бы, но можно отложить на M-OS-2.
  - **P3** — зафиксировать как идею, пока не делать.

---

## §3. По департаментам

### §3.1. Backend

**as-is:**
- Шаблон промпта backend-dev CRUD-сущности в `departments/backend.md` (строки 82-110) — текстовый, копируется вручную.
- Чек-лист самопроверки ADR-gate A.1-A.5 — markdown-текст, без инструмента валидации.
- Линтер миграций `tools/lint_migrations` + CI job `lint-migrations` — автоматизирован (ADR 0013).
- Round-trip миграций в CI — автоматизирован.
- `ruff check` в CI — есть.
- Hook H-5 (ruff + fast-тесты pre-commit) — в плане RFC-004-phase-0 (ещё не реализован).

**Ручные операции-кандидаты:**
1. Scaffold 6 файлов для новой CRUD-сущности (schema/repo/service/api/tests/main registration) — сейчас копируется руками с эталона Project (~15-20 минут).
2. Проверка ADR-gate A.1-A.5 перед PR — визуально, в голове backend-dev.
3. Grep `from sqlalchemy import select` вне `backend/app/repositories/` — сейчас это уже нарушение ADR 0004 MUST #1a, но ловит только reviewer.

**Рекомендации:**

**B-1 [Эффект: high | Затраты: 1 день backend-dev | Риск: low | P0]**
Makefile-цель `make scaffold-crud ENTITY=<name>` + Jinja2-шаблоны в `backend/tools/templates/crud/*.j2`. Запуск: `make scaffold-crud ENTITY=invoice` создаёт 6 файлов-скелетов, готовых к редактированию (модели-плейсхолдеры, TODO-комментарии, тесты-заглушки). Артефакт: `backend/tools/scaffold.py` + папка шаблонов. Экономит 15-20 мин × ~10-15 новых сущностей в M-OS-1 = **2-4 часа backend-dev + 2 часа reviewer** (меньше formatting-nit'ов).

**B-2 [Эффект: high | Затраты: 0.5 дня backend-dev | Риск: low | P0]**
Ruff custom rule (через `ruff` custom plugin или простой `bandit`-like скрипт в `backend/tools/check_layers.py`) на запрет `from sqlalchemy import select|update|delete|insert` в файлах `backend/app/services/**/*.py` и `backend/app/api/**/*.py`. Запуск в CI job `layer-check`. Артефакт: `backend/tools/check_layers.py` + CI job. Автоматизирует причину №2 из RFC-007 (SQL вне репозитория, 25% раундов ревью).

**B-3 [Эффект: med | Затраты: 0.5 дня backend-dev | Риск: low | P1]**
SKILL.md `backend-crud-scaffolding` в `~/.claude/skills/` — интерактивный: Claude Code при запросе «реализуй CRUD для X» запускает скил, который последовательно спрашивает/предлагает поля модели, RBAC-матрицу, бизнес-правила, и вызывает `make scaffold-crud`. Артефакт: `~/.claude/skills/backend-crud-scaffolding/SKILL.md`. Дополняет B-1 для работы из агентной сессии.

**Автоматизированное пересечение:** B-2 закрывает то же, что Hook H-5 (RFC-004), но на уровне CI. Hook работает локально (не все исполнители запускают), CI — gate обязательный. Нужны оба.

---

### §3.2. Frontend

**as-is:**
- Регламент v1.1 (391 строка) с 4 стандартами (Query Key Factory, Controlled Select, `Button asChild`, 5 состояний UI).
- `npm run codegen` — генерация типов из OpenAPI, автоматизирована (вывод коммитится).
- data-testid конвенция — ручная (чек-лист у Head).
- MSW-handlers — пишутся руками по образцу `companies.ts`.
- `npm run lint && typecheck && build` — команды есть, запускаются руками dev'ом и Head.
- `rollup-plugin-visualizer` для bundle budget — ручной запуск.

**Ручные операции-кандидаты:**
1. Scaffold новой сущности (page + api-hooks + zod-schema + MSW-handler + fixture + e2e-spec) — ~30-45 минут копирования с образца Companies.
2. Проверка 4 стандартов v1.1 (Query Key Factory, Controlled Select, Button asChild, 5 состояний) — руками frontend-head.
3. Bundle budget — ручной gzip-check, Head смотрит глазами.

**Рекомендации:**

**F-1 [Эффект: high | Затраты: 1 день frontend-dev | Риск: low | P0]**
Plop.js-генератор (или простой Node.js-скрипт) `npm run scaffold:entity -- --name Contract` — создаёт 7 файлов по паттерну Companies: page, api-hooks, zod-schema, MSW handler+fixture, e2e-spec, registration в routes.tsx. Артефакт: `frontend/tools/scaffold/` + templates. Экономит 30-45 мин × ~8 новых сущностей в M-OS-1 = **4-6 часов frontend-dev**.

**F-2 [Эффект: med | Затраты: 0.5 дня frontend-dev | Риск: low | P1]**
ESLint custom rule (через `eslint-plugin-local-rules`) на 4 стандарта отдела: `no-defaultvalue-on-controlled-select`, `no-raw-query-key-literals` (требует `<entity>Keys.*`), `no-button-onclick-navigate` (требует `<Button asChild><Link>`). Артефакт: `frontend/eslint-local-rules/*.js` + подключение в `.eslintrc.cjs`. Автоматизирует ручную проверку frontend-head.

**F-3 [Эффект: med | Затраты: 0.5 дня devops | Риск: low | P2]**
Bundle budget CI job: `npm run build && node tools/check-bundle-budget.js` — падает при превышении baseline +50KB. Артефакт: `frontend/tools/check-bundle-budget.js` + CI job в `.github/workflows/frontend-ci.yml` (новый). Работает после F-1. Автоматизирует §6.4 регламента.

---

### §3.3. Design

**as-is:**
- Регламент v1.0 (165 строк) — процесс «бриф → designer → ux-head → director».
- Wireframes — markdown-файлы в `docs/pods/cottage-platform/tasks/wireframes-*.md`.
- Self-review designer'а — чек-лист из 6 пунктов (руками).
- ux-head проверяет полноту (6 блоков на экран) — руками.
- Скил `ui-ux-pro-max`, `frontend-design`, `composition-patterns` — уже в `~/.claude/skills/`.

**Ручные операции-кандидаты:**
1. Создание нового wireframe-файла — копирование структуры 6 блоков из предыдущего.
2. Self-review designer'а и первичное ревью ux-head — по чек-листу руками.
3. Нет связи wireframe ↔ frontend page-implementation (drift).

**Рекомендации:**

**D-1 [Эффект: med | Затраты: 0.25 дня design-director | Риск: low | P1]**
Шаблон wireframe в `docs/pods/<pod>/tasks/_wireframe-template.md` — пустая структура 6 блоков (personas / text layout / fields / states / flows / openapi-ref). + cookiecutter-like команда в Makefile pod-а: `make wireframe ENTITY=contract BATCH_ID=m-os-1-4`. Артефакт: шаблон + Makefile-цель. Экономит 15 мин × ~15 экранов = **4 часа designer'а**.

**D-2 [Эффект: med | Затраты: 0.5 дня tech-writer | Риск: low | P1]**
Linter для wireframe-файлов: `tools/lint-wireframe.py` проверяет наличие 6 обязательных секций, упоминание shadcn/ui компонентов, отсутствие «живых интеграций» кроме Telegram (CODE_OF_LAWS ст. 45а). Запуск в CI `docs-validation.yml` на файлы `docs/pods/**/wireframes-*.md`. Артефакт: скрипт + расширение CI. Автоматизирует self-review и часть ревью ux-head.

**D-3 [Эффект: low | Затраты: 0.5 дня frontend-dev | Риск: low | P2]**
Двусторонняя ссылка wireframe ↔ frontend-page: в frontmatter wireframe указывать `implementation: frontend/src/pages/admin/<entity>/...`, CI проверяет что файл существует. Артефакт: расширение `docs-validation.yml`. Закрывает drift, но малая частота срабатывания.

---

### §3.4. Quality

**as-is:**
- Регламент v1.1 (151 строка), чек-лист reviewer (12 пунктов) и self-check qa.
- Pre-commit review до `git commit` — регламент v1.3 §1.
- Spot-check режим reviewer при валидном self-check отчёте backend-dev (правило 11, добавлено 2026-04-18).
- Еженедельный random-full-audit для калибровки.
- Нет SAST (Bandit / semgrep) в CI, нет DAST.
- OWASP API Top 10 / AI Testing Guide — декларативно (см. RFC-005 Q-2, Q-4, не внедрены).
- Скил `owasp-top10-checklist` — есть.

**Ручные операции-кандидаты:**
1. Проверка self-check отчёта backend-dev на валидность (артефакты A.1-A.5) — руками reviewer'а.
2. Формирование отчёта ревью — сейчас free-form markdown.
3. Сбор baseline-метрик (раунды на PR, P0/P1/P2/P3 распределение) — ручные таблицы.

**Рекомендации:**

**Q-1 [Эффект: high | Затраты: 1 день qa + devops | Риск: low | P0]**
SAST в CI: Bandit + pip-audit (из RFC-005 Top-10 #3). Артефакт: CI job `security-scan` в `.github/workflows/ci.yml` + baseline-отчёт + правило в `departments/quality.md` v1.2. Ловит автоматически: hardcoded secrets, SQL injection patterns, CVE в зависимостях. Освобождает security-auditor от ручной фазы-wide проверки.

**Q-2 [Эффект: med | Затраты: 0.5 дня quality-director | Риск: low | P1]**
Шаблон review-report как Markdown-структура с обязательными секциями (Summary / P0 / P1 / P2 / P3 / Test coverage / Self-check validation). Артефакт: `docs/reviews/_template.md` + скрипт `tools/new-review.py phase-X-batch-Y` создаёт файл с заполненным frontmatter. Ускоряет формирование отчёта и **делает метрики парсимыми** (для автоматического сбора в weekly digest).

**Q-3 [Эффект: med | Затраты: 0.5 дня ri-analyst | Риск: low | P1]**
Скрипт `tools/review-stats.py` — парсит все `docs/reviews/*.md` за N дней, выводит агрегацию: среднее раундов, распределение P0/P1/P2, топ-5 первопричин (по тегам в отчётах). Запуск еженедельно перед weekly digest R&I. Артефакт: скрипт. Закрывает R-1 из RFC-005 (outcome-метрики) для Quality.

---

### §3.5. Infrastructure

**as-is:**
- Регламент v0.1 (34 строки, СКЕЛЕТ) — dormant.
- `docker-compose.yml` dev.
- CI — 2 workflow (ci.yml с ruff/lint-migrations/round-trip + docs-validation.yml).
- Нет observability, нет deploy-процедуры, нет backup-скриптов, нет incident runbook.
- В RFC-005 — infra-director активация = P0.

**Ручные операции-кандидаты:**
1. Запуск локального dev-стека — `docker compose up` (OK, автоматизировано).
2. Альембик-миграции — `alembic upgrade head` (OK).
3. Всё остальное (deploy, backup, восстановление) — пока нет.
4. Отсутствие IaC для второго окружения (staging) — при появлении будет ручная настройка.

**Рекомендации:**

**I-1 [Эффект: high | Затраты: 2 дня infra-director (после активации) | Риск: med (не активирован) | P0]**
Регламент infrastructure.md v1.0 вместо скелета (пересекается с RFC-005 Top-10 #5). Артефакт: регламент 120+ строк (разделы: CI/CD стандарты / Deploy / Backup / Incident runbook / Метрики). **Это предусловие для всех остальных I-пунктов.**

**I-2 [Эффект: med | Затраты: 0.5 дня devops | Риск: low | P1]**
Backup-скрипт `infra/scripts/backup-db.sh` + cron-задача на dev/staging: `pg_dump` каждые 24ч, хранение 7 дней, при восстановлении — скрипт `restore-db.sh`. Артефакт: 2 bash-скрипта + systemd timer / cron. Закрывает блок «нет backup» в текущем infra.md v0.1.

**I-3 [Эффект: med | Затраты: 0.5 дня infra-director | Риск: low | P1]**
Шаблон incident-runbook.md (из RFC-005 I-3, приоритет P1) — 1 страница, 5 сценариев (DB down / backend 500 / disk full / auth broken / data corruption) × 3-5 шагов. Артефакт: `docs/ops/incident-runbook.md` + раздел в регламенте v1.0. Пересекается с I-1.

---

### §3.6. Governance

**as-is:**
- Регламент v1.0 (86 строк), процесс комиссии через `docs/governance/requests/*.md`.
- Еженедельный аудит — понедельник, ручной (governance-auditor).
- Поведенческий аудит по триггеру — ручной.
- Нет линтера регламентов (противоречия / дубли) — всё глазами.
- Скил `adr-compliance-checker` — есть.

**Ручные операции-кандидаты:**
1. Поиск противоречий между CLAUDE.md и `departments/*.md` — глазами auditor'а, еженедельно.
2. Проверка что все ADR ссылки не битые — ручная.
3. Ведение CHANGELOG отдела — ручное.
4. Заявки в комиссию — шаблон есть, но исполнение без авто-валидации.

**Рекомендации:**

**G-1 [Эффект: high | Затраты: 1 день governance-auditor + ri-analyst | Риск: low | P0]**
`tools/regulations-lint.py` — скрипт, проверяет:
- Все ссылки `ADR-NNNN` / `CLAUDE.md §...` резолвятся.
- Версия регламента в frontmatter совпадает с последней записью в разделе «История версий».
- Нет дублирующихся правил между CLAUDE.md и `departments/*.md` (поиск одинаковых regex-паттернов требований).
Запуск в CI `docs-validation.yml` на push в `docs/agents/**` и `CLAUDE.md`. Артефакт: скрипт + CI job. Автоматизирует ~30% работы еженедельного аудита.

**G-2 [Эффект: med | Затраты: 0.25 дня governance-director | Риск: low | P1]**
Шаблон governance-request как JSON-schema + Python-валидатор. Заявки в `docs/governance/requests/*.md` с frontmatter, обязательные поля: `change / why / affects / owner / decision`. CI валидирует при PR. Артефакт: `docs/governance/_request-schema.json` + интеграция в `docs-validation.yml`. Убирает ошибки в заявках.

**G-3 [Эффект: med | Затраты: 0.5 дня governance-auditor | Риск: low | P1]**
Скрипт `tools/weekly-audit-scaffold.py` — перед еженедельным аудитом собирает: diff CLAUDE.md за неделю + список изменённых регламентов + список новых ADR + открытые governance-requests. Заготовка отчёта. Артефакт: скрипт + шаблон отчёта. Ускоряет аудит с 2-3 часов до 30-45 минут.

---

### §3.7. Docs / Tech-writer

**as-is:**
- `docs/` — 100+ markdown, много типов (ADR, RFC, reviews, audits, stories, wireframes, policies).
- `docs-validation.yml` — markdown-lint + битые ссылки (уже good).
- Diátaxis-теги в frontmatter — частично, не enforced (RFC-005 Doc-1).
- Нет автоматической генерации оглавления / индекса.
- Скилы: `doc-coauthoring`, `skill-creator`.

**Ручные операции-кандидаты:**
1. Поиск документа по теме — глазами, через `Grep`.
2. Поддержка README.md проекта — нет README (RFC-005 Doc-3).
3. Валидация frontmatter — сейчас markdown-lint проверяет только синтаксис.

**Рекомендации:**

**Doc-1 [Эффект: med | Затраты: 0.5 дня tech-writer | Риск: low | P1]**
`tools/docs-index.py` — генерирует `docs/INDEX.md` с иерархией по типам Diátaxis + ключевыми документами (ADR, RFC, регламенты). Запуск в CI при изменении `docs/**`. Артефакт: скрипт + сгенерированный INDEX.md (коммитится). Закрывает Doc-3 README-idea частично.

**Doc-2 [Эффект: med | Затраты: 0.25 дня tech-writer | Риск: low | P1]**
Frontmatter schema (JSON) + валидатор в CI на обязательные поля `title / date / author / diataxis_type` для новых документов в `docs/adr/`, `docs/research/rfc/`, `docs/reviews/`. Артефакт: `docs/_frontmatter-schema.json` + расширение `docs-validation.yml`. Automates RFC-005 Doc-1.

**Doc-3 [Эффект: low | Затраты: 0.5 дня tech-writer | Риск: low | P2]**
`lychee` link-checker (findings.md R-04) в `docs-validation.yml` — быстрый async-checker с кешем. Уже частично работает через markdown-lint — lychee быстрее и с кешем. Артефакт: CI job. Отложено — текущий чекер справляется.

---

### §3.8. Innovation

**as-is:**
- Регламент v1.0 (74 строки), активный с 2026-04-17.
- Источники: `erzrf.ru`, `gartner.com`, `a16z.com`, конкуренты (Procore, 1С:УСО).
- trend-scout активен, innovation-analyst dormant.
- Артефакты: `docs/innovation/findings.md`, `briefs/`, `competitor-watch.md`, `tech-radar.md`.
- Процесс аналогичен R&I (scout → analyst → director → digest).

**Ручные операции-кандидаты:**
1. Новые Innovation Brief — пишутся с нуля.
2. Competitor-watch — руками из статей.
3. Нет аналитики найденного vs принятого (R-1 из RFC-005 применим сюда).

**Рекомендации:**

**Inn-1 [Эффект: med | Затраты: 0.25 дня innovation-director | Риск: low | P1]**
Шаблон Innovation Brief как markdown-skeleton в `docs/innovation/briefs/_template.md` — структура: What / Market signal / Our position / Competitive gap / Proposal / Cost-benefit / Risk. Артефакт: шаблон. Унификация с RFC-формой R&I для облегчения перехода brief → RFC.

**Inn-2 [Эффект: low | Затраты: 0.5 дня ri-analyst (совм.) | Риск: low | P2]**
Общий линтер findings для R&I и Innovation — один скрипт `tools/lint-findings.py` проверяет: дубли URL за 30 дней, формат даты, статус (Discovered/Analysis/Pilot/Adopted/Rejected). Артефакт: скрипт + подключение к CI. Закрывает пропущенные дубли в обоих отделах.

**Inn-3 [Эффект: low | Затраты: 0.25 дня innovation-director | Риск: low | P3]**
Метрика «находок/месяц → briefs/месяц → adopt/quarter» — 3 цифры в конце Innovation Digest. Артефакт: обновление регламента. Параллельно R-1 из RFC-005.

---

### §3.9. Research & Integration (самоаудит)

**as-is:**
- Регламент v1.0 (95 строк), пилот 2026-04-15.
- 7 RFC за 3 дня, weekly digest — вручную.
- Скаут + Analyst в роли. Analyst dormant на момент написания (совмещение с Director разрешено — §«Совмещение ролей при малом потоке»).
- Нет outcome-метрик (RFC-005 R-1), именование RFC не стандартизовано (R-2), findings.md append-only без ротации (R-3).

**Ручные операции-кандидаты:**
1. Weekly digest — пишется руками из findings + RFC + текущих пилотов.
2. Формирование frontmatter RFC — копируется из предыдущего.
3. Коллизия номеров RFC (как в этом документе — rfc-007 занят, новый пришлось делать rfc-008) — нет автоинкремента.

**Рекомендации:**

**R-1 [Эффект: high | Затраты: 0.5 дня Координатора (настройка) | Риск: low | P0]**
Weekly digest как Claude Code Routine (RFC-001 adopt как пилот). Cron `0 7 * * MON` → промпт «читай findings.md + rfc/ за прошедшую неделю + `review-stats.py` (из Q-3) → собери digest по шаблону → отправь в Telegram Владельцу». Артефакт: настроенный Routine в веб-интерфейсе Claude Code + промпт-шаблон в `docs/research/digests/_digest-prompt.md`. Решает «weekly digest на памяти Координатора» (RFC-001 §2 пункт 1).

**R-2 [Эффект: med | Затраты: 0.25 дня ri-director | Риск: low | P1]**
Скрипт `tools/new-rfc.py <slug>` — автоинкремент номера (ищет max `rfc-NNN-*.md` в папке, +1), генерирует файл с frontmatter и шаблоном 10 секций. Артефакт: скрипт. Закрывает R-2 из RFC-005 + предотвращает коллизию номеров.

**R-3 [Эффект: low | Затраты: 0.25 дня ri-director раз в квартал | Риск: low | P2]**
Ротация findings.md по кварталам — скрипт `tools/rotate-findings.py` архивирует закрытые (Adopted/Rejected) строки в `findings-archive-YYYY-QN.md`. Артефакт: скрипт. Закрывает R-3 из RFC-005.

---

## §4. Сводный Top-10 через все департаменты

Отсортировано по приоритету (P0 → P1 → P2), в группе — по Impact/Effort.

| # | Код | Отдел | Рекомендация | Эффект | Затраты | P | Артефакт |
|---|---|---|---|---|---|---|---|
| 1 | RFC-004 Phase 0 | Backend+Quality | 5 hooks (H-1..H-5, старт пилота) | high | 2 дня | P0 | `.git/hooks/*` + `~/.claude/hooks/*.json` |
| 2 | B-1 | Backend | `make scaffold-crud` генератор CRUD | high | 1 день | P0 | `backend/tools/scaffold.py` + templates |
| 3 | Q-1 | Quality | SAST в CI (Bandit + pip-audit) | high | 1 день | P0 | CI job `security-scan` |
| 4 | B-2 | Backend | Layer-check скрипт на SQL вне репозиториев | high | 0.5 дня | P0 | `backend/tools/check_layers.py` + CI |
| 5 | G-1 | Governance | `regulations-lint.py` | high | 1 день | P0 | скрипт + CI |
| 6 | R-1 | R&I | Weekly digest как Routine | high | 0.5 дня | P0 | Claude Code Routine |
| 7 | F-1 | Frontend | `npm run scaffold:entity` генератор | high | 1 день | P0 | `frontend/tools/scaffold/` |
| 8 | I-1 | Infrastructure | Регламент v1.0 (после активации) | high | 2 дня | P0 | `departments/infrastructure.md` v1.0 |
| 9 | Doc-1 | Docs | `docs-index.py` автогенерация INDEX | med | 0.5 дня | P1 | скрипт + `docs/INDEX.md` |
| 10 | F-2 | Frontend | ESLint custom rules на 4 стандарта | med | 0.5 дня | P1 | `frontend/eslint-local-rules/*` |

Ниже Top-10 (P1-P3, второй волной): B-3 (backend-crud SKILL.md), D-1 (wireframe template), D-2 (wireframe linter), Q-2 (review template), Q-3 (review-stats), I-2 (backup script), I-3 (incident runbook), G-2 (request schema), G-3 (weekly-audit scaffold), Doc-2 (frontmatter validator), Doc-3 (lychee), Inn-1 (innovation brief template), Inn-2 (findings linter), R-2 (new-rfc script), R-3 (findings rotation), F-3 (bundle budget CI), Inn-3 (innovation metrics), D-3 (wireframe↔page link).

**Итого пунктов RFC-008:** 8 P0, 13 P1, 5 P2, 1 P3 (Inn-3). Суммарное время на всё — ~18-20 рабочих дней. Первая волна (Top-10 P0) — ~9 дней.

---

## §5. План внедрения Top-5 quick-wins

Quick-wins выбраны по правилу «максимальный эффект / минимальные часы / низкий риск». Первые 2 недели в параллель с M-OS-1.

### Шаг 1 (неделя 1, день 1-2): RFC-004 Phase 0 Hooks — 5 скриптов

- **Кто:** backend-dev (1.5 дня на скрипты) + ri-analyst (0.5 дня на тесты заминированного входа).
- **DoD:** 4 из 5 hooks ловят синтетические bad-inputs; governance-director выносит вердикт.
- **Откат:** удалить файлы `.git/hooks/*` и `~/.claude/hooks/*.json` — 1 минута.
- **Метрика:** за следующие 4 PR — 0 рецидивов литералов секретов (H-1), 0 `git add -A` инцидентов (H-2).
- **Статус:** уже одобрено Владельцем 2026-04-18, ждёт выделения исполнителя.

### Шаг 2 (неделя 1, день 3): Q-1 SAST в CI (Bandit + pip-audit)

- **Кто:** qa (бриф quality-director) + devops (CI-изменения). 1 день.
- **DoD:** CI jobs `bandit` и `pip-audit` зелёные на baseline, правило в `departments/quality.md` v1.2.
- **Откат:** убрать 2 job'а — 1 минута.
- **Метрика:** на каждом PR логи Bandit прикладываются; severity=high — block.

### Шаг 3 (неделя 1, день 4-5): B-1 `make scaffold-crud` генератор

- **Кто:** backend-dev (бриф backend-director). 1 день.
- **DoD:** `make scaffold-crud ENTITY=test` создаёт 6 файлов, после ручного заполнения они проходят ruff+pytest.
- **Откат:** удалить `backend/tools/scaffold.py` + templates — 30 секунд.
- **Метрика:** первая реальная новая сущность в M-OS-1 создаётся за ≤10 минут до MVP-уровня.

### Шаг 4 (неделя 2, день 1-2): B-2 layer-check + G-1 regulations-lint (в параллель)

- **Кто:** backend-dev для B-2 (0.5 дня) + ri-analyst для G-1 (1 день).
- **DoD:** B-2 — CI ловит `from sqlalchemy import select` вне репозиториев; G-1 — CI ловит устаревшую версию в frontmatter или битую ADR-ссылку.
- **Откат:** убрать CI jobs — 1 минута каждый.
- **Метрика:** B-2 — 0 рецидивов SQL вне репозиториев (RFC-007 причина №2); G-1 — еженедельный governance-audit сокращается с 2 часов до 45 минут.

### Шаг 5 (неделя 2, день 3): R-1 Weekly digest как Claude Code Routine

- **Кто:** Координатор (настройка в веб-интерфейсе Claude Code). 0.5 дня.
- **DoD:** первое автоматическое отправление digest в Telegram Владельцу в понедельник 07:00 следующей недели.
- **Откат:** удалить Routine в веб-интерфейсе — 1 минута.
- **Метрика:** 3 недели подряд digest приходит без участия Координатора (RFC-001 метрика успеха).

**Итого Top-5:** 6 дней работы за 2 недели. Распараллелено: шаги 1+2 (разные исполнители), 3 идёт после 1 (backend-dev освобождается), 4 в параллель (разные исполнители), 5 — Координатор только.

---

## §6. Риски внедрения

**Риск 1: перегруз backend-dev Волной 2 M-OS-1.** Шаги 1, 3, 4a (B-2) — все про backend-dev. Если Волна 2 стартует раньше недели 2 — backend-dev перегружен.

Митигация: шаг 1 (hooks) уже одобрен Владельцем отдельно, имеет выделенное время. Шаги 3 и 4a — по 0.5-1 дню, можно сдвинуть на неделю 3-4 без ущерба.

**Риск 2: Hooks Phase 0 не стартует — блокирует эффект B-2.** B-2 пересекается с H-5 (ruff pre-commit). Если Phase 0 откладывается, B-2 единственная защита.

Митигация: B-2 (CI layer-check) — работает независимо от pre-commit. Hooks — локальная защита для исполнителей, CI — обязательный gate.

**Риск 3: активация infra-director затягивается — блокирует I-1.** I-1 (регламент v1.0) требует infra-director. Сейчас dormant.

Митигация: идентичен RFC-005 риску 6.3. Координатор эскалирует активацию Владельцу отдельно; если откладывается — bootstrap регламента силами Координатора + devops.

**Риск 4: SAST false positives ломают dev-experience.** Bandit иногда триггерит на легитимные паттерны (например, `assert` в тестах — warning severity=low). Если в baseline много такого — dev начинает игнорировать.

Митигация: baseline-отчёт до включения fail, настройка `.bandit` со whitelisting легитимных паттернов. Threshold — только `severity=high` блокирует; med/low — warning.

**Риск 5: шаблоны устаревают быстрее, чем обновляются.** Scaffolds B-1, F-1 генерируют файлы по текущему паттерну Companies/Project. Когда эталон эволюционирует — шаблоны drift.

Митигация: test — `make scaffold-crud ENTITY=_testentity && pytest backend/tests/test__testentity.py` в CI раз в неделю (проверка что шаблон всё ещё даёт работающий код). Если упадёт — P1-задача на backend-director обновить шаблон.

**Риск 6: Claude Code Routine (R-1) зависит от облачной инфраструктуры Anthropic.** Если сервис недоступен — digest не отправится, Владелец не узнает.

Митигация: fallback — у Координатора в Memory правило «если понедельник 11:00 и digest не видел — отправить руками». Плюс — Routines в research preview, API может меняться (см. RFC-001 риски).

---

## §7. Связь с предыдущими RFC

- **RFC-001 (Claude Code Routines, draft)** — R-1 (weekly digest as Routine) — прямой пилот этого RFC. RFC-008 рекомендует его приёмку.
- **RFC-003 (mem0 память субагентов)** — не пересекается прямо, но долгосрочно: при внедрении mem0 шаблоны из RFC-008 (B-1, F-1) станут «памятью» скаффолдов.
- **RFC-004 (Orchestration Layer + Hooks Phase 0)** — Phase 0 Hooks = шаг 1 Top-5 RFC-008. Полный Orchestration Layer отложен до роста масштаба (см. RFC-004 v0.1).
- **RFC-005 (Cross-audit 8 департаментов)** — предшественник. RFC-008 использует многие находки RFC-005 как база для автоматизации: Q-4 SAST → Q-1 здесь; R-1 outcome-метрики → Q-3 здесь; Doc-1 Diátaxis → Doc-2 здесь.
- **RFC-007 (Code review acceleration, adopted)** — закрыто по Варианту C (Amendments A/B/C в backend.md v1.3 + quality.md v1.1 2026-04-18). RFC-008 развивает автоматизацию за пределы code review.
- **Коллизия номеров:** этот RFC я вынужденно сделал **rfc-008**, хотя Координатор просил rfc-007. Причина: номер rfc-007 занят узким RFC «Code review acceleration» (adopted 2026-04-18), на него ссылаются 17 файлов — переименование сломает. Координатор решает: (а) оставить номер 008 и этот документ; (б) переименовать rfc-007 в rfc-007a и переиспользовать 007. Моё предложение — оставить 008, меньше ломает ссылки.

---

## §8. Открытые вопросы для Координатора и Владельца

1. **Коллизия номеров RFC.** Оставляем 008 или переименовываем? Моё предложение — 008.

2. **Активация infra-director.** I-1 требует его. Активировать сейчас или Координатор пишет регламент v1.0 как bootstrap?

3. **Приоритет Top-5 при конфликте с M-OS-1 Волной 2.** Если backend-dev нужен в Волне 2 в неделю 1 — задерживаем шаги 3 и 4a?

4. **Scope B-1 и F-1 scaffolds.** Делать как bash/make или полноценный Plop.js (frontend) / Cookiecutter (backend)? Я заложил простые Makefile + Jinja2. Если хотите phiger — +1 день на каждый scaffold.

5. **Bandit severity threshold.** Block только high или high+medium? Индустрия — high+medium, но у нас baseline потенциально большой → много false positives. Моё предложение — начать с high, через 2 недели добавить medium если false positive rate ≤10%.

6. **SKILL.md-ориентация (B-3, и параллельно — `adr-compliance-checker`, `skill-creator` уже есть).** Делать ли SKILL.md явным **первым классом** автоматизации, или оставить эпизодически? Моё предложение — эпизодически, по запросу; phase 2 RFC-008 v2.0.

7. **Периодичность RFC-008-like audits.** Раз в квартал? По запросу? Моё предложение — раз в квартал, сокращённый формат (5-10 пунктов, 2 часа ri-analyst).

---

## §9. Честные ограничения RFC-008

1. **Не измерено, только оценено.** Все «high/med/low» эффекта — экспертные. Реальная экономия может отличаться в 1.5-2 раза. Митигация — первые 2 пилота (hooks + SAST) короткие, ошибка ограничена.

2. **Scaffold-риск.** Шаблоны B-1 и F-1 сэкономят часы только если они **поддерживаются** в актуальном состоянии. Иначе — устаревшие скелеты генерируют код, который сразу требует рефакторинга.

3. **Infra dormant.** §3.5 написан без участия infra-director — его знания добавят нюансов. При активации — возможна v1.1 RFC-008.

4. **Analyst dormant.** RFC пишу в режиме совмещения Director+Analyst (регламент R&I разрешает при <3 находок/неделю). Риск — я могу быть менее критичен к своим же формулировкам. Митигация — разбор RFC в комиссии governance + приёмка Координатором.

5. **Скилы учтены, но не полностью проанализированы.** Из 30 скилов в `~/.claude/skills/` я прошёл по названиям, но не по содержимому каждого. Возможно, некоторые из моих рекомендаций уже частично покрыты существующими скилами (`skill-creator`, `delegate-chain`). Митигация — при принятии P0-пунктов, прежде чем писать новый скил, проверить готовые.

6. **Не покрыт departments/legal.md.** Legal был в 8 департаментах RFC-005, но это advisory, не core_department (§ограничения scope RFC-008). При активации legal-трека — отдельный мини-RFC.

---

## §10. Статус и дальнейшие шаги

- **Статус RFC:** v1.0 (готов к приёмке).
- **Ожидает:** решения Координатора — принять Top-5 quick-wins / запросить v1.1 / отклонить отдельные пункты.
- **После принятия:**
  1. Координатор заводит задачи по Top-5 в `project_tasks_log.md`.
  2. Старт шагов 1-5 (2 недели, параллельно с M-OS-1).
  3. Через 30 дней — ретроспектива: что сделано, какие метрики попали в цель.
- **При частичном отклонении:** Координатор указывает, какие пункты исключить — обновляю до v1.1.

---

**Автор:** ri-director (в совмещённой роли с Analyst — Analyst dormant, регламент R&I §«Совмещение ролей при малом потоке»)
**Дата финализации:** 2026-04-18
**Бюджет времени:** ~3 часа (в рамках 4-часового бюджета регламента R&I).
