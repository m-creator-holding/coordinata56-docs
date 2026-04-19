---
status: reserved
title: "ADR 0021 — Pod Isolation Patterns: технический enforcement межпод-изоляции"
date: 2026-04-18
authors: [architect]
depends_on: [ADR-0009, ADR-0011, ADR-0016]
---

# ADR 0021 — Pod Isolation Patterns: технический enforcement межпод-изоляции

- **Статус**: RESERVED
- **Дата (placeholder)**: 2026-04-18
- **Авторы**: architect
- **Зависит от**: ADR-0009 (Pod Architecture), ADR-0011 (Foundation RBAC), ADR-0016 (Dual Event Bus)

---

## Контекст

ADR-0009 декларирует изоляцию подов: поды не импортируют модули друг друга напрямую, взаимодействие только через `BusinessEventBus` и API-контракты. Однако ADR-0009 не содержит технического инструмента принуждения (линтера, import-guards, CI-правил). По результатам `adr-consistency-audit-2026-04-18.md` этот пробел создаёт реальный риск: к запуску gas-stations-pod-lite (M-OS-2) разработчик может нарушить изоляцию без автоматического обнаружения.

ADR 0021 фиксирует: (а) правило именования пакетов подов и запрет cross-pod imports через `ruff` или `pylint`-правило; (б) CI-job `check-pod-boundaries` как gate в pipeline; (в) разрешённые каналы межпод-взаимодействия (только `BusinessEventBus` из ADR-0016 и явные REST-контракты через ACL ADR-0014); (г) паттерн shared-kernel — перечень модулей, которые могут использоваться всеми подами (только `core/`, `shared/`).

Написание ADR 0021 приоритизируется до старта разработки второго пода (gas-stations-pod-lite), чтобы первый pod (cottage-platform) успел пройти ретроспективную проверку до появления второго.

## Статус

RESERVED — полноценный текст будет написан до старта M-OS-2 (второй pod). Ориентировочная волна — M-OS-1.2/1.3 по решению architect по готовности ADR-0016 и ADR-0017.

## Где упоминается

| Файл | Контекст упоминания |
|---|---|
| `docs/reviews/adr-consistency-audit-2026-04-18.md` | Пробел: ADR 0009 не содержит enforcement; ADR 0021 должен закрыть — до появления второго пода |
| `docs/reviews/regulations-lint-baseline-2026-04-18.md` | Упоминается как missing — 117 P1 findings |
