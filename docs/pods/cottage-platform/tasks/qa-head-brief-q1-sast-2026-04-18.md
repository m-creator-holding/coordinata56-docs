# Бриф qa-head: Q-1 SAST baseline (quick-win RFC-008)

**Дата:** 2026-04-18
**От:** quality-director
**Кому:** qa-head (делегирует qa-1 или qa-2)
**Срок:** 1 рабочий день
**Триггер:** RFC-008 Top-5 quick-wins, одобрен Владельцем 2026-04-18

## ultrathink

## Цель
Зафиксировать текущее состояние безопасности Python-кода и зависимостей, чтобы новый CI-gate `security-scan` не падал от legacy-находок. Baseline — «точка отсчёта», всё новое после неё будет блокироваться.

## Обязательно прочесть
1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/quality.md` (черновик v1.2 от quality-director — раздел «security scanning»)
3. `/root/coordinata56/backend/pyproject.toml` (куда добавить `[tool.bandit]`)

## Скоуп работ

### 1. Bandit на текущем коде
- Установить `bandit[toml]>=1.7.9` локально (не в `pyproject.toml` — это сделает devops в зависимостях `dev`).
- Прогнать: `bandit -r backend/app/ -f json -o /tmp/bandit-report.json`.
- Отдельно прогнать текстовый отчёт для документа.

### 2. pip-audit на зависимостях
- Установить `pip-audit>=2.7.3`.
- Прогнать: `pip-audit --desc -r backend/pyproject.toml` (или по lock-файлу, если есть).
- Зафиксировать все CVE с severity/описанием.

### 3. Baseline-документы
Создать два файла (НЕ коммитить — это сделает Координатор):
- `docs/reviews/bandit-baseline-2026-04-18.md` — таблица: файл:строка, severity, confidence, правило (B101/B105/...), краткое «почему оставлено в baseline» (legacy / ложноположительное / принято). High-severity findings, которые можно быстро починить — помечать как `FIX` (отдельной задачей, не в этом батче).
- `docs/reviews/pip-audit-baseline-2026-04-18.md` — таблица: пакет, версия, CVE-id, severity, статус (`ACCEPT` / `UPDATE` / `BLOCKED-UPSTREAM`).

### 4. Конфиг Bandit
Предложить секцию `[tool.bandit]` для `backend/pyproject.toml`:
```toml
[tool.bandit]
exclude_dirs = ["tests", "alembic/versions"]
skips = []  # заполнить по итогам baseline (если какое-то правило повсеместно шумит — обосновать)
```
Игнорировать тесты и миграции — это стандарт; security-аудит миграций делает ревьюер вручную.

### 5. Документация исключений
Для каждого `# nosec` в коде (если добавляете) — обязателен комментарий-обоснование. Правило из CLAUDE.md «никаких `# noqa` без комментария» распространяется и на `# nosec`.

## Ограничения
- НЕ менять код приложения — только читать. Если нашёлся реальный P0 (хардкод секрета, eval от user input) — в `bug_log.md`, не фиксить.
- НЕ править CI — это devops.
- НЕ коммитить — передать артефакты Координатору.

## Критерии приёмки (DoD)
- [ ] Оба baseline-файла созданы, заполнены, читаемы
- [ ] High-severity bandit-findings перечислены поимённо с решением (accept / fix-later)
- [ ] Critical/High CVE в pip-audit перечислены поимённо
- [ ] Предложен `[tool.bandit]` для pyproject.toml
- [ ] Отчёт quality-director ≤ 200 слов: сколько findings, сколько high, сколько в `FIX`, сколько в `ACCEPT`
