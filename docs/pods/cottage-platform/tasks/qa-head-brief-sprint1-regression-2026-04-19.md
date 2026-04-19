# Бриф qa-head: Полный регресс-прогон Sprint 1 (M-OS-1.1A)

**Дата:** 2026-04-19
**От:** quality-director
**Кому:** qa-head (делегирует qa-1 или qa-2 по свободному слоту)
**Приоритет:** P0 — gate Sprint 1 зависит от этого прогона
**Оценка:** 0.5 рабочего дня (прогон + классификация FAIL + отчёт)
**Триггер:** merge в main кода US-01 (company_id × 12 таблиц), US-02 (JWT + X-Company-ID middleware), US-03 (require_permission + RBAC matrix) и широкой починки consent-failures (backend-dev-2, 2026-04-19)
**Коммит:** НЕ коммитить — передать артефакты Координатору для sign-off

---

## ultrathink

## Цель

Подтвердить, что Sprint 1 код (US-01/02/03 + consent broad fix) не откатил regression-базовую линию 349 PASS и не ввёл регрессий в суще­ствующей функциональ­ности. Классифицировать остаточные FAIL (если есть) на: (а) **pre-existing** — известные до Sprint 1; (б) **новые регрессии** Sprint 1 — блокер gate; (в) **test-environment** — падения из-за сетевого/БД-окружения, не кода.

**Exit criterion:** либо 0 новых регрессий и ≥349 PASS, либо точный список P0-регрессий с BUG-id для возврата backend-head через Координатора.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md` (разделы «Процесс», «Секреты и тесты», «API»)
2. `/root/coordinata56/docs/agents/departments/quality.md` (v1.3, особенно правило 9 «QA не чинит код» и правило 11 spot-check)
3. `/root/coordinata56/docs/pods/cottage-platform/quality/test-strategy-m-os-1-1a-2026-04-18.md` §1 принципы, §4 Sprint 1 gate (пункты 1–7)
4. Дев-брифы, вошедшие в gate:
   - `docs/pods/cottage-platform/tasks/backend-dev-brief-us-01-company-id-2026-04-19.md`
   - `docs/pods/cottage-platform/tasks/backend-dev-brief-us-02-jwt-company-middleware-2026-04-19.md`
   - `docs/pods/cottage-platform/tasks/backend-dev-brief-us-03-rbac-completeness-2026-04-19.md`
   - `docs/pods/cottage-platform/tasks/backend-dev-brief-consent-broad-fix-2026-04-19.md`

## Скоуп работ

### 1. Baseline-снимок перед прогоном

- Зафиксировать текущий HEAD: `git rev-parse HEAD` → в отчёт, поле `commit_under_test`.
- Проверить, что миграции применены на тестовой БД: `cd backend && alembic current`.
- Очистить кеш: `pytest --cache-clear` перед первым прогоном.

### 2. Полный прогон

```bash
cd /root/coordinata56/backend
pytest -q --tb=short --maxfail=999 --junitxml=/tmp/sprint1-junit.xml 2>&1 | tee /tmp/sprint1-pytest.log
```

Флаг `--maxfail=999` намеренный: нужен **полный** список FAIL, не остановка на первом. `junitxml` — машиночитаемый артефакт для классификации.

### 3. Параллельно: измерение coverage (critical paths)

```bash
pytest --cov=backend/app --cov-branch --cov-report=term-missing --cov-report=html:/tmp/cov-sprint1 \
  backend/tests/ 2>&1 | tee /tmp/sprint1-coverage.log
