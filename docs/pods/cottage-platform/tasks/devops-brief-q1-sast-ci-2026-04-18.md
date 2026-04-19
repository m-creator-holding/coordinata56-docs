# Бриф devops (через infra-director): Q-1 SAST CI integration

**Дата:** 2026-04-18
**От:** quality-director (маршрут: infra-director → devops)
**Кому:** devops (после брифинга infra-director)
**Срок:** 1 рабочий день (параллельно с qa по baseline)
**Триггер:** RFC-008 Top-5 quick-wins, одобрен Владельцем 2026-04-18

## ultrathink

## Цель
Добавить в `.github/workflows/ci.yml` новый job `security-scan`, который на каждый PR запускает Bandit (SAST) и pip-audit (CVE), используя baseline-файлы от qa для исключения legacy-находок.

## Обязательно прочесть
1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/quality.md` (v1.2 черновик — раздел «security scanning»)
3. `/root/coordinata56/.github/workflows/ci.yml` — где добавлять
4. Baseline-файлы от qa (появятся параллельно):
   - `docs/reviews/bandit-baseline-2026-04-18.md`
   - `docs/reviews/pip-audit-baseline-2026-04-18.md`

## Скоуп работ

### 1. Зависимости dev
В `backend/pyproject.toml` секцию `[project.optional-dependencies].dev` добавить:
```toml
"bandit[toml]>=1.7.9",
"pip-audit>=2.7.3",
```

### 2. Новый job security-scan
В `.github/workflows/ci.yml` (после job `lint`, до `test`):
```yaml
  security-scan:
    # SAST (Bandit) + CVE-аудит зависимостей (pip-audit).
    # Fail: новые Bandit high-severity (не в baseline) ИЛИ pip-audit critical CVE.
    # Warning-only: low/medium — попадают в job summary, не блокируют merge.
    # Триггер: pull_request (push в main не перепроверяем — экономия минут).
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install dependencies
        run: pip install -e "backend/[dev]"
      - name: Run Bandit SAST
        run: |
          cd backend
          bandit -r app/ -c pyproject.toml \
            --severity-level high --confidence-level medium \
            -f txt -o /tmp/bandit-high.txt
      - name: Run pip-audit (CVE scan)
        run: |
          pip-audit --desc --strict \
            --vulnerability-service osv \
            -r backend/pyproject.toml
```

### 3. Критерии fail/pass
- **Bandit fail:** любой high-severity finding вне `[tool.bandit].skips` baseline.
- **pip-audit fail:** любой CVE с severity `critical` (флаг `--strict` заставляет pip-audit падать на найденных уязвимостях; low/medium потребуют отдельной обёртки — см. ниже).
- **Low/medium** — в `$GITHUB_STEP_SUMMARY` как warning, не блокируют merge. Если pip-audit `--strict` слишком строгий — обернуть в скрипт, который парсит JSON и фильтрует по severity (взять за шаблон уже существующий `backend/tools/lint_migrations.py`).

### 4. required check
`security-scan` должен стать **required check** для merge в main (вровень с `test`, `lint-migrations`, `round-trip`). Настройка — в GitHub branch protection (не в YAML). Предложить Координатору через отчёт.

## Ограничения
- НЕ трогать jobs `test`, `lint`, `round-trip` — не сломать зелёную ветку.
- НЕ коммитить — передать diff Координатору.
- Verify-before-scale: прогнать job локально через `act` или в тестовом PR перед включением required check.

## Критерии приёмки (DoD)
- [ ] YAML job добавлен, валиден (`actionlint` без ошибок)
- [ ] Зависимости `bandit`, `pip-audit` в `[dev]`
- [ ] Тестовый прогон зелёный (с baseline-исключениями)
- [ ] В отчёте — diff, команды для локальной проверки, список шагов для branch protection
- [ ] Отчёт ≤ 200 слов
