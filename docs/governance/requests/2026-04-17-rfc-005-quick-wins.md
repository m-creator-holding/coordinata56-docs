# Заявка: RFC-005 Top-10 Quick-Wins (4 governance-пункта)

- **ID:** REQ-2026-04-17-rfc-005-quick-wins
- **Дата подачи:** 2026-04-17
- **Инициатор:** Координатор (по одобрению Владельца RFC-005)
- **Источник:** `docs/research/rfc/rfc-005-cross-audit-departments.md` + решение Владельца (Telegram msg 1152+)
- **Срок:** 3-4 дня

---

## Что меняется (пакет из 4 подзаявок + 1 amendment v1.6)

### Подзаявка 1 — ADR Lifecycle: статусы и связи

**Документ:** `docs/adr/0001..0014` (14 файлов) + `docs/agents/departments/governance.md`

**Изменение:**
Обновить шапку каждого ADR, нормализовав статус по единому контракту. Вместо разношёрстных формулировок («принято», «принято v1.1, редакция ...», «утверждён (governance, ...)», «черновик», «proposed», «proposed (ожидает governance)») — единый enum из 4 значений:

- `proposed` — черновик подан, ожидает решения комиссии
- `accepted` — одобрено комиссией и Владельцем (или Владельцем напрямую — для ранних ADR до бутстрапа комиссии)
- `deprecated` — устарел, больше не применяется; замены нет
- `superseded` — заменён более новым ADR; обязательно поле `superseded_by`

Новые поля frontmatter (рядом с существующими):
- `status:` — одно из четырёх выше
- `superseded_by:` — присутствует только при status=superseded, значение: номер заменяющего ADR (например, `0015`)
- `supersedes:` — присутствует в ADR-«преемнике», значение: номер(а) заменённого(ых) ADR
- `approved_by:` и `approved_date:` — переносим из текста в frontmatter (если есть)

Контент ADR (разделы «Проблема», «Решение», «Последствия») **не трогается** — только шапка.

Регламент жизненного цикла (новый раздел в `departments/governance.md` «ADR Lifecycle»):
- Переход `proposed → accepted` — только по вердикту комиссии с пометкой в CHANGELOG.md.
- Переход `accepted → superseded` — только когда принят преемник; обязательное двустороннее связывание (`supersedes` в новом, `superseded_by` в старом).
- Переход `accepted → deprecated` — решение комиссии без преемника (технология отпала).
- ADR в статусе `superseded` / `deprecated` **не удаляются** — остаются в репозитории для истории решений.

### Подзаявка 2 — RFC Naming Convention

**Документ:** `docs/research/rfc/rfc-*.md` (4 файла) + `docs/agents/departments/governance.md` + `docs/agents/departments/research.md`

**Изменение:**
Единый формат имени файла: `rfc-YYYY-NNN-slug.md`, где:
- `YYYY` — год подачи
- `NNN` — трёхзначный сквозной номер в пределах года
- `slug` — короткий kebab-case

Переименование (через `git mv`, выполнит Координатор):
- `rfc-001-claude-code-routines.md` → `rfc-2026-001-claude-code-routines.md`
- `rfc-003-mem0-subagent-memory.md` → `rfc-2026-003-mem0-subagent-memory.md`
- `rfc-004-coordinator-routing-optimization.md` → `rfc-2026-004-coordinator-routing-optimization.md`
- `rfc-005-cross-audit-departments.md` → `rfc-2026-005-cross-audit-departments.md`

**RFC-002 — пропущен.** Задокументировать в служебном файле `docs/research/rfc/_skipped.md` (прецедент: номер был зарезервирован в ходе ранней черновой работы, но черновик не дошёл до стадии публикации; номер не переиспользовать, чтобы не нарушать хронологию).

Frontmatter-контракт (YAML-блок на первых строках файла):
```yaml
---
id: RFC-2026-NNN
title: <одной строкой>
status: draft | in-review | accepted | rejected | implemented
date: YYYY-MM-DD
author: <роль или имя>
---
```

Для RFC-001 (сейчас без YAML-блока) — добавить; остальные привести к единому набору полей.

### Подзаявка 3 — RFC vs ADR разграничение

**Документ:** `docs/agents/departments/governance.md`

**Изменение:** Новый раздел «RFC vs ADR — границы» со следующим содержанием (резюме):

- **RFC (Request for Comments)** — живой документ исследования. Место: `docs/research/rfc/`. Цель: обсудить идею, собрать контраргументы, выработать рекомендацию. Может быть пересмотрен, переписан, отозван. Владелец: R&I.
- **ADR (Architecture Decision Record)** — immutable запись принятого архитектурного решения. Место: `docs/adr/`. Цель: зафиксировать «что решили, почему, какие альтернативы были отвергнуты» на момент принятия. После статуса `accepted` контент не правится — только заменяется новым ADR со статусом `supersedes: NNNN`. Владелец: Governance (комиссия) + автор-архитектор.
- **Переход RFC → ADR.** Если RFC принят (`status: accepted`) и требует архитектурной фиксации (а не просто organizational change) — Координатор поручает architect/соответствующему Директору подготовить ADR. ADR ссылается на исходный RFC в поле `source_rfc:`. RFC остаётся в `docs/research/rfc/` как исторический документ.
- **RFC без ADR.** Не каждый RFC рождает ADR — если принятое решение процессное (регламент, изменение обязанностей), оно идёт в `CODE_OF_LAWS` или `departments/*.md`, не в ADR.

