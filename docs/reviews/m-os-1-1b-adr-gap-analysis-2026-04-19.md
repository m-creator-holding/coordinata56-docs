# Gap Analysis ADR — M-OS-1.1B Configuration/Admin Foundation

- **Дата**: 2026-04-19
- **Автор**: architect (субагент L4 Advisory)
- **Контекст**: M-OS-1.1B начинается через ~3 недели после завершения M-OS-1.1A
- **Скоуп 1.1B**: Configuration-as-Data (9 категорий), Admin UI конструктор (4 страницы: permissions / companies / users / rules), Rule Snapshots (ADR-0023)

---

## 1. Что уже покрыто ADR

| Gap-область | ADR | Статус | Покрытие |
|---|---|---|---|
| Структура хранения 7 полей company_settings | ADR-0017-CaD (план) | **MISSING** | Задокументировано только в m-os-1-foundation-adr-plan.md, не в ADR |
| Rule Snapshots Pattern | ADR-0023 | accepted (force-majeure) | Полное |
| Form/Report JSON descriptor format | ADR-0020 | reserved | Только placeholder |
| Admin UI Constructor (под-фазы) | ADR-0018 | proposed | Структурно есть, но зависит от ADR-0017-CaD |
| Pluggability Contract | ADR-0019 | reserved | Зависит от ADR-0017-CaD |
| Integration Registry (Admin UI часть) | ADR-0015 | accepted (force-majeure) | Покрыто — таблица, сервис, Admin UI toggle |

---

## 2. Выявленные gaps

### GAP-1 (критический): ADR-0017-CaD — Configuration-as-Data Layer

**Что должно быть**: полноценный ADR, описывающий A3-гибрид (мета-таблица `configuration_entities` + 9 дочерних таблиц), версионирование конфигов, hot-reload, optimistic lock, BPM migration rules (11 правил), 7 полей company_settings.

**Что есть**: решения Владельца зафиксированы только в `m-os-1-foundation-adr-plan.md` §ADR-0017. Файла `docs/adr/0017-configuration-as-data.md` не существует.

**Дополнительная проблема**: номер 0017 уже занят файлом `0017-hooks-defense-in-depth.md`, что создаёт конфликт нумерации.

**Блокирует**: ADR-0019 (reserved), ADR-0020 (reserved), ADR-0023 (принят с dependency), весь Admin UI конструктор.

**Предлагаемый ADR**: `ADR-0024 — Configuration-as-Data Layer: мета-таблица + 9 дочерних категорий, версионирование, hot-reload`  
**Статус**: proposed (срочно писать перед Sprint 1 M-OS-1.1B)

---

### GAP-2 (высокий): отсутствует ADR на версионирование конфигураций

**Что должно быть**: ADR, описывающий механизм истории изменений конфигурации (`draft → published → archived`), rollback (смена статуса версий), структуру `config_version_history`, кто может публиковать / откатывать, UI-паттерн «Preview & Publish».

**Что есть**: в плане ADR-0017 (CaD) есть раздел «Версионирование конфигурации» — одна страница без альтернатив и без детализации конфликта rollback при запущенных BPM-экземплярах. ADR-0023 решает версионирование rule_snapshots, но не конфигов в целом.

**Пробел**: нет формального выбора между вариантами хранения истории (append-only child-таблица версий vs отдельная history-таблица vs event-sourcing) с обоснованием и последствиями.

**Предлагаемый ADR**: `ADR-0025 — Config Version History: append-only версионирование конфигурационных сущностей и rollback`  
**Статус**: proposed (писать параллельно с ADR-0024)

---

### GAP-3 (средний): отсутствует ADR на Admin UI — Data Contract (API)

**Что должно быть**: ADR, фиксирующий API-контракт между Admin UI (frontend) и backend для конфигурационного конструктора: схема endpoint-ов CRUD для `configuration_entities`, правила pagination/filtering (совместимость с ADR-0006), формат Preview-ответа перед публикацией, WebSocket/SSE vs polling для hot-reload в браузере.

