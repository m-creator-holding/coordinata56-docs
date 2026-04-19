---
status: reserved
title: "ADR 0019 — Pluggability Contract: dependency injection для внешних точек расширения"
date: 2026-04-18
authors: [architect]
depends_on: [ADR-0014, ADR-0015, ADR-0016, ADR-0024]
---

# ADR 0019 — Pluggability Contract: dependency injection для внешних точек расширения

- **Статус**: RESERVED
- **Дата (placeholder)**: 2026-04-18
- **Авторы**: architect
- **Зависит от**: ADR-0014 (Anti-Corruption Layer), ADR-0015 (Integration Registry), ADR-0016 (Dual Event Bus), ADR-0024 (RESERVED: Config-as-Data ADR — номер зарезервирован; ранее ошибочно указывался как ADR-0017, который фактически является Hooks Defense-in-Depth)

---

## Контекст

ADR-0024 (Config-as-Data, RESERVED) ссылается на `ConfigurationCache` как на pluggable point по ADR-0019. ADR-0016 вводит два event bus (`BusinessEventBus`, `AgentControlBus`) — они также являются pluggable points. Без формального DI-контракта каждый компонент системы реализует внедрение зависимостей по-своему, что к M-OS-2 приведёт к несовместимым паттернам инициализации.

ADR 0019 фиксирует явный реестр `app/core/container.py` с FastAPI `Depends()` для всех 11 внешних точек расширения M-OS-1: `NotificationProvider`, `AIProvider`, `BankAdapter`, `OFDAdapter`, `1CAdapter`, `RosreestrAdapter`, `CryptoProvider`, `BusinessEventBus`, `AgentControlBus`, `ConfigurationCache`, `AuditLogger`. Правило: `BusinessEventBus` и `AgentControlBus` — разные pluggable points, нельзя зарегистрировать одну реализацию на оба ключа.

ADR входит в Волну 4 Foundation (открывается после принятия Волн 1–3). M-OS-1.1A частично реализует 4 из 11 точек.

## Статус

RESERVED — полноценный текст будет написан в Волну 4 (см. `docs/pods/cottage-platform/m-os-1-foundation-adr-plan.md`, раздел «Волна 4 — Pluggability и Admin UI»).

Параллельно в Волне 4 пишется ADR-0018 (Admin UI Constructor).

## Где упоминается

| Файл | Контекст упоминания |
|---|---|
| `docs/pods/cottage-platform/m-os-1-foundation-adr-plan.md` | Описание в таблице ADR-кандидатов Волны 4; список 11 pluggable points |
| `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` | Частичная реализация 4 из 11 точек в 1.1A; полный реестр — в 1.1B |
| `docs/reviews/regulations-lint-baseline-2026-04-18.md` | Упоминается как missing — 117 P1 findings |
