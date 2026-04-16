# Фаза 3 — Скоуп

**Дата**: 2026-04-15
**Статус**: ⏳ на согласование Владельца
**Оценка**: 10–14 дней (по ROADMAP)

## Цель фазы

Эндпоинты на чтение и запись для всех основных бизнес-сущностей MVP. На выходе — рабочий Swagger с покрытием всех CRUD-операций, каждая write-операция попадает в `audit_log`, каждый эндпоинт защищён RBAC.

## Полный список сущностей (16 моделей)

Подтверждено чтением `backend/app/models/`:

1. `User` — (уже есть в Фазе 2, только admin-CRUD в этой фазе)
2. `Project` — проект/посёлок
3. `Stage` — справочник стадий стройки
4. `HouseType` — 4 типа домов
5. `OptionCatalog` — каталог опций
6. `HouseTypeOptionCompat` — совместимость типов и опций
7. `House` — 85 домов
8. `HouseConfiguration` — конфигурация конкретного дома
9. `HouseStageHistory` — история смен стадий дома
10. `BudgetCategory` — 10+ статей бюджета
11. `BudgetPlan` — план по (проект × статья × стадия × дом)
12. `Contractor` — подрядчики
13. `Contract` — договоры
14. `Payment` — платежи
15. `MaterialPurchase` — закупки материалов
16. `AuditLog` — **только read** (append-only через middleware, не CRUD)

---

## Разбиение на батчи

**Цель разбиения**: ревью по частям, ранняя обратная связь, чтобы не переделывать 16 эндпоинтов разом.

### Батч A — Каталог и справочники (ориентир 3–4 дня)

Сущности без сложных бизнес-зависимостей. Первый в работу — здесь отрабатываем общий CRUD-паттерн, формат ошибок, пагинацию, audit-хук.

- `Project` (полный CRUD, owner only на create/delete)
- `Stage` (read-only для всех, CRUD только owner)
- `HouseType` (CRUD owner; read для всех)
- `OptionCatalog` (CRUD owner; read для всех)
- `HouseTypeOptionCompat` (bulk assign через отдельный эндпоинт)
- `House` (CRUD owner + construction_manager; read для всех)
- `HouseConfiguration` (CRUD owner + construction_manager)
- `HouseStageHistory` (read всем; write — только через переход стадии у House, отдельного CRUD нет)

**DoD Батч A**: 8 роутеров, Swagger зелёный, 100% эндпоинтов покрыты RBAC, аудит на всех write, интеграционные тесты ≥1 на эндпоинт.

### Батч B — Финансы-план (ориентир 2–3 дня)

- `BudgetCategory` (CRUD owner + accountant; read всем)
- `BudgetPlan` (CRUD owner + accountant; read всем) — основной сценарий: массовая загрузка плана

**DoD Батч B**: 2 роутера + bulk-endpoint для загрузки плана, тесты на пересчёт агрегатов (заглушка — без бизнес-логики дашборда, это Фаза 5).

### Батч C — Финансы-факт (ориентир 3–4 дня)

- `Contractor` (CRUD owner + accountant)
- `Contract` (CRUD owner + accountant; read + construction_manager)
- `Payment` (CRUD owner + accountant; read всем; **иммутабельность после approved**)
- `MaterialPurchase` (CRUD construction_manager + accountant + owner; read всем)

**DoD Батч C**: 4 роутера, проверка ссылочной целостности (Payment→Contract→Contractor), тесты на иммутабельность approved Payment, тесты на каскадные запреты на delete.

---

## Кросс-срезовые компоненты (делаются в Батче A, переиспользуются в B/C)

1. **Базовый CRUD-паттерн** — решается в ADR 0004.
2. **Формат ошибок** — ADR 0005.
3. **Пагинация и фильтрация** — ADR 0006.
4. **Аудит-лог** (middleware или явный сервис) — ADR 0007.
5. **Soft-delete API-семантика** — модели с `SoftDeleteMixin` не удаляют физически; `DELETE /…` выставляет `deleted_at`. Read-эндпоинты по умолчанию фильтруют soft-deleted.

## Что НЕ входит в Фазу 3

- Бизнес-логика дашборда план/факт — Фаза 5.
- Сводные отчёты / экспорты — Фаза 8.
- UI — Фаза 4.
- Bulk-импорт из Excel — отдельная история после MVP.
- Webhook / external-API интеграции — не MVP.

## Риски

| # | Риск | Митигация |
|---|---|---|
| R1 | Рутина 16 моделей → усталость и копипаста | Жёсткий общий паттерн (ADR 0004), батчи |
| R2 | Кросс-модельные зависимости (Payment требует Contract) | Батчи идут строго A→B→C |
| R3 | Аудит-лог станет bottleneck на каждом запросе | Замер в конце Батча A; решение до Батча B |
| R4 | Swagger перегружен, Владельцу трудно тестировать | Tag по батчам, короткие summaries |

## Критерий закрытия Фазы 3

1. 15 бизнес-роутеров работают, `AuditLog` append-only.
2. Swagger: все эндпоинты имеют summary, description, примеры.
3. RBAC: покрытие 100% write-эндпоинтов, проверено тестами.
4. Аудит-лог: запись появляется на каждой write-операции.
5. Интеграционные тесты: ≥1 happy path + ≥1 permission-denied + ≥1 validation-error на эндпоинт.
6. DoD-чек-лист `phase-3-checklist.md` — все пункты зелёные.
7. Reviewer `approve` на каждом из трёх батчей.
8. Ретро `phase_3_retro.md`.
