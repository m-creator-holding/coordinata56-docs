---
name: ADR 0023 ratification (Rule Snapshots Pattern)
description: Backup-mode ratification ADR-0023 — governance-director недоступен через Agent tool. Универсальный паттерн rule_snapshots + FK для Payment/Contract, Sprint 3 M-OS-1.1B.
type: governance-request
date: 2026-04-19
applicant: Координатор (backup-mode)
decision: approved
reviewer: governance-auditor (backup-approver, резервный режим)
---

# Заявка: ADR 0023 ratification (Rule Snapshots Pattern)

## Мотивация

ADR-0023 «Rule Snapshots Pattern» решает три проблемы M-OS-1.1B, прямо вытекающие из решения Владельца 2026-04-19 msg 1480 Q5:

1. **Ретроактивность.** Заявка на согласовании, созданная под старым правилом, должна дорабатываться по старому правилу (решение Владельца Q4 msg 1480).
2. **Аудируемость.** Через год возможность восстановить «по какому правилу одобрен Payment #1247».
3. **Обратная совместимость.** Паттерн повторяется на Contract / Invoice / Action-workflows — нужен универсальный механизм.

Владелец Q5 msg 1480 явно выбрал **Вариант A** (универсальная таблица `rule_snapshots` + FK от сущностей), отклонив Вариант C (колонка JSON в самой Payment/Contract).

**Backup-mode.** `governance-director` недоступен через Agent tool (force-majeure паттерн, повторно воспроизведён 2026-04-19). Вердикт выносит `governance-auditor` по прецеденту ADR-0014 / ADR-0015 ratification. Владелец одобрил Координатору использование backup-mode.

## Скоуп правок

1. `docs/adr/0023-rule-snapshots-pattern.md` — frontmatter `status: proposed → accepted` + дата утверждения 2026-04-19 + footer ratification (документ написан без YAML-frontmatter, ratification добавляется в header + footer).
2. `docs/governance/CHANGELOG.md` — новая запись о ratification.

## Проверка каноничности (CODE_OF_LAWS Книга II — ADR process)

| Критерий | Статус | Комментарий |
|----------|--------|-------------|
| Решение Владельца зафиксировано | ДА | Q4 + Q5 msg 1480 2026-04-19 прямо выбирают Вариант A и ретроактивность |
| Рассмотренные альтернативы | ДА | 3 варианта (A принят, B per-module — отклонён по DRY, C JSON-колонка — отклонён Владельцем по scalability) |
| Схема БД определена | ДА | Таблица `rule_snapshots` с 8 полями + unique constraint + 2 индекса; FK добавляются в Payment и Contract |
| Правила создания/привязки snapshot | ДА | Snapshot создаётся при сохранении правила через Admin UI; привязывается при `status='pending_approval'`; чтение — из snapshot, не из `company_settings` |
| Миграция существующих данных | ДА | Одноразовый backfill-script создаёт snapshot v1 из текущих `company_settings` для висящих Payment |
| DoD (проверяемые критерии) | ДА | 7 пунктов, включая `test_retroactive_rule_change` и `test_snapshot_immutable` |

## Согласованность с каноном

- **CLAUDE.md раздел «Данные и БД»** — enum не используется (не требуется совместимость); миграция идёт по ADR-0013 (lint-migrations, round-trip в CI явно указаны в DoD пункт 1).
- **CLAUDE.md раздел «API»** — косвенно поддерживает (аудит в той же транзакции со сменой статуса, ADR-0007).
- **ADR 0007 (AuditLog)** — каждая привязка snapshot к Payment фиксируется в аудит-записи со ссылкой на `snapshot.id`. Согласовано.
- **ADR 0011 (Foundation: multi-company, RBAC, crypto audit)** — `company_id` FK на `companies(id)`, `approved_by_user_id` остаётся как есть; `approval_rule_snapshot_id` добавляется. Без изменений существующей семантики.
- **ADR 0013 (Migrations Evolution Contract)** — DDL для `rule_snapshots` разрешён без ограничений; FK добавляются в существующие таблицы nullable (expand-фаза корректна, contract-фаза не требуется).
- **ADR 0017 (Configuration-as-Data)** — уточняется: изменение правила в `company_settings` публикует событие `RuleChanged`. Amendment к ADR 0017 будет оформлен отдельной заявкой при ratification ADR-0017. ADR-0017 в статусе `proposed` — **warning (не блокер)**.
- **ADR 0020 (JSON descriptors)** — `rule_json` наследует формат дескриптора. ADR-0020 в статусе `reserved` — **warning**: контракт descriptor'а ещё не финализирован, потребуется re-review при ratification ADR-0020.
- **ADR 0016 (Event Bus)** — событие `RuleChanged` добавляется в business-события. ADR-0016 в статусе `proposed` — **warning** (та же ситуация, что и для ADR-0015; integrates-with зависимость допустима).

## Вердикт

**APPROVED** (governance-auditor backup-mode, 2026-04-19).

ADR-0023 переведён в `accepted`. Sprint 3 M-OS-1.1B может использовать `rule_snapshots` как утверждённый паттерн.

**Ключевой аргумент:** решение Владельца Q4+Q5 msg 1480 прямо выбирает Вариант A; 3 альтернативы обоснованно рассмотрены; паттерн универсальный (DRY на будущие сущности); DoD содержит проверяемые критерии ретроактивности (`test_retroactive_rule_change`) и immutability (`test_snapshot_immutable`); противоречий с Конституцией / CODE_OF_LAWS / принятыми ADR (0004, 0007, 0011, 0013, 0014) не выявлено.

## Warnings (не блокирующие)

1. **Integrates-with зависимости на proposed/reserved ADR.** ADR-0016 (Event Bus, proposed), ADR-0017 (Configuration-as-Data, proposed), ADR-0020 (JSON descriptors, reserved). При ratification каждого из них возможны уточнения контракта ADR-0023 (формат `rule_json` descriptor, механизм публикации `RuleChanged`). Не блокер — прецедент ADR-0014 / ADR-0015.
2. **Amendment к ADR-0017.** После ratification ADR-0017 нужна отдельная заявка: «изменение правила в `company_settings` публикует событие `RuleChanged`». Трек.
3. **Partial multi-company.** В схеме `rule_snapshots.company_id` корректен. FK `payments.approval_rule_snapshot_id` не требует изменения Payment.company_id. Согласовано.
4. **Backfill скрипт.** Один раз при деплое, идемпотентный, не в рамках Alembic round-trip (но в плане внедрения явно зафиксирован). Рекомендация: backend-director при реализации документирует скрипт как `backend/scripts/backfill_rule_snapshots_v1.py` с отдельным тестом идемпотентности.
5. **Rule immutability.** DoD пункт 6 предлагает выбор — триггер БД или «дублирование в новую version». Рекомендация (не блокер): выбрать триггер-запрет UPDATE/DELETE на уровне БД для строгой аудируемости; backend-director фиксирует выбор при реализации. Если выбрано дублирование — явно указать в тексте ADR amendment'ом.
6. **CODE_OF_LAWS ст. 42** — требует Sync-3 (добавить 0013, 0014, 0015, 0023). Отдельный трек.

## Ретроспективное ревью

При восстановлении `governance-director` — заявка подаётся на ретроспективный approve. Если Директор найдёт критичное — отдельный amendment-ADR.

---

*Заявка подана и решена Координатором через governance-auditor (backup-mode) 2026-04-19. Основание: прямое решение Владельца Q4+Q5 msg 1480 2026-04-19 + старт Sprint 3 M-OS-1.1B + прецеденты ADR-0014 / ADR-0015 ratification.*
