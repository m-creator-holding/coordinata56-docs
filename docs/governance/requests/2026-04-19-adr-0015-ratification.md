---
name: ADR 0015 ratification (Integration Registry)
description: Backup-mode ratification ADR-0015 — governance-director недоступен через Agent tool. Закрывает DoD предусловие ADR-0014 и разблокирует Sprint 3 M-OS-1.1B (US-11).
type: governance-request
date: 2026-04-19
applicant: Координатор (backup-mode)
decision: approved
reviewer: governance-auditor (backup-approver, резервный режим)
---

# Заявка: ADR 0015 ratification (Integration Registry)

## Мотивация

ADR-0015 «Integration Registry» описывает таблицу `integration_catalog` (хранилище состояния адаптеров), seed 7 записей, service-слой `IntegrationRegistry`, TTL-кеш с инвалидацией через business_events_bus, правила переходов состояний.

ADR-0015 является **прямым предусловием DoD ADR-0014** (зафиксировано в Amendment 2026-04-18 architect): без ratification ADR-0015 невозможно выполнить seed-миграцию каркаса адаптеров. Также ADR-0015 является **предусловием старта Sprint 3 US-11** (explicitly в плане внедрения самого ADR).

**Backup-mode.** `governance-director` недоступен через Agent tool (force-majeure паттерн зафиксирован в memory; инцидент повторно воспроизвёлся 2026-04-19). Вердикт выносит `governance-auditor` по Системной находке ретроспективного вердикта 2026-04-18 и прецеденту ADR-0014 ratification того же дня. Владелец одобрил Координатору использование backup-mode.

## Скоуп правок

1. `docs/adr/0015-integration-registry.md` — frontmatter `status: proposed → accepted` + дата утверждения 2026-04-19 + footer ratification.
2. `docs/governance/CHANGELOG.md` — новая запись о ratification.

## Проверка каноничности (CODE_OF_LAWS Книга II — ADR process)

| Критерий | Статус | Комментарий |
|----------|--------|-------------|
| Статус `proposed` достаточное время | ДА | 2026-04-18 → 2026-04-19, ≥1 день; backup-mode оправдан предусловием DoD ADR-0014 |
| Обоснован выбор альтернативы | ДА | 4 варианта рассмотрены (A: PostgreSQL — принят; B: YAML — отклонён (противоречит ADR-0014); C: Redis — отклонён (ADR-0002 не включает Redis); D: multi-tenant — отклонён (избыточно для M-OS-1)) |
| Схема БД определена | ДА | 2 enum + таблица `integration_catalog` с 10 полями + 2 индекса, правила регистра (ADR-0013 совместимость) |
| Seed содержателен и соблюдает ст. 45а | ДА | 7 записей: 1 `enabled_live` (telegram, явное разрешение Владельца), 6 `written` (остальные, полный mock до production-gate) |
| Service-контракт определён | ДА | `get_state / get_all / set_state / invalidate_cache` с RBAC (owner) и AuditLog (ADR-0007) |
| Правила переходов состояний | ДА | Прямой `written → enabled_live` запрещён на уровне сервиса (не конвенцией); откат `enabled_live → enabled_mock` разрешён owner; `enabled_live → written` только через governance-director |
| Риски перечислены | ДА | 6 рисков с митигациями (fail-fast БД, CI-тест seed, lint credentials_ref, grant-политика БД) |

## Согласованность с каноном

- **CODE_OF_LAWS ст. 45а/45б** — прямая реализация. `enabled_live` только для Telegram в seed; runtime-guard блокирует переход `written → enabled_live` на уровне сервиса; каждый toggle пишется в AuditLog (crypto-chain, ст. 45б «фиксируется в AuditLog»).
- **Конституция M-OS** — принцип изоляции подов и skeleton-first соблюдён (mock по умолчанию, live только по явному решению Владельца в production).
- **CLAUDE.md раздел «Данные и БД»** — enum в миграции соответствует `.value` Python-enum (раздел схемы явно это оговаривает, регистр строчный).
- **ADR-0014** — закрывает DoD предусловие seed-миграции; ссылка взаимная и корректная.
- **ADR-0011** — RBAC owner-роль используется для `set_state`; AuditLog наследует crypto-chain.
- **ADR-0013** — DDL и DML идут отдельными Alembic-ревизиями (в плане внедрения явно разделены).
- **ADR-0016** — событие `AdapterStateChanged` публикуется в `business_events_bus` для инвалидации кеша. ADR-0016 в статусе `proposed` — **warning (не блокер)**: аналогично тому, как ADR-0014 был принят при `proposed` ADR-0015; integrates-with зависимость допустима.
- **ADR-0018** — governance-link на production-gate корректен; переход `enabled_mock → enabled_live` заблокирован в сервисе без `APP_ENV=production` + gate-ratification. ADR-0018 в статусе `proposed` — **warning (не блокер)**: блокировка работает на runtime-уровне, активируется автоматически при ratification ADR-0018.

## Открытые вопросы Владельцу (из тела ADR)

ADR-0015 содержит 3 открытых вопроса (Q1 `credentials_ref` Telegram в dev, Q2 `kind enum` для `kryptopro`, Q3 multi-tenancy credentials). **Не блокируют ratify** — это operational-детали, решаются точечно при реализации Sprint 3 / при появлении второй компании. Координатор передаёт Владельцу в следующем сессионном отчёте.

## Вердикт

**APPROVED** (governance-auditor backup-mode, 2026-04-19).

ADR-0015 переведён в `accepted`. Предусловие DoD ADR-0014 закрыто. Sprint 3 US-11 разблокирован.

**Ключевой аргумент:** 4 альтернативы рассмотрены и обоснованы; выбранный вариант A (PostgreSQL) единственный совместимый с ADR-0014 (единый источник правды), ADR-0013 (стандартный Alembic-паттерн), ADR-0011 (RBAC + AuditLog из коробки); seed строго соблюдает ст. 45а/45б (только Telegram `enabled_live`); runtime-блокировка `written → enabled_live` на уровне сервиса снимает класс ошибок «прямой переход через raw SQL / seed».

## Warnings (не блокирующие)

1. **Integrates-with зависимости на proposed ADR.** ADR-0016 (Event Bus) и ADR-0018 (Production Gate) в статусе `proposed`. ADR-0015 полагается на их будущую ratification для полной семантики (шина событий и gate-trigger). До их принятия — guard работает по текущему контракту (TTL 60 сек + APP_ENV=production проверка). Не блокер — прецедент принятия ADR-0014 при `proposed` ADR-0015 легитимирует integrates-with зависимости.
2. **Открытые вопросы Владельцу (Q1/Q2/Q3)** — требуют ответа до финальной реализации Sprint 3. Не блокер ratify, но Координатор обязан передать Владельцу.
3. **CODE_OF_LAWS ст. 42** (перечень ADR) — требует Sync-3 (добавить 0013, 0014, 0015). Не блокер, отдельный трек.
4. **Процедурный пробел.** Формализация backup-mode в `departments/governance.md` — отдельная заявка после стабилизации governance-director (precheck 2026-04-22 §3.5).

## Ретроспективное ревью

При восстановлении `governance-director` — заявка подаётся на ретроспективный approve. Если Директор найдёт критичное — отдельный amendment-ADR.

---

*Заявка подана и решена Координатором через governance-auditor (backup-mode) 2026-04-19. Основание: предусловие DoD ADR-0014 + старт Sprint 3 US-11 + прецедент ADR-0014 ratification 2026-04-18.*