### Подзаявка 4 — Bandit + pip-audit в CI

**Документ:** `.github/workflows/ci.yml` (вероятно отсутствует — требует создания совместно с infra-director)

**Изменение:** добавить два шага в CI:
- `bandit -r backend/app/ -ll` — статический анализ Python на security-issues уровня medium+.
- `pip-audit` — проверка зависимостей на известные уязвимости (CVE).

Пороги:
- bandit severity ≥ medium, confidence ≥ medium → fail.
- pip-audit любая CVE с CVSS ≥ 7.0 → fail; 4.0–6.9 → warn.

**Governance-роль:** зафиксировать стандарт в `departments/governance.md` (раздел «Security gate CI»). Техническая реализация — в `departments/infrastructure.md` через **отдельную заявку к infra-director**, согласованную комиссией. Эта подзаявка приносит только норматив, не сам workflow.

### Подзаявка 5 — Amendment: SendMessage ≠ запуск работы

**Документ:** `/root/coordinata56/CLAUDE.md` (раздел «Процесс»)

**Изменение:** добавить строку:

> **`SendMessage` не запускает работу у адресата.** Инструмент `SendMessage` доставляет сообщение в inbox субагента, но **не инициирует** у него сессию и не запускает выполнение. Адресат увидит сообщение только при следующем вызове через `Agent` tool. Практический вывод: любое поручение Директору / Head / Worker должно сопровождаться отдельным `Agent`-вызовом; `SendMessage` — это асинхронная почта, не асинхронный триггер задачи. При работе с dormant-агентами это особенно важно: сообщение ляжет в inbox, но работа не начнётся, пока Координатор не активирует сессию через `Agent`.

Обоснование: инцидент обнаружен Координатором 2026-04-18 утром — ранее предполагалось, что `SendMessage` к dormant-агенту достаточен для запуска; фактически сообщения только накапливались в inbox.

---

## Почему

- **RFC-005** одобрен Владельцем как пакет быстрых улучшений по результатам cross-audit 8 департаментов.
- **Подзаявка 5** — предотвращение повторения инцидента потерянных делегирований.

## На что влияет

Документы затрагиваемые прямо:
- 14 ADR (только шапки)
- 4 RFC (переименование + frontmatter)
- `docs/agents/departments/governance.md` — три новых раздела (ADR Lifecycle, RFC vs ADR, Security gate CI)
- `docs/agents/departments/research.md` — ссылка на RFC Naming Convention (одна строка-отсылка)
- `/root/coordinata56/CLAUDE.md` — одна строка в «Процесс»
- `.github/workflows/ci.yml` — отдельная заявка к infra-director

Конфликты с другими документами — анализ поручен `governance-auditor` (см. ниже).

---

## Поручение аудитору

`governance-auditor`, проверь следующие точки:

1. **ADR-frontmatter унификация** — не ломаем ли мы ссылки из `CODE_OF_LAWS.md` ст. 42 или из `agents-map.yaml` (если там есть поля про ADR-статусы).
2. **RFC Naming** — используется ли имя `rfc-001-claude-code-routines.md` где-то в других документах жёсткой ссылкой, которую нужно будет обновить после `git mv`. Поиск по всему `docs/` + `~/.claude/agents/` + `CLAUDE.md`.
3. **RFC vs ADR** — нет ли в Конституции M-OS (docs/CONSTITUTION.md) или Процессуальном кодексе уже существующего определения RFC/ADR, которое мы сейчас продублируем.
4. **Bandit/pip-audit** — совместимо ли с уже существующим security-нормативом (docs/security/), нет ли конфликта по порогам.
5. **SendMessage amendment** — не противоречит ли существующему описанию инструмента в `regulations_addendum_v1.6.md` (паттерн Координатор-транспорт); возможно, там уже есть намёк на асинхронность, который надо уточнить, а не дублировать.

Срок отчёта: в течение текущей рабочей сессии.

---

## Вердикт

Будет заполнен после анализа аудитора и применения правок:
- Подзаявка 1 (ADR Lifecycle): **approved** — правки frontmatter-only, контент не трогается; см. CHANGELOG.md 2026-04-18.
- Подзаявка 2 (RFC Naming): **approved** — переименование через `git mv` выполняет Координатор.
- Подзаявка 3 (RFC vs ADR): **approved** — новый раздел в governance.md.
- Подзаявка 4 (Bandit + pip-audit): **approved в части норматива**; техническая реализация — через отдельную заявку к infra-director.
- Подзаявка 5 (SendMessage amendment): **approved** — срочное правило CLAUDE.md, фиксирующее свойство платформы.
