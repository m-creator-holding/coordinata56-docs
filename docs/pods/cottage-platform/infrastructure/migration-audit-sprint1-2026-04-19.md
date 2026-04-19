# Migration Audit — Sprint 1 — 2026-04-19

**Статус**: завершён  
**Ревьюер**: db-head (coordinata56), db-engineer (L4)  
**Дата**: 2026-04-19  
**БД**: PostgreSQL 16.13, dev (`coordinata56` @ 127.0.0.1:5433)  
**Состояние цепочки до аудита**: `us03_rbac_owner_seed` (head)  
**ADR-baseline**: ADR-0013 Migrations Evolution Contract

---

## Scope

Миграции Sprint 1 (US-01, US-02, US-03):

| Файл | Revision ID | Дата |
|------|-------------|------|
| `2026_04_18_1000_c34c3b715bcb_users_is_holding_owner.py` | `c34c3b715bcb` | 2026-04-18 |
| `2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py` | `ac27c3e125c8` | 2026-04-18 |
| `2026_04_18_1600_d3a7f8e21719_audit_crypto_chain_expand.py` | `d3a7f8e21719` | 2026-04-18 |
| `2026_04_19_1000_us03_rbac_defaults_seed.py` | `us03_rbac_defaults_seed` | 2026-04-19 |
| `2026_04_19_1100_us01_add_company_id.py` | `us01_add_company_id` | 2026-04-19 |
| `2026_04_19_1200_us03_rbac_owner_seed.py` | `us03_rbac_owner_seed` | 2026-04-19 |

---

## Результаты по миграциям

### c34c3b715bcb — users_is_holding_owner — PASS

**Round-trip**: чистый (downgrade: DROP COLUMN; upgrade: expand → backfill → NOT NULL).  
**ADR-0013 compliance**:

- Expand-pattern соблюдён: nullable → backfill UPDATE → ALTER NOT NULL с server_default=false().
- migration-exception задокументирован с обоснованием.
- downgrade симметрично удаляет колонку.

**Замечаний нет.**

---

### ac27c3e125c8 — rbac_v2_pd_consent — PASS с WARN

**Round-trip**: чистый.  
**ADR-0013 compliance**: соблюдён.

**WARN-1**: Заявлено 23 permissions в комментарии миграции. Фактически вставляется 25: `user_roles.read` и `user_roles.admin` добавлены вне основного блока seed (шаг 7.2) в отдельном INSERT в конце upgrade. Несоответствие документации коду. На корректность не влияет, но создаёт путаницу при cross-migration аудите (см. WARN в us03 ниже).

**WARN-2**: Seed `role_permissions` для роли `owner` выполнен через `SELECT * FROM roles WHERE r.code='owner'` — полный набор permissions для owner. Однако `us03_rbac_defaults_seed` помечает это как BUG-001 (owner не получал role_permissions). Противоречие в документации: в ac27 owner-seed присутствует, но us03_rbac_owner_seed описывает его как отсутствующий. При анализе фактических данных БД до `us03_rbac_defaults_seed` у owner было 29 role_permissions — из них часть принадлежит ac27 seed. Требует уточнения в changelog.

---

### d3a7f8e21719 — audit_crypto_chain_expand — PASS

**Round-trip**: чистый.  
**ADR-0013 compliance**: соблюдён.

- Expand-pattern: два nullable-поля `prev_hash`, `hash` без backfill.
- downgrade: drop_index → drop_column в корректном порядке.
- `ix_audit_log_hash` не UNIQUE — корректно, hash может быть NULL у legacy-записей.
- NOT NULL-контракт отложен на отдельную миграцию — задокументировано.

**Замечаний нет.**

---

### us03_rbac_defaults_seed — WARN (ранее оценено P1, скорректировано)

**Round-trip**: функционально проходит на dev-БД без пользовательских данных. Фактические данные после `downgrade → upgrade` цикла: permissions=77, role_permissions=253, roles=8 — состояние совпадает.

**Нарушение ADR-0013 §1 (cross-migration symmetry)**:

`us03_rbac_defaults_seed` вставляет `project.write` и `project.delete` в permissions через `ON CONFLICT DO NOTHING` (они уже существуют в ac27). В downgrade эти два кода присутствуют в списке `DELETE FROM permissions WHERE code IN (...)`.

**Фактический эффект**: после `downgrade us03_rbac_defaults_seed` в таблице `permissions` остаётся 23 записи — и `project.write`, `project.delete` в них отсутствуют, хотя принадлежат ac27. Через FK `ondelete=CASCADE` (`fk_rp_permission_id`) удаляются все `role_permissions` для этих двух прав.

