# Dev-бриф: Hooks Phase 0 — реализация 5 хуков

- **От:** backend-head
- **Кому:** backend-dev (назначен: backend-dev — первый номер, без параллелизма)
- **Дата:** 2026-04-18
- **Источник:** head-бриф `/root/coordinata56/docs/pods/cottage-platform/tasks/hooks-phase-0-implementation.md`
- **Тип задачи:** последовательная, ~1.5–1.8 дня (12–14 ч), один исполнитель
- **Критичность:** инфраструктура, не app-код — `backend/app/` не трогается совсем

---

## СТОП: прочесть перед первой строкой кода

Обязательные источники (в этом порядке):

1. `/root/coordinata56/CLAUDE.md` — секции «Секреты и тесты», «Git», «SendMessage только для активных», «Extended Thinking»
2. `/root/coordinata56/docs/agents/departments/backend.md` — чек-лист самопроверки (п. 7, п. 8)
3. `/root/coordinata56/docs/research/rfc/rfc-004-hooks-phase-0-plan.md` — **целиком** (главный источник истины: §3 хуки, §4 acceptance, §5 deliverables, §7 риски)
4. `/root/coordinata56/docs/pods/cottage-platform/tasks/hooks-phase-0-implementation.md` — head-бриф (этот dev-бриф его уточняет, не заменяет)
5. Claude Code hooks docs: <https://docs.claude.com/en/docs/claude-code/hooks> — особенно формат JSON payload `PreToolUse`/`PostToolUse`/`SubagentStart`/`SubagentStop` и схема регистрации в `settings.json`
6. `git help hooks` — поведение pre-commit, exit code ≠ 0
7. `/root/.claude/hooks/log_tool_use.py` — **обязательно прочитать**: это рабочий прецедент Claude Code hook, понять формат stdin JSON и структуру Python-скрипта
8. `/root/coordinata56/backend/tools/lint_migrations.py` — прецедент stand-alone Python без FastAPI

---

## FILES_ALLOWED

Создавать и модифицировать разрешено **только** эти файлы:

**Скрипты хуков (исходники в репозитории):**
- `/root/coordinata56/scripts/hooks/pre-commit` (bash, главный entrypoint git hook)
- `/root/coordinata56/scripts/hooks/_common.sh` (общие bash-функции)
- `/root/coordinata56/scripts/hooks/check_secrets.py` (H-1 regex-сканер)
- `/root/coordinata56/scripts/hooks/check_add_all.py` (H-2 логика)
- `/root/coordinata56/scripts/hooks/run_lint_and_tests.sh` (H-5)
- `/root/coordinata56/scripts/hooks/post-send-message.py` (H-3)
- `/root/coordinata56/scripts/hooks/pre-agent-call.py` (H-4)
- `/root/coordinata56/scripts/hooks/subagent-lifecycle.py` (реестр active-agents)

**Install / rollback:**
- `/root/coordinata56/scripts/install-hooks.sh`
- `/root/coordinata56/scripts/rollback-hooks.sh`

**Конфиги и реестры:**
- `/root/coordinata56/.gitsecrets-patterns.txt` (regex паттерны для H-1)
- `/root/coordinata56/docs/agents/opus-agents.yaml` (справочник Opus-агентов для H-4)
- `/root/coordinata56/.claude/active-workers.json` (пустой init-файл для H-2)
- `/root/coordinata56/.claude/hook-h2-whitelist.txt` (whitelist путей для H-2)
- `/root/coordinata56/.claude/settings.local.json.example` (пример регистрации хуков)

**Тесты:**
- `/root/coordinata56/scripts/hooks/tests/test_check_secrets.py`
- `/root/coordinata56/scripts/hooks/tests/test_check_add_all.py`
- `/root/coordinata56/scripts/hooks/tests/test_post_send_message.py`
- `/root/coordinata56/scripts/hooks/tests/test_pre_agent_call.py`

**Документация:**
- `/root/coordinata56/docs/agents/hooks/README.md`

**Внимание по структуре:** директории `scripts/hooks/`, `scripts/hooks/tests/`, `docs/agents/hooks/` не существуют — создаёшь их при необходимости. Директория `scripts/` уже есть, но пуста.

---

## FILES_FORBIDDEN

Эти файлы и директории **запрещено трогать при любых обстоятельствах:**

