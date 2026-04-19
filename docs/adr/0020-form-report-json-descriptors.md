---
status: reserved
title: "ADR 0020 — Form/Report JSON Descriptors: формат декларативного описания форм, отчётов, формул KPI"
date: 2026-04-18
authors: [architect]
depends_on: [ADR-0024, ADR-0018]
---

# ADR 0020 — Form/Report JSON Descriptors: формат декларативного описания форм, отчётов, формул KPI

- **Статус**: RESERVED
- **Дата (placeholder)**: 2026-04-18
- **Авторы**: architect
- **Зависит от**: ADR-0024 (RESERVED: Config-as-Data ADR — номер зарезервирован; ранее ошибочно указывался как ADR-0017, который фактически является Hooks Defense-in-Depth), ADR-0018 (Admin UI Constructor)

---

## Контекст

ADR-0024 (Config-as-Data, RESERVED) хранит `bpm_process_steps`, `form_fields`, `report_definitions` как JSONB в дочерних таблицах, но намеренно не фиксирует синтаксис этих дескрипторов — это зона ADR 0020. ADR-0022 (Analytics & Reporting Data Model) содержит 23 явные ссылки на ADR 0020: поле `kpi_definitions.formula` обязано соответствовать JSON Schema ADR-0020; движок Report Builder компилирует этот дескриптор в параметризованный SQL. Без утверждённого контракта ADR-0020 разработчики ADR-0022 и admin-UI работают с «ожидаемым минимальным интерфейсом», что создаёт риск рассинхронизации.

ADR 0020 фиксирует: (а) формат JSON-дескриптора формулы KPI (`version`, `type`, `numerator`, `denominator`, `post`); (б) формат дескриптора отчёта (`data_source`, `filters`, `aggregations`, `visualization`); (в) JSON Schema для валидации в сервисном слое до записи; (г) правила расширения формата при появлении новых типов (`ratio`, `sum`, `count`, `avg`, `custom`); (д) синтаксис условий алертов (`alert_condition`).

ADR входит в Волну 4 Foundation, разрабатывается параллельно с ADR-0022. Является критической зависимостью для M-OS-1.3 (Report Builder) и для валидации в CI-job `validate-kpi-formulas`.

## Статус

RESERVED — полноценный текст будет написан в Волну 4 (ориентировочно к спринту M-OS-1.3 Report Builder, параллельно с ADR-0022 и ADR-0018).

Срок написания по плану backend-director: 22 апреля (см. forward-reference в ADR-0022).

## Где упоминается

| Файл | Контекст упоминания |
|---|---|
| `docs/adr/0022-analytics-reporting-data-model.md` | 23 ссылки: `kpi_definitions.formula`, движок Report Builder, CI-job, `alert_condition`, JSON Schema |
| `docs/pods/cottage-platform/m-os-1-foundation-adr-plan.md` | Неявно — через ADR-0024 (form_fields, report_definitions как JSONB) |
| `docs/reviews/regulations-lint-baseline-2026-04-18.md` | Упоминается как missing — 117 P1 findings |
