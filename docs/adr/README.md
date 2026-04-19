# ADR Map — M-OS / coordinata56

**Версия**: 1.0  
**Дата**: 2026-04-19  
**Составил**: architect (субагент L4 Advisory)  
**Основание**: задача gap-analysis M-OS-1.1B, 2026-04-19

---

## Соглашения по статусам

| Статус | Значение |
|---|---|
| `accepted` | Утверждён governance. Обязателен к соблюдению. |
| `accepted (force-majeure)` | Принят в backup-режиме (governance-auditor). Ожидает ретроспективного ревью governance-director. |
| `proposed` | Черновик, ожидает governance approval. Не обязателен к соблюдению до утверждения. |
| `reserved` | Placeholder — текст будет написан в соответствующей волне. |
| `MISSING` | ADR упоминается в планах/других ADR как зависимость, но файл не создан. |

---

## Полная таблица ADR 0001–0023

| Номер | Название | Статус | Дата | Зависит от | Фаза |
|---|---|---|---|---|---|
| **ADR-0001** | Модель данных v1 (MVP) | `accepted` | 2026-04-11 / rev. 2026-04-14 | — | Фаза 0–3 |
| **ADR-0002** | Выбор технологического стека MVP | `accepted` | 2026-04-14 | — | Фаза 0–3 |
| **ADR-0003** | Аутентификация и авторизация MVP | `accepted` | 2026-04-15 | ADR-0001, ADR-0002 | Фаза 0–3 |
| **ADR-0004** | Структура CRUD-слоя (Phase 3) | `proposed` | 2026-04-15 | ADR-0001, ADR-0002 | Фаза 3 / M-OS-0 |
| **ADR-0005** | Формат ошибок API (Phase 3) | `proposed` | 2026-04-15 | ADR-0002 | Фаза 3 / M-OS-0 |
| **ADR-0006** | Пагинация и фильтрация (Phase 3) | `proposed` | 2026-04-15 | ADR-0001, ADR-0004 | Фаза 3 / M-OS-0 |
| **ADR-0007** | Механизм записи в аудит-лог (Phase 3) | `proposed` | 2026-04-15 | ADR-0001, ADR-0004 | Фаза 3 / M-OS-0 |
| **ADR-0008** | M-OS: определение системы и её границы | `accepted` | 2026-04-16 | — | M-OS-0 |
| **ADR-0009** | Pod-архитектура M-OS | `accepted` | 2026-04-16 | ADR-0008 | M-OS-0 |
| **ADR-0010** | Таксономия субагентов M-OS: пять типов | `accepted` | 2026-04-16 | ADR-0008, ADR-0009 | M-OS-0 |
| **ADR-0011** | Foundation: Multi-company, RBAC, Crypto Audit | `accepted` | 2026-04-16 / 2026-04-17 | ADR-0001, ADR-0009 | M-OS-1.1A |
| **ADR-0012** | Orchestration Layer (control plane) | `proposed` (ожидает governance) | 2026-04-16 | ADR-0009, ADR-0010 | M-OS-1.1A |
| **ADR-0013** | Migrations Evolution Contract | `accepted (force-majeure)` | 2026-04-17 / 2026-04-18 | ADR-0001, ADR-0011 | M-OS-1.1A |
| **ADR-0014** | Anti-Corruption Layer Foundation | `accepted (force-majeure)` | 2026-04-17 / 2026-04-18 | ADR-0009, ADR-0013, ADR-0015 | M-OS-1.1A |
| **ADR-0015** | Integration Registry (integration_catalog) | `accepted (force-majeure)` | 2026-04-18 / 2026-04-19 | ADR-0014, ADR-0011, ADR-0013 | M-OS-1.1A / 1.1B |
| **ADR-0016** | Domain Event Bus (два транспорта) | `proposed` | 2026-04-18 | ADR-0009, ADR-0013, ADR-0012 | M-OS-1.1A |
| **ADR-0017** | Hooks as Defense-in-Depth Layer | `proposed` | 2026-04-18 | CODE_OF_LAWS | M-OS-1 (горизонтальный) |
| **ADR-0017-CaD** | **Configuration-as-Data Layer** | **`MISSING`** | — | ADR-0011, ADR-0013, ADR-0015, ADR-0016, ADR-0019 | **M-OS-1.1B** |
| **ADR-0018** | Production-Gate Definition | `proposed` | 2026-04-18 | ADR-0014, ADR-0015 | M-OS горизонтальный |
| **ADR-0019** | Pluggability Contract | `reserved` | 2026-04-18 | ADR-0014, ADR-0015, ADR-0016, ADR-0017-CaD | M-OS-1.1B / Волна 4 |
| **ADR-0020** | Form/Report JSON Descriptors | `reserved` | 2026-04-18 | ADR-0017-CaD, ADR-0018 | M-OS-1.3 / Волна 4 |
| **ADR-0021** | Pod Isolation Patterns | `reserved` | 2026-04-18 | ADR-0009, ADR-0016 | M-OS-1.2 |
| **ADR-0022** | Analytics & Reporting Data Model | `proposed` | 2026-04-18 | ADR-0020, ADR-0011 | M-OS-1.3 |
| **ADR-0023** | Rule Snapshots Pattern | `accepted (force-majeure)` | 2026-04-19 | ADR-0011, ADR-0013, ADR-0017-CaD, ADR-0020, ADR-0016 | M-OS-1.1B Sprint 3 |

