# docs/agents/ — регламенты, карта и документы системы субагентов

Эта папка — единый дом всего, что связано с ИИ-командой проекта coordinata56: Свод законов, регламенты по уровням и направлениям, паспорт системы, карта, схемы, шаблоны. Здесь живёт «конституция» компании.

---

## Что здесь находится

### Навигационные документы (начни отсюда)

| Файл | Зачем нужен |
|---|---|
| [`CODE_OF_LAWS.md`](CODE_OF_LAWS.md) | Свод законов — общий документ верхнего уровня со ссылками на все регламенты. Читать первым. |
| [`agents-system-map.md`](agents-system-map.md) | Паспорт системы — сколько агентов, что каждый делает, где хранит память. Читать вторым. |
| [`agents-diagrams.md`](agents-diagrams.md) | Визуальные схемы: оргструктура, маршруты задач, делегирование, статусы. |
| [`agents-map.yaml`](agents-map.yaml) | Машинно-читаемая карта всех агентов (для скриптов, линтеров, автогенерации). |

### Регламенты по уровням (что должен делать агент каждого уровня)

- [`regulations/coordinator.md`](regulations/coordinator.md) — L1 Координатор
- [`regulations/director.md`](regulations/director.md) — L2 Директор
- [`regulations/head.md`](regulations/head.md) — L3 Начальник отдела
- [`regulations/worker.md`](regulations/worker.md) — L4 Сотрудник

### Регламенты по направлениям (что должен знать агент своего департамента)

- [`departments/backend.md`](departments/backend.md) — Бэкенд (активен, v1.0)
- [`departments/quality.md`](departments/quality.md) — Качество (активен, v1.0)
- [`departments/governance.md`](departments/governance.md) — Свод законов (активен, v1.0)
- [`departments/research.md`](departments/research.md) — R&I (активен, v1.0 пилот)
- [`departments/frontend.md`](departments/frontend.md) — Фронтенд (dormant 0.1)
- [`departments/design.md`](departments/design.md) — Дизайн (dormant 0.1)
- [`departments/infrastructure.md`](departments/infrastructure.md) — Инфраструктура (dormant 0.1)
- [`departments/legal.md`](departments/legal.md) — Юридические вопросы (dormant 0.1)

### Общефирменные дополнения к регламенту

- [`regulations_draft_v1.md`](regulations_draft_v1.md) — v1.0, исходный свод 17 субагентов
- [`regulations_addendum_v1.1.md`](regulations_addendum_v1.1.md) — скилы, источники знаний, обучение
- [`regulations_addendum_v1.2.md`](regulations_addendum_v1.2.md) — регламент Координатора как CEO
- [`regulations_addendum_v1.3.md`](regulations_addendum_v1.3.md) — процессные уточнения после ретро Фазы 2
- [`regulations_addendum_v1.4.md`](regulations_addendum_v1.4.md) — иерархическая структура 4 уровней
- [`regulations_addendum_v1.5.md`](regulations_addendum_v1.5.md) — балансировка нагрузки и learning loop

### Шаблоны

- [`agent-card-template.md`](agent-card-template.md) — карточка агента (при создании новой роли)
- [`task-routing-template.md`](task-routing-template.md) — паспорт задачи (при приёмке новой задачи от Владельца)
- [`phase-checklist.md`](phase-checklist.md) — чек-лист закрытия фазы
- [`phase-3-checklist.md`](phase-3-checklist.md) — DoD Фазы 3

### Копии должностных инструкций (для durability репозитория)

`subagents/*.md` — копии некоторых `~/.claude/agents/*.md` (зеркало). Делается выборочно — не все субагенты зеркалятся.

---

## Как читать карту агентов

**Сценарий «мне нужно понять, кто за что отвечает»:**
1. Открыть [`agents-system-map.md`](agents-system-map.md) раздел 4 — таблица всех активных агентов.
2. Для конкретной роли — пройти по должностной `~/.claude/agents/<id>.md`.
3. Для визуализации — [`agents-diagrams.md`](agents-diagrams.md) схема Б (департаментская).

**Сценарий «мне нужна машинная обработка»:**
- Читать `agents-map.yaml`. Поля паспорта: `name`, `id`, `level`, `department`, `unit`, `role`, `purpose`, `agent_type`, `status`, `memory_paths`, `notes`. Связи делегации — **только в `delegation-rules.yaml`** (единственный source of truth для графа связей).

**Сценарий «я новый агент, что мне читать?»:**
В порядке приоритета (по v1.4 + CLAUDE.md):
1. `/root/coordinata56/CLAUDE.md` — антипаттерник проекта (автозагрузка)
2. `docs/agents/CODE_OF_LAWS.md` — Свод законов
3. `docs/agents/regulations/<мой уровень>.md` — регламент моего уровня
4. `docs/agents/departments/<моё направление>.md` — регламент моего направления (если не штаб)
5. Релевантные ADR в `docs/adr/`
6. Своя должностная `~/.claude/agents/<мой id>.md`