- `backend/app/` — всё дерево целиком
- `backend/tests/` — тесты хуков живут в `scripts/hooks/tests/`, не здесь
- `backend/alembic/` — миграций нет
- `frontend/` — фронт не трогаем
- `.git/hooks/*` — эти файлы НЕ коммитятся (git не коммитит `.git/`), ставятся install-скриптом
- `/root/.claude/hooks/*` — ставятся install-скриптом, не напрямую
- `~/.claude/settings.json` — не переписывать целиком; install-скрипт создаёт `settings.local.json` или аккуратно дополняет секцию hooks
- `CLAUDE.md` — не модифицировать
- `docs/agents/departments/backend.md` — не модифицировать
- `docs/adr/*` — ADR не заводим

---

## COMMUNICATION_RULES

- Отчёт Head'у после каждой завершённой подзадачи (не в конце всех 8 сразу).
- Если Claude Code hooks API отличается от описанного → стоп, отчёт Head'у (≤150 слов: в чём расхождение, предложение по адаптации). Head эскалирует Директору.
- При любых сомнениях по скоупу → стоп, вопрос Head'у.
- Git — **не коммитить ничего**. Файлы сдаются в рабочем дереве.
- `git add` — только явным списком файлов, никогда `git add -A` или `git add .`.

---

## Вопросы перед стартом (ответить в первые 30 минут — до написания кода)

Это не риторика, это реальные неопределённости, которые могут заблокировать работу:

**Q1.** Формат JSON payload для `SubagentStart`/`SubagentStop` событий — документация Claude Code hooks (research preview) может описывать эти события иначе, чем `PreToolUse`/`PostToolUse`. Проверь: есть ли поля `subagent_type` и `subagent_id` в payload этих событий? Зафиксируй в плане (подзадача 1).

**Q2.** Схема регистрации хуков в `~/.claude/settings.json` — в `log_tool_use.py` прецеденте она уже зарегистрирована. Как сейчас выглядит раздел `hooks` в `/root/.claude/settings.json`? Нужно понять текущий формат, прежде чем install-скрипт будет его дополнять. Зафиксируй в плане.

**Q3.** Формат `active-workers.json` для H-2 поддерживается Координатором (не backend-dev). Нужно только определить схему и создать init-файл. Схема уже прописана в head-брифе §3.H-2 — подтвердить что понял и принял as-is.

Ответы на Q1–Q3 — в тексте плана из подзадачи 1. Если Q1 или Q2 блокируют — стоп, сообщи Head'у немедленно.

---

## Декомпозиция: 8 подзадач

Идти строго по порядку. Не начинать следующую подзадачу, пока не отчитался по текущей.

| # | Подзадача | Оценка | Зависит от | Deliverable для отчёта Head'у |
|---|---|---|---|---|
| 1 | Прочитать все источники (§ СТОП выше), ответить на Q1–Q3, составить план ≤300 слов | 30 мин | — | Текст плана в сообщении Head'у |
| 2 | H-1: `check_secrets.py` + `.gitsecrets-patterns.txt` + `test_check_secrets.py` | 2 ч | 1 | Файлы созданы, тест проходит |
| 3 | H-5: `run_lint_and_tests.sh` + module→test mapping + `check_add_all.py` (stub) | 2 ч | 1 | Bash-скрипт работает на примере staged Python-файла |
| 4 | Объединяющий `pre-commit` bash + `_common.sh` + smoke на локальной «мине» | 1.5 ч | 2, 3 | `pre-commit` объединяет H-1/H-5; ручной прогон показывает block |
| 5 | H-2: `check_add_all.py` (полноценный) + `active-workers.json` init + whitelist + тест | 2 ч | 4 | Скрипт + schema + тест |
| 6 | H-3 + lifecycle: `post-send-message.py` + `subagent-lifecycle.py` + `test_post_send_message.py` | 2.5 ч | 1 | Два Python-скрипта; тест warning на dormant |
| 7 | H-4: `pre-agent-call.py` + `opus-agents.yaml` + `test_pre_agent_call.py` | 1.5 ч | 1 | Скрипт + YAML + тест |
| 8 | `install-hooks.sh` + `rollback-hooks.sh` + `README.md` + финальный smoke на всех 5 хуках | 2 ч | 2–7 | Install/rollback/README + таблица smoke-результатов |

**Итого оценка:** 13.5 ч. Это 1.7 дня при 8 ч/день.

**Чекпоинт после подзадачи 4 (обязательный):** после завершения подзадачи 4 — стоп, отчёт Head'у. Head оценивает прогресс и принимает решение по буферу. Не продолжать до получения подтверждения от Head'а.

---

## Детальные требования по хукам

### H-1 (подзадачи 2, 4) — pre-commit, блокировка секретов

**Технология:** bash entrypoint в `scripts/hooks/pre-commit` вызывает `check_secrets.py` через системный `/usr/bin/python3`. Без зависимостей от проектного venv.