---

## Критический gap: конфликт нумерации ADR-0017

**Проблема.** В плане Foundation (`m-os-1-foundation-adr-plan.md` v3) номер ADR-0017 зарезервирован для `Configuration-as-Data Layer` (ключевой ADR Волны 3, P0). Однако файл `docs/adr/0017-hooks-defense-in-depth.md` занял этот номер.

**Следствие.** `Configuration-as-Data Layer` не имеет ни файла, ни номера. ADR-0019, ADR-0020, ADR-0023 ссылаются на него как на зависимость (`depends_on: [ADR-0017]`), но указывают на `Hooks-Defense-in-Depth` — не тот документ.

**Рекомендуемое решение.** Присвоить `Configuration-as-Data Layer` свободный номер (кандидат: ADR-0024 при создании после 0023) и провести amendment во всех `reserved`/`proposed` ADR, ссылающихся на него. Либо переименовать файл `0017-hooks-defense-in-depth.md` → `0025-hooks-defense-in-depth.md` (если Hooks ещё не попал в реализацию). Решение принимается governance-director.

---

## Матрица влияния по фазам

| ADR | M-OS-0 | M-OS-1.1A | M-OS-1.1B | M-OS-1.2 | M-OS-1.3 |
|---|---|---|---|---|---|
| 0001–0007 | ✅ фундамент | — | — | — | — |
| 0008–0010 | ✅ reframing | — | — | — | — |
| 0011 | — | ✅ ядро | зависимость | зависимость | зависимость |
| 0012 | — | черновик | — | — | — |
| 0013 | — | ✅ gate-0 | зависимость | зависимость | зависимость |
| 0014 | — | ✅ gate-0 | зависимость | — | — |
| 0015 | — | зависимость | ✅ admin-UI | — | — |
| 0016 | — | ✅ Sprint 1 | зависимость | зависимость | зависимость |
| **0017-CaD** | — | — | **✅ фундамент 1.1B** | зависимость | зависимость |
| 0017-Hooks | — | — | — | — | — |
| 0018 | — | — | зависимость | — | — |
| 0019 | — | — | reserved | — | — |
| 0020 | — | — | — | — | ✅ Report Builder |
| 0021 | — | — | — | ✅ | — |
| 0022 | — | — | — | — | ✅ |
| 0023 | — | — | ✅ Sprint 3 | зависимость | — |

---

## Связи между ADR (граф зависимостей)

```
ADR-0001 ──→ ADR-0003, ADR-0004, ADR-0006, ADR-0007, ADR-0013
ADR-0009 ──→ ADR-0010, ADR-0011, ADR-0012, ADR-0014, ADR-0016, ADR-0021
ADR-0011 ──→ ADR-0013, ADR-0015, ADR-0022, ADR-0023
ADR-0013 ──→ ADR-0014, ADR-0015, ADR-0016, ADR-0017-CaD
ADR-0014 ──→ ADR-0015
ADR-0015 ──→ ADR-0016, ADR-0017-CaD, ADR-0018, ADR-0019
ADR-0016 ──→ ADR-0017-CaD, ADR-0021, ADR-0023
ADR-0017-CaD ──→ ADR-0019, ADR-0020, ADR-0023
ADR-0020 ──→ ADR-0022, ADR-0023
```

---

*Составлен: architect (субагент L4 Advisory), 2026-04-19. Обновлять при каждом добавлении или смене статуса ADR.*