```

Отдельно зафиксировать coverage на critical paths (test-strategy §3):
- `backend/app/services/company_scoped.py` (US-01 service layer) — цель ≥95% строк
- `backend/app/core/auth/jwt.py` или аналог (US-02 middleware) — ≥95% строк
- `backend/app/core/auth/permissions.py` / `require_permission` (US-03) — ≥95% строк

### 4. Классификация FAIL (главный артефакт)

На каждый FAIL — одна строка в таблице отчёта с колонками:

| test_id | класс | BUG-id (если новый) | обоснование |
|---|---|---|---|

Где **класс** — один из:
- `PRE_EXISTING` — тест падал на HEAD до merge US-01 (проверяется через `git stash && git checkout <pre-sprint1-sha> && pytest <test_id>`). Не блокирует gate, но упоминается в отчёте со ссылкой на issue.
- `REGRESSION_SPRINT1` — тест PASS до Sprint 1, FAIL после. **Блокер gate**. Завести BUG-id в `docs/pods/cottage-platform/quality/bug_log.md`, пометить xfail **только после** согласования с quality-director, вернуть задачу backend-head через Координатора.
- `TEST_ENV` — падение из-за сети, permissions, отсутствия postgres-контейнера, flaky timing. Не блокер gate при наличии воспроизведённого локального прогона, но отметить в отчёте с hint по исправлению окружения.
- `FLAKY` — падает непредсказуемо. Перепрогнать 3 раза; если падает хотя бы раз — `BUG-id` + `@pytest.mark.flaky` запрещён (quality.md §метрики), требует реального фикса, возврат backend-head.

Для классификации `PRE_EXISTING` vs `REGRESSION_SPRINT1` использовать sha прошлого зелёного прогона. Если sha неизвестен — Координатор подскажет (последний зелёный M-OS-0 commit).

### 5. Дополнительно — проверка RBAC-матрицы (US-03 specific)

Отдельно запустить:
```bash
pytest backend/tests/test_rbac_matrix.py -v
```

Зафиксировать:
- Количество параметризованных случаев (ожидаем 4 роли × N write-эндпоинтов × 2 сценария).
- Все 4 роли (owner, accountant, construction_manager, read_only) покрыты.
- Holding-owner bypass протестирован отдельным классом, не параметром.

### 6. Дополнительно — cross-company isolation (US-01 specific)

```bash
pytest backend/tests/test_cross_company_isolation.py -v backend/tests/test_company_scope.py -v
```

Убедиться: чужой id возвращает 404 (не 403 — не раскрывать существование).

### 7. Дополнительно — consent middleware (consent broad fix)

Проверить, что:
- Нет коллекционных `NameError` на `contracts.py` (см. бриф backend-dev-2 шаг 1).
- Фикстуры без `pd_consent_version` не ломают тесты (294 теста, которые падали на 403, должны теперь пройти).
- Намеренно-негативные тесты consent (test_pr2_rbac_integration.py строки 230-231, 278 и аналоги) — **остались красными** или остались под `xfail` в зависимости от дизайна. Если они «починились» без изменения — значит consent-gate случайно отключён, это P0.

## Ограничения

- **QA не чинит код** (quality.md §9). Нашли баг → BUG-id в `bug_log.md`, тест xfail **с комментарием-ссылкой на BUG-id**, возврат backend-head через Координатора.
- **Никаких литералов паролей в новых фикстурах** (если пришлось что-то дописывать) — `secrets.token_urlsafe(16)` (CLAUDE.md §Секреты).
- **Не коммитить**. Артефакты `/tmp/sprint1-*.log`, `/tmp/sprint1-junit.xml`, `/tmp/cov-sprint1/*` передать Координатору ссылкой на путь.
- `FILES_ALLOWED` для qa Worker:
  - `docs/pods/cottage-platform/quality/bug_log.md` (append-only)
  - `docs/pods/cottage-platform/quality/sprint1-regression-report-2026-04-19.md` (новый отчёт)
  - `backend/tests/**` — **только** добавление `xfail` с BUG-id (не фикс!)
- `FILES_FORBIDDEN`: `backend/app/**` (qa код приложения не чинит).

## Критерии приёмки (DoD)

- [ ] Baseline-sha зафиксирован в отчёте
- [ ] Полный прогон выполнен, junitxml прикреплён
- [ ] ≥349 PASS (ориентир: после +20–25 новых тестов US-01/02/03 ожидаем ~370–376 PASS)
- [ ] Все FAIL классифицированы по 4 категориям; для `REGRESSION_SPRINT1` заведены BUG-id
- [ ] Coverage critical paths измерен и приведён в отчёте (US-01 service, US-02 middleware, US-03 decorator)
- [ ] RBAC-матрица проверена на комплектность (4 роли × все write)
- [ ] Cross-company isolation возвращает 404 (не 403)
- [ ] Consent-gate не отключён случайно (намеренно-негативные тесты остались красными/xfail)
- [ ] Отчёт `docs/pods/cottage-platform/quality/sprint1-regression-report-2026-04-19.md` создан (НЕ коммитить, передать Координатору для sign-off)
- [ ] Сводка qa-head → quality-director ≤ 300 слов: PASS/FAIL счёт, число новых регрессий, coverage-срез, список BUG-id

## Формат отчёта qa-head (для передачи quality-director через Координатора)

```markdown
# Sprint 1 Regression Report — 2026-04-19

commit_under_test: <sha>
baseline_commit: <pre-sprint1-sha>

## Summary
- Total: <N> tests
- PASSED: <N>
- FAILED: <N> (breakdown ниже)
- SKIPPED / XFAIL: <N>
- Duration: <s>

## Classification of failures
| test_id | class | BUG-id | обоснование |
|---|---|---|---|
| ... | REGRESSION_SPRINT1 | BUG-042 | ... |

## Coverage critical paths
- company_scoped.py: <X>% lines, <Y>% branches
- jwt/middleware: <X>% lines, <Y>% branches
- permissions/require_permission: <X>% lines, <Y>% branches

## RBAC matrix check
- Параметризованные случаи: <N>
- Роли покрыты: owner/accountant/cm/read_only — all yes/no

## Consent gate sanity
- Коллекционных NameError: <0/>0>
- Намеренно-негативные тесты consent: <остались красными/отключились>

## Gate recommendation
- [ ] APPROVE — нет новых регрессий, все gates зелёные
- [ ] REQUEST-CHANGES — список BUG-id для возврата backend-head
- [ ] BLOCK — критическая регрессия (утечка между компаниями, bypass RBAC, отключение consent)
```

## Эскалация

- Найдена утечка cross-company (US-01 regression) — **немедленная** остановка gate, BUG-id с P0, Координатор возвращает backend-head.
- Обнаружено, что `require_permission` не блокирует роль на write — **немедленно** остановка gate, P0 (эскалация прав).
- Consent middleware отключён — P0, возврат backend-head.
- Любое из вышеперечисленного → quality-director эскалирует Координатору **в течение 30 минут** после обнаружения, не ждёт конца полного прогона.

---

*Бриф составил quality-director 2026-04-19. Передача qa-head — через Координатора (Pattern 5, Координатор-транспорт).*
