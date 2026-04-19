# Дев-бриф devops: Q-1 SAST CI integration (v2)

**Дата:** 2026-04-18
**От:** infra-director (после приёма брифа quality-director)
**Кому:** devops (через devops-head)
**Версия:** v2 — детализация YAML, baseline-diff, required check
**Заменяет:** `devops-brief-q1-sast-ci-2026-04-18.md` (входной бриф от quality-director; остаётся в истории как исходник)

## ultrathink

## Соответствие регламенту

Инфра-регламент `departments/infrastructure.md v1.0` §1 «CI/CD стандарты» — job `sast (Bandit/Semgrep)` значится в таблице «План расширения CI». Текущая задача — его реализация. Новый CI-job добавляется только через Governance-заявку, бриф → Директор → Head → Worker — маршрут соблюдён.

Подтверждение реализуемости: **да**. Расхождений с регламентом нет. Добавление `security-scan` после `lint`, только на PR, с blocking-поведением — согласуется с §1 (round-trip тоже только на PR, экономия минут) и не затрагивает deploy (§2) / backup (§3).

## Цель

Добавить в `.github/workflows/ci.yml` job `security-scan`:
- SAST через Bandit (по `backend/app + backend/tools`, зона baseline)
- CVE-аудит зависимостей через pip-audit
- Baseline-сравнение: fail только если новый HIGH-finding вне `docs/reviews/bandit-baseline-2026-04-18.md`
- Триггер: `pull_request` only (не `push` в `main` — чтобы главную ветку не блокировать до ратификации и не жечь минуты)

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/infrastructure.md` v1.0 §1
3. `/root/coordinata56/docs/agents/departments/quality.md` (v1.2 черновик, раздел «security scanning»)
4. `/root/coordinata56/.github/workflows/ci.yml` — место вставки (после job `lint`, до `test`)
5. `/root/coordinata56/docs/reviews/bandit-baseline-2026-04-18.md` — baseline (2 LOW findings, 0 HIGH, exclude_dirs `tests`, `alembic/versions`)
6. Исходный бриф quality-director: `devops-brief-q1-sast-ci-2026-04-18.md` (контекст и DoD)

## Скоуп работ

### 1. Зависимости dev

В `backend/pyproject.toml`, секция `[project.optional-dependencies].dev`, добавить:

```toml
"bandit[toml]>=1.7.9",
"pip-audit>=2.7.3",
```

**Важно:** в проекте **нет** `backend/requirements.txt` — зависимости живут в `pyproject.toml`. Установка в CI через `pip install -e "backend/[dev]"` (как уже делают jobs `lint-migrations`, `test`, `round-trip`).

### 2. Секция `[tool.bandit]` в `backend/pyproject.toml`

Скопировать из baseline §«Предлагаемая секция `[tool.bandit]`»:

```toml
[tool.bandit]
exclude_dirs = ["tests", "alembic/versions"]
skips = []
```

### 3. Новый job `security-scan`

Место вставки: `.github/workflows/ci.yml`, между job `lint` и `test` (после строки 18, до строки 36).

```yaml
  security-scan:
    # SAST (Bandit) + CVE-аудит (pip-audit).
    # Триггер: только pull_request — на push в main не перепроверяем (экономия минут, симметрично round-trip).
    # Блокирует merge: новый HIGH Bandit (вне baseline) ИЛИ любой CVE от pip-audit.
    # Low/medium Bandit — в job summary, не блокируют.
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install dependencies
        run: pip install -e "backend/[dev]"
      - name: Run Bandit SAST (JSON output)
        run: |
          bandit -r backend/app backend/tools \
            -c backend/pyproject.toml \
            -ll -f json -o /tmp/bandit.json
        continue-on-error: true
      - name: Diff Bandit against baseline
        # fail если появились НОВЫЕ HIGH-findings, которых нет в baseline.
        # Скрипт tools/diff-bandit-baseline.py — отдельная задача backend-dev (см. §4).
        run: |
          python tools/diff-bandit-baseline.py \
            /tmp/bandit.json \
            docs/reviews/bandit-baseline-2026-04-18.md
      - name: Run pip-audit (CVE scan)
        # --strict: ненулевой exit-code если найдены уязвимости.
        # Скопирует pyproject.toml зависимости; requirements.txt в проекте нет.
        run: |
          pip-audit --desc --strict \
            --vulnerability-service osv \
            -r backend/pyproject.toml
      - name: Bandit summary to $GITHUB_STEP_SUMMARY
        if: always()
        run: |
          echo "## Bandit findings" >> "$GITHUB_STEP_SUMMARY"
          python -c "import json,sys; d=json.load(open('/tmp/bandit.json')); \
            print(f\"- HIGH: {sum(1 for r in d['results'] if r['issue_severity']=='HIGH')}\"); \
            print(f\"- MEDIUM: {sum(1 for r in d['results'] if r['issue_severity']=='MEDIUM')}\"); \
            print(f\"- LOW: {sum(1 for r in d['results'] if r['issue_severity']=='LOW')}\")" \
            >> "$GITHUB_STEP_SUMMARY"