**`check_secrets.py` должен:**
- Принимать список staged-файлов через stdin или аргументы
- Блокировать по именам файлов: `.env*` (кроме `.env.example`), `*.key`, `*.pem`, `*credentials*`, `secrets.json`
- Блокировать по содержимому diff (regex): `JWT_SECRET_KEY=`, `DATABASE_URL=postgresql://.*:.*@`, `password\s*=\s*["'][A-Za-z0-9]{8,}["']`
- При блоке: exit 1 + чёткое сообщение + инструкция как исправить (`git reset HEAD <файл>`)
- Обход: строка с `# hook-exception: H-1 <причина>` НЕ блокируется; событие логируется в stderr для reviewer'а

**`.gitsecrets-patterns.txt`:** файл с regex-паттернами, один паттерн на строку. `check_secrets.py` читает из него паттерны — это источник истины, чтобы паттерны не были захардкожены в скрипте.

**`test_check_secrets.py`:** минимум 4 теста:
1. `.env` файл в staged → блок
2. `JWT_SECRET_KEY=abc123...` в diff → блок
3. `.env.example` с `JWT_SECRET_KEY=<placeholder>` → не блокирует
4. Строка с `# hook-exception: H-1 test fixture` → не блокирует

**Acceptance:** оверхед ≤100 мс.

### H-5 (подзадача 3, интеграция в 4) — pre-commit, ruff + pytest

**Технология:** bash `run_lint_and_tests.sh`, может зависеть от проектного venv (`backend/.venv/bin/ruff` если есть, иначе system).

**Логика:**
1. Из `git diff --cached --name-only` выбрать только Python-файлы в `backend/`
2. Если Python-файлов нет → скип (exit 0)
3. `ruff check <files>` → блок при exit ≠ 0
4. `ruff format --check <files>` → блок при exit ≠ 0
5. Module→test mapping: `backend/app/services/X.py` → `backend/tests/services/test_X.py` + `backend/tests/api/test_Xs_api.py`. Если mapping не найден → skip pytest (только ruff). Если файл теста существует → `pytest -q --timeout=30 <test_files>`

**Обход:** `SKIP_HOOKS=H-5` в ENV обходит только H-5, H-1/H-2 остаются активны.

**Acceptance:** оверхед ≤1.5 сек; при изменении `services/project.py` — только тесты project, не весь pytest.

### H-2 (подзадача 5) — pre-commit, защита от git add -A

**Технология:** `check_add_all.py`, вызывается из `pre-commit`, системный Python.

**Логика:**
1. `git status --porcelain` → количество staged файлов
2. Если staged ≤10 → exit 0, не проверяем
3. Если staged >10 → читаем `.claude/active-workers.json`
4. Для каждого staged-файла проверяем: есть ли он в `files_owned` какого-либо worker'а из реестра (игнорируя записи старше 4 часов по полю `started_at`)
5. Дополнительно проверяем whitelist: пути из `.claude/hook-h2-whitelist.txt` пропускаем
6. Если «чужих» файлов нет → exit 0
7. Если TTY есть → печатаем список подозрительных файлов + prompt `[y/N]`
8. Если TTY нет и нет ENV `COORDINATOR_ALLOW_ADD_ALL=1` → exit 1, требуем явный `git add path1 path2`
9. Если `COORDINATOR_ALLOW_ADD_ALL=1` → exit 0 + запись в `/root/.claude/projects/-root/memory/git_add_all_log.md`

**`active-workers.json` init-файл** (создать пустым):
```json
{"workers": []}
```

**`hook-h2-whitelist.txt`** — создать с содержимым:
```
docs/agents/regulations
docs/adr/
docs/CONSTITUTION.md
```

**`test_check_add_all.py`:** минимум 4 теста (мокируя `git status` и `active-workers.json`):
1. 15 staged + 3 «чужих» в автономе (нет TTY, нет ENV) → блок
2. 15 staged без «чужих» в автономе → проходит
3. 5 staged → проходит без проверки
4. «Чужой» файл в whitelist → проходит

### H-3 (подзадача 6) — Claude Code PostToolUse hook

**Технология:** `post-send-message.py` в `/root/coordinata56/scripts/hooks/` (копируется install-скриптом в `/root/.claude/hooks/`). Системный Python. Читает JSON из stdin, пишет warning в stderr.

**Логика:**
- Читать JSON payload из stdin (формат аналогичен `log_tool_use.py`)
- Проверить `tool_name == "SendMessage"` (или аналог из реального API — уточнить по Q1)
- Прочитать параметр `to` (получатель) из `tool_input`
- Прочитать `/root/.claude/teams/default/active-agents.json`
- Игнорировать записи старше 2 часов по полю `started_at`
- Если получатель отсутствует в реестре → `print("WARNING [H-3]: SendMessage к dormant агенту ...", file=sys.stderr)`
- Всегда exit 0 (предупреждение, не блокирует)