**Риск**:
- На чистой dev-БД (без данных) и при стандартном `upgrade head` от base — не проявляется.
- При частичном rollback в боевой среде (downgrade до `d3a7f8e21719` → upgrade отдельно до `ac27c3e125c8`) — состояние БД не совпадёт с ожидаемым: два права и их role_permissions исчезнут.

**Рекомендуемое исправление**: убрать `project.write` и `project.delete` из списка `DELETE` в `downgrade()` миграции `us03_rbac_defaults_seed`. Они принадлежат ac27 и не должны удаляться откатом us03.

**WARN, не BLOCK**: на текущем dev-цикле (только `upgrade head` от base) не проявляется. Для production требует исправления до первого применения.

---

### us01_add_company_id — PASS с WARN

**Round-trip**: чистый. Прогнан как часть полного цикла `downgrade d3a7f8e21719 → upgrade head`.  
**ADR-0013 compliance**: Expand → Backfill → Contract соблюдён на 10 таблицах.

**Проверки**:
- На clean БД backfill `UPDATE SET company_id=1 WHERE company_id IS NULL` обновил 0 строк — FK нарушения нет.
- `reversed(_TABLES)` в downgrade loop обеспечивает обратный порядок — корректно.
- Шаг 4 (UNIQUE рефакторинг): `drop_index ix_{tbl}_code` → `create_unique_constraint uq_{tbl}_company_id_code`. Downgrade восстанавливает исходные индексы с `unique=True` — соответствует `initial_schema`.

**WARN**: downgrade создаёт индексы через строковый литерал `f'ix_{tbl}_code'` без `op.f()`. В `env.py` naming_convention не задан, поэтому имена фактически совпадают. Стилистическое несоответствие с `initial_schema` (там используется `op.f()`). Не влияет на функциональность, но снижает консистентность.

---

### us03_rbac_owner_seed — PASS

**Round-trip**: чистый.  
**ADR-0013 compliance**: соблюдён.

- upgrade: `INSERT WHERE NOT EXISTS` — идемпотентно.
- downgrade: `DELETE WHERE role_id = owner` — корректно восстанавливает состояние до этой миграции (BUG-001 state: у owner 0 записей в role_permissions до этого fix).
- Допущение downgrade явно задокументировано в файле.

**Замечаний нет.**

---

## Нарушения ADR-0013

| # | Миграция | Тип | Severity | Описание |
|---|----------|-----|----------|----------|
| 1 | us03_rbac_defaults_seed | Cross-migration downgrade symmetry | WARN | downgrade удаляет `project.write` и `project.delete` из permissions — они принадлежат ac27c3e125c8. На dev не проявляется, на production при partial rollback — потеря данных. |
| 2 | ac27c3e125c8 | Документационное несоответствие | WARN | Заявлено 23 permissions, фактически 25. |

---

## Рекомендации

1. **us03_rbac_defaults_seed** — убрать `project.write` и `project.delete` из `DELETE` в downgrade. Это нарушение принадлежности данных между миграциями. Приоритет: до production-gate.

2. **us01_add_company_id** — заменить строковые литералы `f'ix_{tbl}_code'` на `op.f(f'ix_{tbl}_code')` в downgrade для консистентности с `initial_schema`. Приоритет: низкий (косметика).

3. **ac27c3e125c8** — обновить комментарий: «23 permissions» → «25 permissions (23 основных + user_roles.read/admin)». Приоритет: низкий (документация).

4. **CI round-trip**: ADR-0013 требует автоматического CI-шага `upgrade head → downgrade -1 → upgrade head`. Сейчас не реализован (DoD ADR-0013 не закрыт). Рекомендуется добавить в следующем спринте.

---

## Round-trip результат

**Метод**: `alembic downgrade d3a7f8e21719 → alembic upgrade head` (полный sprint 1 cycle).  
**БД**: dev, PostgreSQL 16.13, данные присутствуют (seed из предыдущих миграций).

| Шаг | Команда | Результат |
|-----|---------|-----------|
| Downgrade Sprint 1 | `alembic downgrade d3a7f8e21719` | OK — 3 downgrade без ошибок |
| Upgrade head | `alembic upgrade head` | OK — 3 upgrade без ошибок |
| Финальная ревизия | `alembic current` | `us03_rbac_owner_seed (head)` |
| Счётчик permissions | после upgrade | 77 |
| Счётчик role_permissions | после upgrade | 253 |
| Счётчик roles | после upgrade | 8 |

**Отдельный cycle us03**: `downgrade us03 → upgrade us03` — round-trip чистый по count (23 → 77 → 23). Однако состав 23 permissions после downgrade us03 не идентичен состоянию ac27 HEAD: отсутствуют `project.write` и `project.delete`.

**Итоговый вердикт**: Sprint 1 миграции применимы к dev и могут идти в тест. До production-gate требуется исправление us03_rbac_defaults_seed (рекомендация 1).
