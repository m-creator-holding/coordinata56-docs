# Weekly Digest — Template v0.1

**Источник:** R-1 quick-win из RFC-008. Координатор заполняет еженедельно (пятница, 5 минут).

## 1. Обзор недели

- **Период:** YYYY-MM-DD — YYYY-MM-DD
- **Commits на main:** N (ссылки)
- **Активных агентов (уникальные):** N
- **Закрыто задач:** N из M (% от плана)
- **Фаза:** current / milestone

## 2. Основные результаты

- ✅ **Done:**
- 🟡 **В работе:**
- ⏸️ **Заблокировано:**

## 3. Решения Владельца за неделю

| Дата | Тема | Решение | Последствие |
|---|---|---|---|

## 4. Открытые вопросы Владельцу (на начало следующей недели)

| Приоритет | Кто задал | Вопрос | Варианты + рекомендация Координатора |
|---|---|---|---|

## 5. Риски и техдолг

| Риск | P | Митигация |
|---|---|---|

## 6. Context-audit Координатора

**Цель:** отслеживать context rot Координатора (по Fowler, Morphllm, Towards DS).

### Метрики сессии Координатора

- **Длина текущей сессии:** N часов / N commits
- **Agent spawns:** N (совокупно), параллельных в пике: M
- **Приблизительная длина контекста Координатора:** ~K токенов (оценка по returning-agent reports × среднее 300 токенов)
- **% использования окна 200К:** K% (граница 2× pricing)

### Индикаторы context rot

- [ ] Путаница в названиях агентов (backend-head vs backend-director)
- [ ] Повторение уже сделанной работы
- [ ] Игнорирование свежих решений Владельца
- [ ] Использование deprecated терминов / правил
- [ ] Пропуск правил из `memory/feedback_*.md`

**Если чек-листа ≥2 — пора рестарт сессии.**

### Действия по оптимизации

- **Этой недели:**
- **Спроектировано для следующей:**

## 7. Плановые инициативы R&I / Innovation

- Sensing-цикл R&I: N находок, N brief'ов
- Innovation digest: N рыночных движений
- Skills: N новых / N в работе

---

# Первая итерация — 2026-04-19

## 1. Обзор

- **Период:** 2026-04-18 21:42 (Мартин: «Запускай работу») — 2026-04-19 10:10
- **Commits на main:** 12
- **Активных агентов (уникальные spawns):** ~40
- **Задач закрыто:** 45 / 56 создано (80%)
- **Фаза:** M-OS-1.1A Sprint 1 (в активной разработке)

## 2. Основные результаты

- ✅ Gate 0 разблокирован (ADR-0013/0014 ratified)
- ✅ RFC-004 (Coordinator routing) pilot approved + Phase I-a Hooks живёт
- ✅ RFC-008 (Department automation) Top-5 quick-wins — 4 из 5 в коде
- ✅ US-02 (JWT+X-Company-ID middleware) — закрыт 7/7 тестов
- ✅ US-03 (RBAC 7×22 матрица) — закрыт 48/48 тестов
- ✅ Q-1 SAST в CI + pyjwt CVE HIGH закрыт
- ✅ G-1 regulations-lint + 4 ADR stubs (117 P1 closed)
- 🟡 US-01 (company_id migration) — in flight
- 🟡 FE-W1-4 Permissions Matrix UI — Task A in flight
- 🟡 Consent-middleware fix на 294 теста — план готов
- 🟡 Infra (Sentry cloud + WAL S3 + PITR) — скелет готов, ждёт регистраций Владельца

## 3. Решения Владельца за период

| Дата | Тема | Решение |
|---|---|---|
| 2026-04-18 msg 1469 | Hooks + Top-5 + design Q4-6 | 7 ответов, все «ок» |
| 2026-04-19 msg 1480 | Sprint 1 start + Sentry/WAL/PITR/matrix UI/rule_snapshots | 5 одобрений + старт |
| 2026-04-19 msg 1487 | Масштабирование агентов | До 15 параллельно |

## 4. Открытые вопросы Владельцу

| # | От кого | Вопрос | Рекомендация |
|---|---|---|---|
| 1 | infra-director | Sentry: облачный? | ✅ Решено — облачный до prod-gate |
| 2 | infra-director | WAL: S3-совместимое? | ✅ Решено — Яндекс Object Storage |
| 3 | infra-director | PITR сейчас или позже? | ✅ Решено — сейчас, на dev-данных |
| 4 | design-director | Matrix UI группировка? | ✅ Решено — 4 группы-папки |
| 5 | design-director | approved_by_rule_version где? | ✅ Решено — отдельная таблица |
| 6 | architect ADR-0015 | credentials_ref для Telegram dev? | mock:telegram vs dev-vault |
| 7 | architect ADR-0015 | kryptopro kind enum? | other vs dedicated |
| 8 | architect ADR-0015 | multi-tenancy credentials | поле vs таблица |
| 9 | devops | Яндекс Cloud регистрация | (ждёт действия Владельца) |
| 10 | devops | Sentry.io регистрация | (ждёт действия Владельца) |

## 5. Риски

| Риск | P | Митигация |
|---|---|---|
| 294 pre-existing test failures в main | P1 | backend-head план готов, ~2 часа |
| main жёлтый исторически | P2 | правило "main всегда 399/399" после fix |
| branch protection не настроен | P2 | Владелец в GitHub Settings после первого зелёного PR |
| context rot Координатора | P2 | рестарт сессии после Sprint 1 closure |

## 6. Context-audit Координатора

### Метрики

- **Длина сессии:** ~12 часов (с рестарта)
- **Agent spawns:** ~40 параллельных вызовов
- **Context Координатора (оценка):** ~40 × 300 токенов returns + ~20K instruction = **~32K токенов**
- **% от 200K window:** 16% — безопасно, до 2× pricing далеко
- **% от effective window (оценка 50K):** 64% — рисковая зона

### Индикаторы context rot (self-check)

- [ ] Путаница в названиях агентов — НЕ замечено
- [ ] Повторение работы — 1 случай (Task 26 создан вместо 25 для pyjwt-bump, маппинг фикнут)
- [x] Игнорирование свежих решений — пропустил правило "субагент не спавнит субагента" в первой волне → исправлено после возврата ri-director
- [ ] Deprecated термины — НЕ замечено
- [x] Пропуск правил memory/ — ультратхинк instruction я иногда забываю для Opus агентов (частично)

**Итог:** 2 индикатора. На границе. Рекомендация: **рестарт сессии после закрытия Sprint 1** (по решению Владельца 2026-04-19 msg 1497).

### Действия по оптимизации

- **Применяю с сегодня:**
  - Brief'ы к агентам ≤300 слов
  - Memory-first (читаю из файла, не из контекста)
  - Субагенты работают изолированно
  - ri-director готовит skills для lazy-loading (alembic / RBAC)
- **Спроектировано:**
  - CLAUDE.md аудит (governance-auditor + ri-director, волна сейчас)
  - Hand-off note перед рестартом сессии (memory-keeper)

## 7. Инициативы R&I / Innovation

- R&I Skills: `fz152-pd-checker` adopted; `alembic-safe-migration-checker` в работе; 2 ещё в очереди
- Innovation: Odoo + Voice AI briefs done; следующий sensing-цикл — понедельник