```

**Пояснения по расхождениям с исходным брифом Q-1:**
- Скоуп Bandit: `backend/app backend/tools` (как в задаче Координатора) — **совпадает с исходным брифом quality-director, `alembic/versions` исключён через `exclude_dirs`, не через путь**. Это важно для симметрии с baseline.
- Формат: `-ll -f json -o /tmp/bandit.json` — JSON нужен для diff-скрипта; флаг `-ll` (= `--severity-level medium`) экономит шум.
- `continue-on-error: true` на шаге bandit — чтобы fail-решение принимал diff-скрипт, не сам bandit (у него ненулевой exit при любых findings, даже LOW из baseline).
- `pip-audit -r backend/pyproject.toml` — pip-audit 2.7+ понимает pyproject. `requirements.txt` в проекте нет (проверено).
- `timeout-minutes: 5` — защита от зависаний на скачивании OSV-базы.

### 4. Зависимость: скрипт `tools/diff-bandit-baseline.py`

**Скрипт не существует.** Нужен **отдельной задачей для backend-dev** (маршрут: infra-director → Координатор → backend-director → backend-head → backend-dev). Без скрипта job `security-scan` не сможет отличить baseline-findings от новых.

Подзадача для backend-dev (приложение к данному брифу):

> **Задача B-SAST-DIFF:** написать `tools/diff-bandit-baseline.py`.
>
> - Stdlib only (никаких сторонних зависимостей — Python 3.12 хватит).
> - Вход: `argv[1]` = путь к bandit JSON; `argv[2]` = путь к markdown-baseline.
> - Парсит JSON: список `results[]` с полями `filename`, `line_number`, `test_id`, `issue_severity`.
> - Парсит markdown: таблицу §«Таблица findings» — извлекает пары `(файл:строка, правило)` со статусом `ACCEPT`.
> - Сравнивает: если есть HIGH-finding в JSON, которого нет в baseline (по ключу `(файл, строка, test_id)`) — `sys.exit(1)` с человекочитаемым отчётом в stderr.
> - Если HIGH = 0 вне baseline — печатает ok и `sys.exit(0)`.
> - LOW/MEDIUM игнорирует (их фильтрует уже CI через -ll, и всё равно они не блокируют).
> - ≤ 100 строк. Docstring на модуле — что и зачем. Тестов пока не требуется (покроет qa в отдельном раунде).
> - Размещение: `tools/diff-bandit-baseline.py` (не `backend/tools/` — это CI-утилита, не backend-код).

Без выполнения B-SAST-DIFF job `security-scan` зелёным не станет. **Порядок: сначала B-SAST-DIFF в main, потом Q-1 YAML.**

### 5. Required check

После зелёного тестового прогона — `security-scan` добавляется в GitHub branch protection для `main` наравне с `lint`, `lint-migrations`, `test`, `round-trip`. Настройка — не в YAML, а в UI репозитория (Settings → Branches → Branch protection rules → main → Require status checks). Владелец действия — **Координатор** (ему передать через отчёт).

## Ограничения

- НЕ трогать `test`, `lint`, `lint-migrations`, `round-trip`.
- НЕ коммитить — diff передать Координатору через отчёт devops-head.
- Verify-before-scale: прогнать job сначала в тестовом PR, убедиться что baseline-diff ловит искусственно добавленный HIGH (например, `eval(user_input)` в тестовом файле `backend/app/api/_test_sast.py`, удаляется после проверки).

## Критерии приёмки (DoD)

- [ ] YAML-блок добавлен, `actionlint` без ошибок.
- [ ] `bandit`, `pip-audit` в `[project.optional-dependencies].dev`.
- [ ] `[tool.bandit]` секция в `backend/pyproject.toml` совпадает с baseline.
- [ ] Зависимость от B-SAST-DIFF явно указана в отчёте devops (не идти в коммит до её готовности).
- [ ] Тестовый PR: зелёный на чистом diff, красный при искусственной HIGH-инъекции.
- [ ] Отчёт ≤ 200 слов: diff-файлов, команды локального прогона, шаги branch protection для Координатора.