**Что есть**: ADR-0018 описывает UX-принципы и под-фазы, но не фиксирует API-контракт. Wireframes v0.3 (4 страницы) существуют, но без backend-контракта.

**Пробел**: frontend-director и backend-director не имеют общего документа — риск рассинхронизации при параллельной разработке Sprint 2–3 M-OS-1.1B.

**Предлагаемый ADR**: `ADR-0026 — Admin UI API Contract: endpoints конфигурационного конструктора (M-OS-1.1B)`  
**Статус**: proposed (писать до старта параллельной разработки backend + frontend)

---

### GAP-4 (средний): отсутствует ADR на миграцию конфигов между версиями системы

**Что должно быть**: ADR, описывающий как переносить конфигурационные данные при обновлении схемы дочерних таблиц (например, добавление нового поля в `bpm_process_definitions` или смена типа в `form_fields`). Отличается от ADR-0013 (схема БД) — здесь речь о семантике данных, а не DDL.

**Что есть**: ADR-0013 покрывает backward-compatible DDL; BPM migration rules в плане ADR-0017-CaD покрывают запущенные экземпляры процессов. Но нет правил для «как мигрировать уже сохранённые JSONB-дескрипторы форм, отчётов, шаблонов при изменении их JSON-схемы».

**Пробел**: при выходе M-OS-1.2 (BPM Constructor) или M-OS-1.3 (Form Builder) разработчики столкнутся с необходимостью трансформировать сотни сохранённых JSONB-записей без регламента.

**Предлагаемый ADR**: `ADR-0027 — Config Data Migration: семантическое версионирование JSONB-дескрипторов конфигурационных сущностей`  
**Статус**: proposed (можно писать позже — до старта M-OS-1.2, не блокирует 1.1B)

---

## 3. Сводная таблица gaps

| # | Draft-название | Срочность | Блокирует | Рекомендуемый номер |
|---|---|---|---|---|
| GAP-1 | Configuration-as-Data Layer (A3 гибрид, 9 категорий) | Критическая — до Sprint 1 M-OS-1.1B | ADR-0019, ADR-0020, ADR-0023 (deps), Admin UI | **ADR-0024** |
| GAP-2 | Config Version History (append-only, rollback) | Высокая — до Sprint 2 M-OS-1.1B | Admin UI «история версий», откат конфигов | **ADR-0025** |
| GAP-3 | Admin UI API Contract (endpoints CaD конструктора) | Средняя — до параллельной разработки backend+frontend | Синхронизация frontend/backend спринтов | **ADR-0026** |
| GAP-4 | Config Data Migration (семантика JSONB при апгрейде) | Низкая — до M-OS-1.2 | M-OS-1.2 BPM Constructor, M-OS-1.3 Form Builder | **ADR-0027** |

---

## 4. Конфликт нумерации (отдельное замечание)

Файл `docs/adr/0017-hooks-defense-in-depth.md` занял номер, запланированный для `Configuration-as-Data Layer` в `m-os-1-foundation-adr-plan.md`. Это не ошибка содержания — оба документа нужны — но вызывает путаницу в ссылках:

- ADR-0019, ADR-0020, ADR-0023 содержат `depends_on: [ADR-0017]`, имея в виду Configuration-as-Data Layer, но фактически указывают на Hooks-Defense-in-Depth.

**Рекомендация governance-director**: при ratification решить один раз — либо перенумеровать Hooks (→ ADR-0025+), либо CaD получает следующий свободный номер ADR-0024, и все зависимые ADR обновляются amendment.

---

*Составлен: architect (субагент L4 Advisory), 2026-04-19.*  
*Использован: ADR map + docs/adr/0017–0023 + m-os-1-foundation-adr-plan.md v3 + gate-0-adr-status-2026-04-18.md*
