# Заявка Sync-1 — синхронизация Свода и регламентов с реальностью после bootstrap отделов Governance и R&I

**Дата:** 2026-04-15
**Инициатор:** Координатор (bootstrap комиссии, пока Директор Governance не подгружен в сессию)
**Основание:** отчёт первого еженедельного аудита — `docs/governance/audits/weekly/2026-04-15-first-audit.md`
**Тип:** пакет (объединённые находки W1, W2, W3, W4, W5, M3, M4, M5, M7, M8)

---

## Что меняется

Единый пакет правок по итогам первого аудита Governance:

1. **W1** — `docs/agents/CODE_OF_LAWS.md` ст. 30: добавить строки `governance.md` и `research.md`; обновить статусы `backend.md` и `quality.md` с «🟡 пишется» на «🟢 действующий v1.0». Обновить Приложение А (карта документов).
2. **W2** — `docs/agents/CODE_OF_LAWS.md` Книга V (ст. 49–54): заменить блок о dormant compliance на короткую отсылку к отделу Governance. Параллельный отдел compliance не создаётся.
3. **W3** — `docs/agents/regulations/director.md` ст. 12: добавить подпункт с триггерами эскалации на уровень Директора (ADR, безопасность, юр-аспекты, блокеры >1 Сотрудника). Ссылка на `regulations_addendum_v1.4.md` §7.1.
4. **W4** — `docs/agents/departments/governance.md`: добавить раздел «Поведенческий аудит» (триггеры + процедура) и «SLA комиссии» (≤2 рабочих дня на вердикт, заявки по еженедельному отчёту — в одной сессии).
5. **W5** — `docs/agents/CODE_OF_LAWS.md` преамбула: переформулировать правило о приоритете коллизий — сослаться на §«Приоритет коллизий» в `departments/governance.md` (6-уровневая иерархия). «Первоисточник имеет приоритет» действует только в пределах одного уровня иерархии.
6. **M3** — шапки `regulations_addendum_v1.1.md` и `v1.2.md`: статус «⏳ черновик на согласование» → «✅ утверждено Владельцем 2026-04-11».
7. **M4** — шапка `regulations_addendum_v1.3.md`: статус → «✅ утверждено Владельцем 2026-04-15».
8. **M5** — `docs/agents/CODE_OF_LAWS.md` ст. 46: добавить строку «ADR 0004 Amendment 2026-04-15 — директория FastAPI-роутеров `backend/app/api/` вместо `routers/`».
9. **M7** — `~/.claude/agents/reviewer.md`: унифицированный футер «Привязка к регламенту» (ссылки на `CLAUDE.md`, `CODE_OF_LAWS.md`, `regulations/worker.md`, `departments/quality.md`, `regulations_addendum_v1.3.md` §1).
10. **M8** — `~/.claude/agents/memory-keeper.md`: унифицированный футер; уточнение в ограничениях про правку memory-директории (v1.2 §A4.7).

## Почему

См. первый еженедельный аудит `docs/governance/audits/weekly/2026-04-15-first-audit.md`:
- Свод отстал от реальности на 2 отдела и неверно отражал статус ещё двух.
- Книга V Свода описывает dormant compliance, параллельный только что созданному отделу Governance — риск будущих конфликтов по подведомственности.
- Регламенты уровней Директора не содержат критериев эскалации «рутинное / серьёзное».
- Должностная `governance-auditor.md` упоминает поведенческий аудит, которого нет в регламенте отдела.
- Преамбула Свода декларирует приоритет «первоисточника», что конфликтует с 6-уровневой иерархией в `departments/governance.md`.
- Маркеры статуса в шапках дополнений v1.1–v1.3 отстали от фактического утверждения Владельцем.
- ADR 0004 Amendment не отражён в Своде ст. 46.
- Должностные `reviewer.md` и `memory-keeper.md` ссылаются на устаревшие документы v1.0–v1.2 вместо актуальных `regulations/worker.md` + `departments/*.md` + v1.3.

## На что влияет

Изменяются документы:
- `docs/agents/CODE_OF_LAWS.md` (преамбула, ст. 30, Книга V, ст. 46, Приложение А)
- `docs/agents/departments/governance.md` (новые разделы «Поведенческий аудит», «SLA комиссии»)
- `docs/agents/regulations/director.md` (ст. 12)
- `docs/agents/regulations_addendum_v1.1.md` (шапка)
- `docs/agents/regulations_addendum_v1.2.md` (шапка)
- `docs/agents/regulations_addendum_v1.3.md` (шапка)
- `~/.claude/agents/reviewer.md` (футер)
- `~/.claude/agents/memory-keeper.md` (футер + ограничения)
- `docs/governance/CHANGELOG.md` (новая запись)

Не затрагивается:
- `backend/` (работа в stage, чужая зона)
- `~/.claude/agents/ri-*`, `~/.claude/agents/governance-*` (правит Координатор отдельно)
- `docs/agents/departments/research.md` (правит Координатор отдельно)
- `MEMORY.md`, `docs/research/*`

## Вердикт

**Approved** Координатором в режиме bootstrap комиссии: Директор Governance ещё не подгружен в текущую сессию, при этом все изменения — прямые следствия зафиксированного аудита, одобрены Владельцем (Telegram msg 606). Дальнейшие заявки пойдут по стандартной процедуре через `governance-director`.

---

**Статус заявки:** approved (bootstrap)
**Исполнитель:** Координатор
**Ожидаемый аудит-след:** запись в `docs/governance/CHANGELOG.md`.