---

## Как обновлять структуру

**Правка регламента** (CODE_OF_LAWS, regulations/*, departments/*, ADR) — **только через комиссию Governance**:

1. Инициатор заводит заявку в `docs/governance/requests/YYYY-MM-DD-<slug>.md` по шаблону из `departments/governance.md` §«Процесс изменение регламента».
2. `governance-auditor` анализирует заявку на противоречия/дубли/конфликты с ADR.
3. `governance-director` выносит вердикт: approve / reject / request-changes.
4. После approve — правка применяется, запись в `docs/governance/CHANGELOG.md`.

**Быстрый путь** (срочная правка CLAUDE.md после инцидента) — Координатор правит напрямую, но в течение 24 часов подаёт post-factum заявку.

**Правка схем и паспорта** (этот README, agents-map.yaml, agents-system-map.md, agents-diagrams.md, шаблоны) — через обычный PR с ревью, не через комиссию (это не регламент, а навигационные документы).

---

## Как добавить нового агента

1. Определиться с ролью: **нужна ли она на самом деле** или есть кто-то, кто уже это делает. Принцип v1.4: «нет работы — нет роли». Если нет явной постоянной работы — не создавать.
2. Заполнить карточку по [`agent-card-template.md`](agent-card-template.md).
3. Если это **новая постоянная роль** — завести заявку в `docs/governance/requests/YYYY-MM-DD-new-role-<slug>.md`. Получить approve от `governance-director`.
4. Создать файл `~/.claude/agents/<id>.md` с фронтматтером и содержанием карточки (минимум: `name`, `description`, `tools`, `model`, + тело с обязательной секцией «Привязка к регламенту»).
5. Если применимо — добавить копию в `docs/agents/subagents/<id>.md` для репозитория.
6. Обновить `agents-map.yaml` — добавить запись агента.
7. Обновить `agents-system-map.md` — добавить в нужную таблицу.
8. Обновить `agents-diagrams.md` — добавить узел в схемы Б (по департаменту) и А (общая).
9. Коммит: `docs(agents): add agent <id> per Governance request YYYY-MM-DD-<slug>`.

---

## Как использовать Mermaid-схемы

1. Просмотр в GitHub: Markdown с ```mermaid``` рендерится автоматически.
2. Локально: VS Code + расширение «Markdown Preview Mermaid Support».
3. Онлайн: https://mermaid.live — копипаст блока, визуализация + экспорт PNG/SVG.
4. Валидация: `mermaid-cli` (`npm i -g @mermaid-js/mermaid-cli`, команда `mmdc -i input.md`).

**Перед коммитом** — убедиться, что схемы валидны. Mermaid ругается на неэкранированные спецсимволы в подписях — `(`, `)`, `[`, `]` внутри текста узла безопасны только в кавычках.

---

## Как понять, кто отвечает за задачу

1. Открыть `agents-system-map.md` раздел 6 — стандартные правила «кто делегирует кому».
2. Определить tier задачи (XS / S / M / L).
3. **Все задачи идут через Директора направления** — даже XS. Координатор передаёт задачу Директору, Директор решает как распределить внутри отдела (Head → Worker).
4. Исключение — **Советники** (advisory): architect, analyst, legal, tutor и т.д. К ним Координатор обращается напрямую (это консультация, не задача).
5. Если задача затрагивает несколько департаментов — см. схему Г «делегирование» в `agents-diagrams.md` + правила кросс-вертикальной коммуникации в `CODE_OF_LAWS.md` статья 13.

---

## Как не сломать существующую систему

1. **Не удаляй файлы из `~/.claude/agents/`** — это должностные. Даже если агент dormant, файл нужен для «знания регламента». Удаление — только через комиссию Governance.
2. **Не переименовывай id агентов** — они используются как идентификаторы в `Agent`-вызовах из основного Claude. Переименование = breaking change для всего кода, который использует `subagent_type=<id>`.
3. **Не коммитить regulation-изменения без заявки в комиссию** — иначе первый же аудит `governance-auditor` выловит нарушение процесса.
4. **Не выдавать агентам права шире, чем им нужно** — в `tools:` фронтматтера должен быть минимум. Например, `reviewer` имеет `Read, Write, Grep, Glob` — но не `Edit`, потому что ревьюер не правит код.
5. **Не литералить секреты** в должностных или карточках — даже для примера. Всегда `<placeholder>` или `secrets.token_urlsafe(16)`.
6. **Перед коммитом** — `reviewer` на staged diff, по правилу v1.3 §1.

---

## Версия и история

| Версия | Дата | Что изменилось |
|---|---|---|
| 1.0 | 2026-04-16 | Первая редакция: README + паспорт + yaml-карта + диаграммы + 2 шаблона. Bootstrap системы документации агентов. |