**`subagent-lifecycle.py`:** отдельный скрипт для событий `SubagentStart`/`SubagentStop`:
- `SubagentStart` → добавить `{id, started_at}` в `active-agents.json`
- `SubagentStop` → удалить запись
- При чтении → автоочистка записей старше 2 часов

**Реестр** `active-agents.json` (создать init-файлом):
```json
{"agents": []}
```

**`test_post_send_message.py`:** минимум 3 теста:
1. SendMessage к агенту из реестра (свежая запись) → тишина (нет warning в stderr)
2. SendMessage к агенту не в реестре → warning в stderr
3. SendMessage к агенту с записью старше 2 часов → warning (как dormant)

### H-4 (подзадача 7) — Claude Code PreToolUse hook

**Технология:** `pre-agent-call.py`. Системный Python. Читает JSON из stdin, пишет warning в stderr.

**Логика:**
- Читать JSON payload из stdin
- Проверить `tool_name == "Agent"` (или аналог — уточнить по Q1)
- Прочитать `subagent_type` и `prompt` из `tool_input`
- Загрузить список Opus-агентов из `/root/coordinata56/docs/agents/opus-agents.yaml`
- Если `subagent_type` в списке Opus-агентов И в `prompt` нет `ultrathink` / `think harder` / `think hard` → warning в stderr
- Всегда exit 0

**`opus-agents.yaml`** — создать с содержимым:
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

**Парсинг YAML:** можно без PyYAML через простой regex или построчно (структура плоская). Не добавлять зависимости.

**`test_pre_agent_call.py`:** минимум 3 теста:
1. Agent(backend-director, prompt без ultrathink) → warning
2. Agent(backend-director, prompt начинается с `ultrathink`) → тишина
3. Agent(backend-dev, prompt без ultrathink) → тишина (Sonnet, не Opus)

### Install / rollback / README (подзадача 8)

**`install-hooks.sh`** должен:
1. Создать backup `.git/hooks/pre-commit` как `.git/hooks/pre-commit.bak` (только если backup не существует)
2. Скопировать `scripts/hooks/pre-commit` в `.git/hooks/pre-commit` и выдать `chmod +x`
3. Скопировать Claude Code хуки в `/root/.claude/hooks/`:
   - `scripts/hooks/post-send-message.py` → `/root/.claude/hooks/post-send-message.py`
   - `scripts/hooks/pre-agent-call.py` → `/root/.claude/hooks/pre-agent-call.py`
   - `scripts/hooks/subagent-lifecycle.py` → `/root/.claude/hooks/subagent-lifecycle.py`
4. Создать init-файлы если не существуют: `/root/coordinata56/.claude/active-workers.json`, `/root/.claude/teams/default/active-agents.json`
5. Зарегистрировать хуки в `~/.claude/settings.json`: добавить секцию `hooks`, не перезаписывая весь файл. Если `hooks` уже есть — дополнить. Использовать `python3 -c` с json-merge или отдельный helper-скрипт.
6. **Идемпотентен:** повторный запуск — no-op, не ломает установленное.

**`rollback-hooks.sh`** должен:
1. Удалить `.git/hooks/pre-commit`
2. Восстановить `.git/hooks/pre-commit.bak` как `.git/hooks/pre-commit` (если backup существует)
3. Удалить скопированные файлы из `/root/.claude/hooks/` (только те, что были установлены этим install)
4. Удалить секцию хуков из `~/.claude/settings.json` (или закомментировать — зависит от реализации merge)
5. Отработать ≤1 минуты без интерактивного ввода

**`README.md`** структура:
- Что делает каждый из 5 хуков (H-1 через H-5): по одной секции на хук
- Как обойти: маркер `# hook-exception`, `SKIP_HOOKS=H-5`, `--no-verify`, `COORDINATOR_ALLOW_ADD_ALL=1`
- Как установить (`bash scripts/install-hooks.sh`)
- Как откатить (`bash scripts/rollback-hooks.sh`)
- Troubleshooting: минимум 3 типичные ошибки с решениями

---

## Definition of Done

PR готов к сдаче Head'у, когда:

