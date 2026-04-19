# Clean Scenarios — False-Positive Guard (20 сценариев)

Назначение: по §4.2 плана и §2-Б брифа — прогнать 20 легитимных операций, убедиться что хуки **не** срабатывают (≤1 false-positive допустим).

## Принцип записи результата

- **Реакция «no warn, no block»** = exit code 0 И stderr **не содержит** substring `HOOK H-N` или `WARNING H-N`.
- False-positive = хук сработал там, где не должен. Записать в отчёт §3.3.

## Таблица сценариев

| № | Группа | Сценарий | Целевой хук (должен молчать) | Команда/действие | Ожидание |
|---|--------|----------|-------------------------------|-------------------|----------|
| 1 | Обычный коммит | Правка одного сервиса | H-1, H-2, H-5 | `echo '# nit' >> backend/app/services/project.py && git add backend/app/services/project.py && git commit -m "nit: comment"` | no warn, no block (если комментарий валиден ruff) |
| 2 | Обычный коммит | Правка теста без пароля | H-1, H-5 | Правка `backend/tests/test_projects.py` с добавлением assert | no warn, no block |
| 3 | Обычный коммит | Правка markdown в docs/ | H-1, H-2 | `echo '- new item' >> docs/agents/regulations/coordinator.md` | no warn, no block |
| 4 | Обычный коммит | Правка .gitignore | H-1, H-2 | добавить строку в `.gitignore` | no warn, no block |
| 5 | Password в тексте | Markdown про политику паролей | H-1 | Файл `docs/security/password-policy.md` со словом `password` в прозе | no warn (H-1 ловит только `password = "literal"`, не прозу) |
| 6 | Password в тексте | Колонка `password_hash` в модели | H-1 | `backend/app/models/user.py` содержит `password_hash: Mapped[str]` | no warn (это имя колонки, не литерал) |
| 7 | git add малый | 1 файл | H-2 | `git add backend/app/services/project.py` → commit | no warn |
| 8 | git add малый | 2 файла (service + test) | H-2 | `git add backend/app/services/x.py backend/tests/test_x.py` → commit | no warn |
| 9 | git add малый | 3 файла (CHANGELOG + 2 service) | H-2 | `git add CHANGELOG.md backend/app/services/x.py backend/app/services/y.py` → commit | no warn |
| 10 | git add -A легит | ≤10 файлов в пустом staging | H-2 | Создать 8 чистых docs-файлов, `git add -A`, commit | no warn (порог §3 H-2 = >10 файлов) |
| 11 | git add -A легит | 5 markdown-файлов docs | H-2 | `git add -A` на 5 docs/*.md | no warn |
| 12 | SendMessage активному | Active background-agent | H-3 | Запустить `Agent(run_in_background=true)`, пока работает — `SendMessage(to=<agent>)` | no warn (агент в active-agents.json) |
| 13 | SendMessage активному | Второй active agent | H-3 | Аналогично 12 со вторым агентом | no warn |
| 14 | Agent Opus с ultrathink | backend-director + ultrathink | H-4 | `Agent(subagent_type="backend-director", prompt="ultrathink — review X")` | no warn |
| 15 | Agent Opus с ultrathink | ri-analyst + think harder | H-4 | `Agent(subagent_type="ri-analyst", prompt="think harder about RFC-008")` | no warn |
| 16 | Agent Sonnet без thinking | ri-scout | H-4 | `Agent(subagent_type="ri-scout", prompt="scan GitHub trending")` | no warn (Sonnet вне справочника Opus) |
| 17 | Agent Sonnet без thinking | quality-worker | H-4 | `Agent(subagent_type="quality-worker", prompt="check test coverage")` | no warn |
| 18 | ruff-clean Python | Правка service прошла локально ruff | H-5 | Предварительно `ruff check <file>` → exit 0, затем commit | no warn, no block |
| 19 | ruff-clean Python | Правка тестового файла прошла ruff | H-5 | Правка `test_x.py` без unused import | no warn, no block |
| 20 | ruff-clean Python | Правка 3 файлов, все ruff-clean | H-5 | 3 service-файла с валидным diff | no warn, no block |

## Замечания по прогону

- **Сценарии 12-13** — требуют действительно активный background-agent. Для этого в worktree запустить `Agent(subagent_type="ri-scout", run_in_background=true, prompt="sleep 60 и вернуться")` — пока он активен, сделать SendMessage. Если не получится воспроизвести активное состояние — этот пункт отмечается как «not testable in this run», не считается false-positive.
- **Сценарии 14-17** — как в Mine 4, воспроизводятся в Claude-сессии (не bash). Можно сократить до 1 вызова на вариант, если время поджимает (§5.8 брифа — бинарный результат).
- **Сценарии 18-20** — используют файлы, для которых test-mapping существует (project, house, budget_plan). Это нужно, чтобы H-5 не запустил полный pytest 60 с.

## Лог false-positive (заполняется при прогоне)

| № | Хук сработал ложно? | Exit code | Substring в stderr | Комментарий |
|---|---------------------|-----------|---------------------|-------------|
| 1 | _(заполняется Г)_   |           |                     |             |
| ... | | | | |
| 20 | | | | |

**Ацептанс:** суммарно false-positive ≤ 1.
