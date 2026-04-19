# Бриф backend-head: Phase 0 Hooks — реализация 5 хуков первого приоритета

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** L-уровень (декомпозиция + один backend-dev, 1.5 дня последовательно)
- **Паттерн:** Координатор-транспорт v1.6 (CLAUDE.md §«Pod-архитектура»)
- **Директор код не пишет.** Head разбивает на ~8 подзадач, отдаёт одному backend-dev, ведёт ревью, возвращает Директору на приёмку.
- **Источник скоупа:** `/root/coordinata56/docs/research/rfc/rfc-004-hooks-phase-0-plan.md` (ri-director, 2026-04-18; одобрен Владельцем msg 1411).
- **Критичность:** **механически закрыть 3 рецидива из 8 раундов ревью** (литералы паролей 3×, `git add -A` с чужими файлами 1×, `SendMessage` к dormant 7× за ночь 17 апреля). Это инфраструктура, а не app-код — **ни в коем случае не трогать `backend/app/`**.

---

## 0. Что это такое (простыми словами для Head'а)

Пять маленьких скриптов, которые срабатывают автоматически:

1. **H-1, H-2, H-5** — срабатывают на `git commit` (файлы в `.git/hooks/pre-commit`).
2. **H-3, H-4** — срабатывают на события Claude Code (`PreToolUse`, `PostToolUse`, `SubagentStart/Stop`; файлы в `/root/.claude/hooks/`).

Хуки делятся на два типа:
- **Block** (блокирует действие, выход ≠ 0): H-1 (секреты), H-5 (ruff/pytest на коммите).
- **Warn** (выводит предупреждение, не блокирует): H-3 (SendMessage dormant), H-4 (Opus без `ultrathink`).
- **Warn + confirm → block в автономе** (гибрид): H-2 (`git add -A`).

**Главное отличие от обычной backend-задачи:** здесь нет FastAPI, нет SQLAlchemy, нет миграций. Это bash + Python без зависимостей на проектный venv (хуки должны работать даже когда venv сломан). Писать просто, держать хирургично, без абстракций.

---

## 1. Цель