1. Все 5 хуков реализованы по acceptance выше.
2. `install-hooks.sh` работает на чистой системе и идемпотентен (повторный запуск — no-op).
3. `rollback-hooks.sh` полностью откатывает установку за ≤1 минуты, после отката `git commit` работает как до установки.
4. `docs/agents/hooks/README.md` покрывает все 5 хуков + install + rollback + troubleshooting.
5. `ruff check scripts/hooks/` чисто, `ruff format --check scripts/hooks/` чисто.
6. `pytest scripts/hooks/tests/ -q` зелёный.
7. Ручной smoke: 5 «мин» прогнаны, все отработали как ожидается. Таблица результатов в отчёте Head'у.
8. FILES_ALLOWED строго соблюдён, ни одного файла из FILES_FORBIDDEN не тронуто.
9. Нет литералов секретов в скриптах и тестах.
10. Нет `# type: ignore` / `# noqa` без обоснования.
11. Не сделано ни одного коммита.

---

## Риски и митигации

### Риск 1: Claude Code hooks API research preview расходится с описанием

**Вероятность:** средняя. **Воздействие:** H-3, H-4, lifecycle — задержка 2–4 ч.

**Как вести себя dev:** в подзадаче 1 потратить 15 мин на чтение актуальной документации + сверить с `log_tool_use.py`. Если API отличается — стоп, отчёт Head'у ≤150 слов с описанием расхождения и предложением адаптации.

**Запасной вариант (принимает Head, не dev):** если `SubagentStart/Stop` не работают как ожидается — реестр `active-agents.json` ведёт Координатор вручную. H-3 работает на этом реестре без автохукового обновления.

### Риск 2: H-5 оверхед >1.5 сек из-за pytest

**Вероятность:** средняя. **Воздействие:** acceptance §4.3 плана не выполнено.

**Митигация в коде:** mapping строго узкий, один модуль → максимум 2 теста. Таймаут pytest `--timeout=30`. Если mapping не найден → только ruff, без pytest. Если оверхед >1.5 сек при прогоне — сообщи Head'у: будет принято решение редуцировать H-5 до ruff-only.

### Риск 3: H-2 ложные срабатывания из-за несинхронного active-workers.json

**Вероятность:** средняя-высокая в начале. **Воздействие:** раздражение, обход через --no-verify.

**Митигация в коде:** записи старше 4 часов игнорируются. ≤10 staged файлов → H-2 не активируется. Whitelist путей. В автономе блок только при >10 staged + есть «чужие». Dev не изменяет эти пороги самостоятельно — любые изменения пороговых значений через Head.

---

## Acceptance criteria (проверяет ri-analyst после Head-ревью)

| Мина | Хук | Ожидание |
|---|---|---|
| `git commit` с `.env` в staged | H-1 | block, чёткое сообщение |
| `git commit` с `JWT_SECRET_KEY=realvalue` в diff | H-1 | block |
| `.env.example` с `JWT_SECRET_KEY=<placeholder>` | H-1 | pass |
| 15 staged + 3 чужих, TTY нет, ENV нет | H-2 | block |
| 15 staged, чужих нет | H-2 | pass |
| `git commit` с ruff-нарушением в staged Python | H-5 | block, вывод ruff |
| `git commit` без Python-файлов | H-5 | skip |
| SendMessage к dormant агенту | H-3 | warning в stderr, не блокирует |
| SendMessage к active агенту | H-3 | тишина |
| Agent(backend-director, prompt без ultrathink) | H-4 | warning в stderr, не блокирует |
| Agent(backend-director, prompt с ultrathink) | H-4 | тишина |

---

## Чекпоинты с Head'ом

- **После подзадачи 1:** ждать подтверждения от Head. Dev присылает план ≤300 слов + ответы на Q1–Q3. Если Q1 или Q2 содержат расхождение с API — стоп, Head эскалирует.
- **После подзадачи 4 (обязательный stop):** Head оценивает прогресс и остаток. При отставании — решение по буферу (урезать юнит-тесты до smoke или принять 1.7 дня). Dev не продолжает без ответа Head'а.
- **После подзадачи 8:** Dev присылает отчёт (таблица smoke + `time git commit` до/после + список файлов `git status`). Head делает ревью FILES_ALLOWED + рецензию скриптов.

**Если к концу подзадачи 7 общее время перешагнуло 1.8 дня:** Dev немедленно сообщает Head'у. Head принимает решение: выкинуть H-2 в follow-up PR, adopt H-1/H-3/H-4/H-5 как MVP Phase 0. H-2 в этом случае НЕ включается в текущий PR.

---

## Отчёт dev'а Head'у после каждой подзадачи (формат)

```
Подзадача N завершена.
Файлы: <список созданных/изменённых>
Тест: <прошёл/не прошёл, что запускал>
Время: <фактическое>
Вопросы к Head: <если есть, иначе «нет»>
```