Закрыть механически (без участия reviewer'а) 3 класса рецидивирующих ошибок + заложить инфраструктуру для двух новых правил (SendMessage к dormant, `ultrathink` для Opus).

**Не-цели:**
- Не подменяем reviewer'а (смысловые дефекты — IDOR, fail-open RBAC — всё ещё его работа).
- Не вводим новые CI-jobs (CI уже существует, расширяется отдельно).
- Не пишем H-6…H-10 из §8 плана (отложены до результата пилота).

---

## 2. Источники (обязательно прочесть backend-dev перед стартом)

**Проектные правила:**
1. `/root/coordinata56/CLAUDE.md` — особенно разделы «Секреты и тесты», «Git», «SendMessage только для активных», «Extended Thinking для всех Opus-субагентов».
2. `/root/coordinata56/docs/agents/departments/backend.md` — чек-лист самопроверки (для документации хуков — какие пункты они закрывают).

**План пилота (главный источник истины):**
3. `/root/coordinata56/docs/research/rfc/rfc-004-hooks-phase-0-plan.md` — **полностью**. Особенно §3 (5 хуков), §4 (acceptance), §5 (deliverables), §7 (риски).

**Нормативные:**
4. `/root/coordinata56/docs/agents/regulations_addendum_v1.6.md` — паттерн «Координатор-транспорт» (для понимания, откуда берутся SendMessage и SubagentStart/Stop события).
5. `/root/coordinata56/docs/agents/inbox-usage.md` — политика inbox (почему H-3 важен).

**Внешние (backend-dev должен понимать API):**
6. Claude Code hooks документация: <https://docs.claude.com/en/docs/claude-code/hooks> — события `PreToolUse`, `PostToolUse`, `SubagentStart`, `SubagentStop`, формат JSON payload, формат конфигурации в `~/.claude/settings.json` или `~/.claude/hooks/*.json`. Актуальная версия (research preview) — читать свежую.
7. Git hooks: `git help hooks` — pre-commit, exit code ≠ 0 блокирует.

**Прецеденты:**
8. `/root/.claude/hooks/log_tool_use.py` — существующий Claude Code hook, понять формат входного JSON и структуру Python-скрипта.
9. `/root/coordinata56/backend/tools/lint_migrations.py` — прецедент stand-alone Python-утилиты без зависимостей от FastAPI.

---

## 3. Скоуп PR — 5 хуков + реестры + документация + install/rollback

Декомпозиция на подзадачи — в §5. Здесь — acceptance-критерии по каждому хуку.

### Блок 1. H-1 pre-commit — блокировка секретов (block)

**Что делает:** при `git commit` сканирует staged-файлы:
1. По имени: блок, если совпадает `.env*` (кроме `.env.example`), `*.key`, `*.pem`, `*credentials*`, `secrets.json`.
2. По содержимому diff: блок, если regex ловит `JWT_SECRET_KEY=`, `DATABASE_URL=postgresql://.*:.*@`, `password\s*=\s*["'][A-Za-z0-9]{8,}["']`.

**Блокирует:** exit 1 + сообщение с чёткой инструкцией как исправить (`git reset HEAD .env.production` или переименовать).

**Обход:** маркер `# hook-exception: H-1 <причина>` в той же строке (для тестов с заведомо dummy-значениями). Маркер логируется reviewer'у.

**Технология:** bash в `.git/hooks/pre-commit` + вспомогательный Python-скрипт `scripts/hooks/check_secrets.py` для regex. **Без зависимостей от venv.** Python — системный `/usr/bin/python3`.

**Acceptance:**
- На «мине 1» (`.env` + JWT секрет в diff) — блок с понятным сообщением.
- На файле `.env.example` с `JWT_SECRET_KEY=<placeholder>` — НЕ блокирует.
- На строке с `# hook-exception: H-1 test fixture` — НЕ блокирует.
- Оверхед ≤100 мс.

### Блок 2. H-2 pre-commit — защита от `git add -A` с чужими файлами (warn+confirm / block в автономе)

**Что делает:** парсит `git status --porcelain`; если staged >10 файлов И среди них есть «чужие» по эвристике:
- `mtime` файла за последние 30 минут и владелец процесса — не текущая сессия Claude (через `.claude/active-workers.json`), ИЛИ
- путь файла есть в `.claude/active-workers.json` у какого-то background-агента.

**Поведение:**
- Если TTY есть (интерактивный терминал) — печатает список подозрительных файлов и запрашивает `[y/N]`.
- Если TTY нет (автономный Claude) и нет ENV `COORDINATOR_ALLOW_ADD_ALL=1` — **блокирует** с требованием явного списка `git add path1 path2`.
- Если ENV выставлен — пропускает с логированием в `/root/.claude/projects/-root/memory/git_add_all_log.md`.

**Технология:** bash + `stat -c %Y` + чтение `.claude/active-workers.json`. Формат реестра (минимальный):
```json
{
  "workers": [
    {"id": "backend-dev-42", "pid": 12345, "started_at": "2026-04-18T10:00:00Z", "files_owned": ["backend/app/services/foo.py"]}
  ]
}
```

**Acceptance:**
- На 15 staged + 3 «чужих» в автономе без ENV — блок.
- На 15 staged без «чужих» в автономе — проходит.
- На 5 staged — проходит без проверки.
- На интерактиве — warning + prompt.
- Оверхед ≤200 мс.

### Блок 3. H-5 pre-commit — ruff + целевой pytest (block)

**Что делает:** фильтрует staged Python-файлы из `backend/`, запускает:
1. `ruff check <files>` — блок при exit ≠ 0.
2. `ruff format --check <files>` — блок при exit ≠ 0.
3. `pytest -q --timeout=30 <related_tests>` — mapping модуль→тест (`backend/app/services/X.py` → `backend/tests/services/test_X.py` + `backend/tests/api/test_Xs_api.py`). При отсутствии мэппинга — skip (не запускает весь pytest). Блок при провале.

**Технология:** bash + вызовы `ruff` и `pytest` из **проектного venv** (`backend/.venv/bin/ruff` если есть, иначе system). Отличие от H-1/H-2: этот хук имеет право зависеть от venv.

**Обход:** `git commit --no-verify` (стандартный git) + маркер `SKIP_HOOKS=H-5` в ENV для точечного обхода только H-5 при работающем H-1/H-2.

**Acceptance:**
- На ruff-нарушении (unused import) — блок с выводом ruff.
- На изменении `services/project.py` — запустились только тесты project.
- На изменении без Python-файлов — скип.
- Оверхед ≤1.5 сек (вместе с ruff).

### Блок 4. H-3 Claude Code hook PostToolUse SendMessage (warn)

**Что делает:** при `PostToolUse` событии с `tool_name == "SendMessage"` читает `to` параметр, сверяет с `/root/.claude/teams/default/active-agents.json`. Если получателя нет в списке активных — печатает warning в stderr (никого не блокирует).

**Технология:** Python в `/root/.claude/hooks/post-send-message.py`. Читает JSON payload из stdin (формат hook events), пишет warning в stderr.

**Реестр активных агентов** поддерживается двумя дополнительными хуками:
- `SubagentStart` — добавляет запись `{id, started_at}` в `active-agents.json`.
- `SubagentStop` — удаляет запись.
- Timeout-поле: записи старше 2 часов автоматически удаляются при чтении (самоочистка, митигация риска «агент упал без unregister»).

**Acceptance:**
- На SendMessage к реально active background-агенту — тишина.
- На SendMessage к dormant (отсутствует в реестре) — warning с текстом из плана §3.H-3.
- Warning не блокирует возврат SendMessage-tool.

### Блок 5. H-4 Claude Code hook PreToolUse Agent — напоминание о `ultrathink` (warn)

**Что делает:** при `PreToolUse` событии с `tool_name == "Agent"` читает `subagent_type` и `prompt`. Если `subagent_type` в справочнике Opus-агентов И в `prompt` нет `ultrathink` / `think harder` / `think hard` — warning в stderr.

**Справочник:** новый файл `/root/coordinata56/docs/agents/opus-agents.yaml`. По состоянию на 2026-04-18 — 11 Opus-агентов (список в CLAUDE.md §Extended Thinking):
```yaml
opus_agents:
  - backend-director
  - frontend-director
  - governance-director
  - governance-auditor
  - infra-director
  - innovation-analyst
  - innovation-director
  - quality-director
  - review-head
  - ri-analyst
  - ri-director
source: CLAUDE.md секция «Extended Thinking для всех Opus-субагентов» (2026-04-18 msg 1355)
```

**Технология:** Python в `/root/.claude/hooks/pre-agent-call.py`. PyYAML или простой парсинг (одна плоская структура — можно без PyYAML, через regex).

**Acceptance:**
- На Agent(backend-director, prompt без триггера) — warning.
- На Agent(backend-director, prompt начинается с `ultrathink`) — тишина.
- На Agent(backend-dev, prompt без триггера) — тишина (это Sonnet, не Opus).
- Не блокирует вызов Agent.

### Блок 6. Install-скрипт + rollback + документация

**Файлы:**
1. `/root/coordinata56/scripts/install-hooks.sh` — копирует хуки в места:
   - `.git/hooks/pre-commit` ← `scripts/hooks/pre-commit` (из репозитория). Создаёт backup существующего как `.git/hooks/pre-commit.bak` при первом запуске.
   - `/root/.claude/hooks/post-send-message.py` ← `scripts/hooks/post-send-message.py`.
   - `/root/.claude/hooks/pre-agent-call.py` ← `scripts/hooks/pre-agent-call.py`.
   - `/root/.claude/hooks/subagent-lifecycle.py` ← `scripts/hooks/subagent-lifecycle.py`.
   - Обновляет `~/.claude/settings.json` (или пишет `~/.claude/hooks/*.json` по актуальной схеме Claude Code) — регистрирует хуки в соответствующих событиях.
   - Создаёт пустые `/root/coordinata56/.claude/active-workers.json` и `/root/.claude/teams/default/active-agents.json` если нет.
   - **Идемпотентен:** повторный запуск не ломает уже установленное.
2. `/root/coordinata56/scripts/rollback-hooks.sh` — удаляет всё установленное, восстанавливает `.git/hooks/pre-commit.bak`. **Должен отработать ≤1 минуты** (включая нажатия пользователя).
3. `/root/coordinata56/docs/agents/hooks/README.md` — документация:
   - Что делает каждый из 5 хуков (одна секция на хук).
   - Как обойти (маркер, ENV, `--no-verify`).
   - Как установить (`bash scripts/install-hooks.sh`).
   - Как откатить (`bash scripts/rollback-hooks.sh`).
   - Troubleshooting: частые ошибки и решения.

**Acceptance:**
- `install-hooks.sh` на чистой системе ставит все 5 хуков, повторный запуск — idempotent.
- `rollback-hooks.sh` полностью удаляет установку, восстанавливает оригинал pre-commit, `git commit` работает как раньше.
- README понятен постороннему человеку (проверка: Head читает и без пояснений понимает, как установить и откатить).

---

## 4. FILES_ALLOWED / FILES_FORBIDDEN для backend-dev

### FILES_ALLOWED (новые + модифицируемые)

**Скрипты хуков (исходники в репозитории):**
- `/root/coordinata56/scripts/hooks/pre-commit` (bash, главный entrypoint)
- `/root/coordinata56/scripts/hooks/_common.sh` (общие bash-функции)
- `/root/coordinata56/scripts/hooks/check_secrets.py` (H-1 regex-сканер)
- `/root/coordinata56/scripts/hooks/check_add_all.py` (H-2 логика)
- `/root/coordinata56/scripts/hooks/run_lint_and_tests.sh` (H-5)
- `/root/coordinata56/scripts/hooks/post-send-message.py` (H-3)
- `/root/coordinata56/scripts/hooks/pre-agent-call.py` (H-4)
- `/root/coordinata56/scripts/hooks/subagent-lifecycle.py` (реестр active-agents)
- `/root/coordinata56/scripts/install-hooks.sh`
- `/root/coordinata56/scripts/rollback-hooks.sh`

**Конфиги и реестры:**
- `/root/coordinata56/.gitsecrets-patterns.txt` (паттерны regex, источник истины для H-1)
- `/root/coordinata56/docs/agents/opus-agents.yaml` (справочник для H-4)
- `/root/coordinata56/.claude/active-workers.json` (пустой init-файл для H-2)
- `/root/coordinata56/.claude/settings.local.json.example` (пример регистрации хуков Claude Code, если нужен)

**Тесты (юнит для Python-частей):**
- `/root/coordinata56/scripts/hooks/tests/test_check_secrets.py`
- `/root/coordinata56/scripts/hooks/tests/test_check_add_all.py`
- `/root/coordinata56/scripts/hooks/tests/test_post_send_message.py`
- `/root/coordinata56/scripts/hooks/tests/test_pre_agent_call.py`
- Стандартный pytest без fixtures проекта; тесты запускаются отдельно от backend-тестов.

**Документация:**
- `/root/coordinata56/docs/agents/hooks/README.md`

### FILES_FORBIDDEN (ни при каких обстоятельствах)

- **Весь `backend/app/`** — это не backend-app задача, app не меняем.
- **Весь `backend/tests/`** — тесты хуков живут отдельно в `scripts/hooks/tests/`.
- **`backend/alembic/`** — миграций нет.
- **`frontend/`** — фронт не трогаем.
- **`.git/hooks/*` напрямую в рабочей директории** — эти файлы пишутся install-скриптом при установке, **не коммитятся** (git сам не коммитит `.git/`).
- **`/root/.claude/hooks/*` напрямую** — те же файлы, копируются install-скриптом.
- **`~/.claude/settings.json`** — не переписывается целиком; install-скрипт аккуратно модифицирует или создаёт `settings.local.json`.
- **CLAUDE.md и departments/backend.md** — **не модифицируем в этом PR**. Зачистку правила «`git add -A` запрещён» (оно переходит в H-2) делает Координатор отдельно после adopt.
- **`docs/adr/*`** — ADR не заводим, это экспериментальный пилот, не архитектурное решение.

### COMMUNICATION_RULES

- backend-dev отчитывается Head'у по каждой завершённой подзадаче (не по всем 8 сразу в конце).
- Если Claude Code hooks API неочевиден (research preview) — backend-dev спрашивает Head, Head — Директора, Директор — Координатора. **Не домысливает API.**
- При любых сомнениях по скоупу — стоп, вопрос Head'у, не додумывать.
- Git — **не коммитить ничего** (коммит делает Координатор через review-head).

---

## 5. Декомпозиция на подзадачи для backend-dev (8 подзадач)

Последовательно, один backend-dev, 1.5 дня (~12 часов).

| # | Подзадача | Оценка | Зависит от | Deliverable |
|---|---|---|---|---|
| 1 | Прочитать все источники §2, составить короткий (≤300 слов) план реализации, согласовать с Head | 30 мин | — | Черновик плана в чате с Head |
| 2 | H-1 (скрипт + паттерны + тест `test_check_secrets.py`) | 2 часа | 1 | `check_secrets.py`, `.gitsecrets-patterns.txt`, 1 тест |
| 3 | H-5 (скрипт ruff + module→test mapping + тест на mapping) | 2 часа | 1 | `run_lint_and_tests.sh`, `check_add_all.py` stub |
| 4 | Объединяющий `pre-commit` bash + `_common.sh` + смоук-прогон на локальной «мине» | 1.5 часа | 2, 3 | `pre-commit`, `_common.sh`, ручной прогон ok |
| 5 | H-2 (`check_add_all.py` + формат `.claude/active-workers.json` + тест) | 2 часа | 4 | `check_add_all.py` полноценный, schema JSON |
| 6 | H-3 + реестр active-agents (`post-send-message.py` + `subagent-lifecycle.py` + тест) | 2.5 часа | 1 | 2 Python-скрипта, JSON-реестр |
| 7 | H-4 + справочник `opus-agents.yaml` (`pre-agent-call.py` + тест) | 1.5 часа | 1 | скрипт, YAML |
| 8 | `install-hooks.sh` + `rollback-hooks.sh` + `docs/agents/hooks/README.md` + финальный smoke на всех 5 хуках | 2 часа | 2-7 | install/rollback/README, ручной прогон ок |

**Итого:** 13.5 часов. При работе 8 ч/день — 1.7 дня. Есть небольшое перекрытие над плановыми 1.5 дня (12 ч), buffer обсудить с Head: либо урезать тесты Python-частей до smoke-уровня (и закрыть ручной проверкой ri-analyst), либо принять 1.7 дня и уведомить Координатора.

**Порядок фиксирован:** H-1 и H-5 первые, потому что они живут в одном `pre-commit` и нужна общая bash-обвязка. H-2 третья, потому что требует формата `active-workers.json`, который первыми двумя не нужен. H-3/H-4 — Claude Code hooks, независимы от git-хуков, могут идти в любом порядке. Install/docs — последние.

---

## 6. Definition of Done (для Head → Директор)

PR считается готовым к приёмке Директором, когда:

1. Все 5 хуков реализованы по acceptance-критериям §3.
2. `install-hooks.sh` запускается на чистой системе, ставит всё без ошибок, идемпотентен (повторный запуск = no-op).
3. `rollback-hooks.sh` полностью откатывает установку за ≤1 минуты; после отката `git commit` работает как до установки.
4. `docs/agents/hooks/README.md` покрывает все 5 хуков + install + rollback + troubleshooting.
5. `ruff check scripts/hooks/` чисто, `ruff format --check scripts/hooks/` чисто (Python-части).
6. Юнит-тесты Python-частей проходят: `pytest scripts/hooks/tests/ -q`.
7. Ручной smoke: backend-dev прогнал 5 «минированных» кейсов (§4.1 плана ri-director) локально, все 5 отработали как ожидается. Отчёт с выводами `git commit` и stderr'ом в комментариях PR.
8. FILES_ALLOWED строго соблюдён, ни одного файла из FILES_FORBIDDEN не тронуто (проверяется Head'ом через `git status` + `git diff --stat`).
9. Head провёл ревью уровня файлов и вернул Директору «accept / accept-with-changes / reject» — обычный маршрут отдела.

**После приёмки Директора** — бриф уходит Координатору, тот передаёт ri-analyst для приёмочного тестирования (§4.1-4.5 плана). Только после отчёта ri-analyst и вердикта governance-director — коммит в main через review-head.

---

## 7. Оценка реалистичности 1.5 дня

**Вердикт Директора: 1.5 дня (12 часов) — впритык, реалистичный диапазон 1.5–1.8 дня.**

**Почему впритык:**
- Claude Code hooks API — research preview, `log_tool_use.py` есть как прецедент, но для `SubagentStart/Stop` прецедента в репо нет. Возможна 1-2 часа на разведку API.
- H-2 требует формата `active-workers.json`, который поддерживается Координатором (это **не** задача backend-dev — Координатор будет писать в файл при запуске background-агентов). Нужно согласовать схему JSON с Координатором до реализации.
- Тесты Python-частей — не часть «основной функциональности», но без них ri-analyst будет ловить регрессии руками.

**Рекомендация Head'у:** идти по §5 последовательно, после подзадачи 4 (общий `pre-commit`) сделать чекпоинт у Директора — оценить остаток по фактическому прогрессу, при отставании урезать юнит-тесты Python-частей до смоука (всё равно ri-analyst будет прогонять acceptance).

**Если backend-dev перешагнёт 1.8 дня** — эскалация Директору, Директор — Координатору, возможное решение: выкинуть H-2 (самый сложный по эвристике «чужие файлы») в отдельный follow-up PR, adopt'нуть H-1/H-3/H-4/H-5 как MVP. Это позиция Head'а при переговорах с Директором.

---

## 8. Риски и митигации (3 ключевых)

### Риск 1: Claude Code hooks API изменится или окажется не таким, как описан в плане (research preview)

**Вероятность:** средняя. **Воздействие:** H-3, H-4, lifecycle — задержка 2-4 часа.

**Митигация:**
- Подзадача 1 (чтение источников) ОБЯЗАТЕЛЬНО включает 15 минут на чтение актуальной документации Claude Code hooks + беглую проверку `log_tool_use.py` на соответствие текущему API.
- Если API отличается от описанного в плане — backend-dev останавливается, пишет короткий (≤150 слов) отчёт Head'у о расхождении и предложение по адаптации. Head эскалирует Директору.
- Резервный вариант: если `SubagentStart/Stop` не работают как ожидается — реестр `active-agents.json` ведёт сам Координатор (как он уже ведёт `active-workers.json`). H-3 в пилоте работает на этом реестре без автохукового обновления.

### Риск 2: ложные срабатывания H-2 из-за несинхронного `active-workers.json`

**Вероятность:** средняя-высокая. **Воздействие:** раздражение Координатора, обход через `--no-verify`, потеря смысла хука.

**Митигация:**
- Формат `active-workers.json` с полем `started_at`; записи старше 4 часов (2×2ч из плана) автоматически игнорируются при чтении H-2 (самоочистка).
- Эвристика «чужие файлы» — только предупреждение в интерактиве, жёсткий блок — только в автономе И только при >10 staged файлов. На малых коммитах (≤10) H-2 не срабатывает вообще.
- Whitelist путей, на которых `-A` легитимен: `docs/agents/regulations*.md`, `docs/adr/*`, `docs/CONSTITUTION.md` (Координатор часто правит пачками регламенты). Список в конфиге `.claude/hook-h2-whitelist.txt`.
- ENV `COORDINATOR_ALLOW_ADD_ALL=1` для точечного обхода с логированием.

### Риск 3: H-5 тормозит коммиты из-за pytest на больших модулях

**Вероятность:** средняя. **Воздействие:** оверхед >2 сек, acceptance §4.3 плана не выполнено.

**Митигация:**
- Mapping модуль→тест максимально узкий: на изменение `services/project.py` запускаем **только** `test_project.py` (unit) + `test_projects_api.py` (integration), не весь `tests/services/`.
- Таймаут 30 сек на тест, 60 сек на всю проверку (жёсткий).
- Если mapping не найден — H-5 **пропускает pytest** (не запускает «весь pytest» как fallback — это съест минуту). Только `ruff check` + `ruff format --check`.
- В README явно написать: H-5 — это smoke-уровень, полный pytest всё равно в CI.
- Если acceptance §4.3 не выполняется в пилоте — H-5 редуцируется до ruff-only перед adopt, pytest переносится в CI. Это запасной вариант от ri-director, принимается без отдельного решения.

---

## 9. Чек-лист для Head перед отправкой Директору

- [ ] Все 8 подзадач §5 пройдены backend-dev, каждая отчитана.
- [ ] FILES_ALLOWED соблюдён, FILES_FORBIDDEN — ни одного касания (проверено `git status`).
- [ ] Ручной smoke на 5 «минах» §4.1 плана ri-director — отчёт с выводами.
- [ ] `ruff check scripts/hooks/` + `ruff format --check scripts/hooks/` чисто.
- [ ] `pytest scripts/hooks/tests/ -q` зелёный.
- [ ] `install-hooks.sh` проверен на чистой копии (ideempotent).
- [ ] `rollback-hooks.sh` проверен (≤1 минуты, полностью откатывает).
- [ ] README покрывает все 5 хуков, install, rollback, troubleshooting.
- [ ] Нет литералов секретов в скриптах хуков и тестах (рекурсивная самопроверка H-1 на собственный PR — ирония уместна).
- [ ] Нет `# type: ignore` / `# noqa` без обоснования.
- [ ] Ни одного коммита — Head возвращает Директору с рабочим деревом (staged или unstaged), Координатор коммитит через review-head.

---

## 10. Что Head отчитывает Директору (формат отчёта ≤400 слов)

1. **Что сделано:** по 5 хукам + install/rollback + docs (1 строка на каждый).
2. **Отклонения от скоупа:** чего не удалось сделать и почему (если было).
3. **Дефекты, пойманные ревью Head:** список замечаний уровня Pk и как решены.
4. **Smoke-результаты:** таблица «мина → хук → результат (block/warn/miss/false-positive)».
5. **Оверхед коммита:** `time git commit` до/после.
6. **Риски для приёмки ri-analyst:** что может сорвать §4 плана (ложноположительные, API hooks, что-то ещё).
7. **Tech-debt:** что отложено (например, сокращение тестов до смоука).

Этот отчёт Директор передаёт Координатору, Координатор инициирует стадию приёмки ri-analyst.

---

## 11. Команды-готовые-для-промпта (справочно для Head)

Когда Head будет формулировать Agent-вызов backend-dev, он должен включить:

```
FILES_ALLOWED: <список из §4>
FILES_FORBIDDEN: <список из §4>
COMMUNICATION_RULES: отчёт после каждой подзадачи; вопросы по API — стоп + вопрос, не додумывать; не коммитить.

Обязательно перед стартом:
1. Прочитай /root/coordinata56/CLAUDE.md
2. Прочитай /root/coordinata56/docs/agents/departments/backend.md
3. Прочитай /root/coordinata56/docs/research/rfc/rfc-004-hooks-phase-0-plan.md (целиком)
4. Прочитай /root/coordinata56/docs/pods/cottage-platform/tasks/hooks-phase-0-implementation.md (этот бриф)

Скоуп — 5 хуков + install + rollback + docs. Ни одного касания к backend/app, backend/tests, frontend/, ADR, CLAUDE.md.

Декомпозиция — 8 подзадач из §5. Идти строго по порядку.
```

Это не `ultrathink`-задача по качеству рассуждения (backend-dev — Sonnet), но при пункте 1 подзадачи backend-dev должен составить короткий план — проверка, что он понял скоуп.

---

## 12. Связь с процессом

- После приёмки Директором — Координатор передаёт в ri-analyst для приёмочного тестирования по §4 плана.
- После отчёта ri-analyst — вердикт governance-director.
- После adopt — коммит через review-head (стандартный маршрут).
- После коммита — Координатор обновляет CLAUDE.md: удаляет пункт «`git add -A` запрещён без просмотра» (переведено в H-2), добавляет ссылку на `docs/agents/hooks/README.md` в секцию Git.

Этот бриф — внутренний документ отдела бэкенда, не нормативный акт. После adopt артефакты (хуки, скрипты, README) становятся частью рабочей инфраструктуры.
