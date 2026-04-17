# Governance Changelog (журнал изменений регламента)

Ведёт `governance-director`. Каждая правка утверждённая комиссией — отдельная запись. Append-only снизу.

## Формат записи
```
## YYYY-MM-DD — <короткое описание>
- **Заявка:** docs/governance/requests/YYYY-MM-DD-<slug>.md
- **Документ:** <путь>
- **Изменение:** <что было → что стало>
- **Мотивация:** <инцидент / RFC / прямое указание Владельца>
- **Вердикт:** approved / rejected / amended
- **Аудитор:** clean / warnings (список)
```

---

## 2026-04-15 — Создание отдела Governance (bootstrap)
- **Заявка:** bootstrap (прямое указание Владельца, Telegram msg 583)
- **Документ:** `docs/agents/departments/governance.md` v1.0
- **Изменение:** отдел создан, назначены `governance-director` и `governance-auditor`
- **Мотивация:** «нужен департамент, который следит за регламентом … все изменения регламента проходят комиссию»
- **Вердикт:** approved (bootstrap — без комиссии, т.к. создаётся сама комиссия)
- **Аудитор:** pending (первый аудит — в течение недели после активации)

## 2026-04-15 — Создание отдела R&I (bootstrap)
- **Заявка:** bootstrap (прямое указание Владельца, Telegram msg 582)
- **Документ:** `docs/agents/departments/research.md` v1.0
- **Изменение:** отдел создан, назначены `ri-director`, `ri-scout`, `ri-analyst`
- **Мотивация:** непрерывный сенсинг внешних источников → пилот → внедрение
- **Вердикт:** approved (bootstrap)
- **Аудитор:** pending

## 2026-04-15 — Sync-1: синхронизация Свода и регламентов по итогам первого аудита
- **Заявка:** `docs/governance/requests/2026-04-15-sync-1-bootstrap-sync.md`
- **Документы:**
  - `docs/agents/CODE_OF_LAWS.md` — преамбула (приоритет коллизий → ссылка на governance.md), ст. 30 (+governance, +research, статусы backend/quality → v1.0), Книга V (ст. 49 переформулирована, ст. 50–54 удалены), ст. 46 (+ADR 0004 Amendment), Приложение А (+governance, +research)
  - `docs/agents/regulations/director.md` — ст. 12.4 (триггеры эскалации)
  - `docs/agents/departments/governance.md` — новые разделы «Поведенческий аудит», «SLA комиссии»
  - `docs/agents/regulations_addendum_v1.1.md` — статус ✅ утверждено Владельцем 2026-04-11
  - `docs/agents/regulations_addendum_v1.2.md` — статус ✅ утверждено Владельцем 2026-04-11
  - `docs/agents/regulations_addendum_v1.3.md` — статус ✅ утверждено Владельцем 2026-04-15
  - `~/.claude/agents/reviewer.md` — футер обновлён 2026-04-16: ссылки на `CLAUDE.md` проекта, `CODE_OF_LAWS.md`, `regulations/worker.md`, `departments/quality.md`, v1.3 §1, ADR 0005/0006/0007
  - `~/.claude/agents/memory-keeper.md` — футер обновлён 2026-04-16: ссылки на `CLAUDE.md` проекта, `CODE_OF_LAWS.md`, исключение Координатора по v1.2 §A4.7, глобальный `~/.claude/CLAUDE.md` раздел «Память»
- **Изменение:** пакет правок W1, W2, W3, W4, W5, M3, M4, M5, M7, M8
- **Мотивация:** отчёт `docs/governance/audits/weekly/2026-04-15-first-audit.md`, одобрено Владельцем (Telegram msg 606, msg 618 «делай всё что они выявили»)
- **Вердикт:** approved Координатором (bootstrap комиссии — Директор Governance не подгружен)
- **Аудитор:** clean (W1–W5, M3–M5, M7, M8 закрыты; остаются минорные M1, M2, M6, M10 — обработать во втором аудите)

## 2026-04-16 — Карта системы субагентов + bootstrap dormant-агентов
- **Заявка:** `docs/governance/requests/2026-04-16-dormant-agents-bootstrap.md`
- **Документы (новые):**
  - `docs/agents/agents-system-map.md` — паспорт системы субагентов v1.0
  - `docs/agents/agents-map.yaml` — машинно-читаемая карта всех 48 файлов (27 активных + 21 dormant + 5 builtin Claude Code в примечаниях)
  - `docs/agents/agents-diagrams.md` — 6+ mermaid-схем (оргструктура, 5 департаментских, маршрут задачи, делегирование, статусы, Governance+R&I цикл)
  - `docs/agents/agent-card-template.md` — шаблон карточки агента
  - `docs/agents/task-routing-template.md` — шаблон паспорта задачи
  - `docs/agents/README.md` — навигация по папке docs/agents/
- **Документы (созданы стабы в `~/.claude/agents/` — 21 файл):**
  - Dormant директора (4): `frontend-director`, `design-director`, `infra-director`, `legal-director`
  - Dormant начальники (8): `integrator-head`, `frontend-head`, `ux-head`, `visual-head`, `content-head`, `devops-head`, `db-head`, `legal-head`
  - Dormant сотрудники (9): `ux-researcher`, `ux-designer`, `ui-designer`, `accessibility-auditor`, `ux-writer`, `copywriter`, `legal-researcher`, `legal-analyst`, `legal-copywriter`
- **Изменение:** Практика dormant-агентов: раньше = «описан в регламенте, файла нет». Теперь = «файл создан заранее, status: dormant, задачи не получает до активации направления». Прямое указание Владельца Telegram msg 629.
- **Мотивация:** Владелец хочет визуализированную формализованную систему агентов (msg 625+626). Plus: при активации направления (Фаза 4, Фаза 9, юр-активация) нет периода «подготовки роли» — просто снимаем флаг dormant.
- **Вердикт:** approved (прямое указание Владельца).
- **Аудитор:** pending — следующий еженедельный аудит (2026-04-22) должен подтвердить консистентность yaml ↔ файлов в `~/.claude/agents/` ↔ regulations/ ↔ CODE_OF_LAWS.

## 2026-04-16 — Amendment v1.4 §5: строгая цепочка делегирования
- **Заявка:** `docs/governance/requests/2026-04-16-amendment-v14-strict-chain.md`
- **Документы:**
  - `/root/coordinata56/CLAUDE.md` — правило «Президент → Директор → Head → Worker» добавлено в раздел «Процесс»
  - `~/.claude/agents/frontend-director.md` — dormant → active-supervising
  - `~/.claude/agents/design-director.md` — dormant → active-supervising
  - `~/.claude/agents/infra-director.md` — dormant → active-supervising
  - `~/.claude/agents/legal-director.md` — уточнено: остаётся dormant, юр-вопросы у advisor `legal` (штаб вне иерархии)
  - `docs/agents/agents-map.yaml` — обновлены статусы 3 Директоров + мета note_on_strict_chain
  - `docs/agents/agents-system-map.md` — раздел «L2 Директора», правило строгой цепочки
- **Изменение:** Координатор (Президент) передаёт задачи только Директорам. Маршруты XS→Worker и S→Head→Worker отменены. Активированы 3 ранее dormant-Директора для обеспечения цепочки. Советники остаются исключением (вне иерархии).
- **Мотивация:** прямое указание Владельца (Telegram msg 665 «ты президент ты можешь ставить задачу только директорам»).
- **Вердикт:** approved (Owner directive).
- **Аудитор:** pending — следующий аудит (2026-04-22) проверит: (1) ни один task-routing-template не нарушает цепочку, (2) regulations_addendum_v1.4.md §5 обновлён в той же редакции.

## 2026-04-16 — v1.6 Координатор-транспорт + post-factum инцидент ri-director
- **Заявка:** `docs/governance/requests/2026-04-16-v16-coordinator-transport.md`
- **Документы (новые):**
  - `docs/agents/regulations_addendum_v1.6.md` v1.0 — паттерн Координатор-транспорт (как реализовать иерархию в Claude Code, где субагенты не могут вызывать друг друга)
  - `~/.claude/skills/delegate-chain/SKILL.md` — переиспользуемый скил с шаблонами промптов Координатора по 8 стадиям цепочки
  - `docs/governance/incidents/2026-04-16-ri-director-sensing.md` — post-factum фиксация инцидента
- **Документы (правки):**
  - `/root/coordinata56/CLAUDE.md` — добавлена строка «Паттерн Координатор-транспорт (v1.6)» в раздел «Процесс»
- **Изменение:** Вводится формальный паттерн: Координатор последовательно делает Agent-вызовы по стадиям (Брифинг у Директора → Распределение у Head → Исполнение Workers → Ревью Head → Вердикт Директора → Pre-commit reviewer → Коммит). Новое жёсткое правило: Координатор формулирует Директору «напиши бриф для <role>», не «сделай <work>». Директор получает право и обязанность отказать при неверной формулировке.
- **Мотивация:** Инцидент 2026-04-16 (ri-director выполнил работу scout'а на задаче «проверь свежие находки»). Владелец msg 733: «директор не искал сам а лишь поручал». msg 748: «реализовывай путь 1 и начинай писать новый регламент». Техническое ограничение Anthropic: «subagents cannot spawn other subagents» (обе платформы — Claude Code и Managed Agents).
- **Вердикт:** approved (Owner directive).
- **Аудитор:** pending — через 2 еженедельных цикла без повторов инцидента закрывается.

## 2026-04-16 — P0-багфикс YAML-синтаксиса трёх файлов кодекса (Codex audit)
- **Заявка:** `docs/governance/requests/2026-04-16-yaml-syntax-fix-codex.md`
- **Документы:**
  - `docs/agents/delegation-rules.yaml` — 50 записей обёрнуты под ключ `agents:`, indent +2 (было: sequence на корневом уровне рядом с `meta:` — невалидный YAML)
  - `docs/agents/agents-map.yaml` — 55 записей обёрнуты под ключ `agents:`, indent +2, + закавычен `tutor.purpose` (значение с `:` внутри)
  - `docs/agents/task-event-log.schema.yaml` — 2 строки закавычены (значения с `:` внутри — `Формат: ...`, `Коротко: ...`)
- **Изменение:** три YAML-файла кодекса стали валидны для `yaml.safe_load`. Регламент как текст (поля, значения, комментарии) **не изменён** — правка чисто синтаксическая, diff-стат +1269 / −1267 (дельта +2 = два новых ключа `agents:`). Счётчики сохранены: 50 связей делегирования, 55 паспортов, 8 событий схемы.
- **Мотивация:** внешний аудит ChatGPT Codex (Telegram 2026-04-16 msg 780) выявил 3 ParserError/ScannerError. Любой автоматический потребитель кодекса (будущий CI-валидатор, дашборд, обучение субагентов на паспортах) падал на парсинге. Блокер для автоматизации.
- **Вердикт:** approved (governance-director, прецедент: P0-багфикс формата машиночитаемого файла, не меняющий ни одного поля, идёт без отдельного поручения аудитору — с обязательной верификацией парсером в теле заявки и reviewer-проверкой перед коммитом).
- **Аудитор:** skipped для самой правки (обоснование в вердикте). Отдельный трек — прицельный аудит drift'а `delegation-rules.yaml` (50) ↔ `agents-map.yaml` (55), поручено `governance-auditor` как новая P1-задача (результат ожидается в виде либо заявки на синхронизацию, либо обоснованного списка исключений builtin Claude Code / Советников с пометкой в обоих файлах).

## 2026-04-16 — Managed Agents (Путь 3) отложен
- **Заявка:** не оформлялась — отложено прямым решением Владельца (msg 748 «останови managed»)
- **Документы:**
  - `managed_agents/STATUS.md` — пояснение, код сохранён для будущего использования при необходимости параллелизма
  - `.gitignore` — исключены `managed_agents/.venv/` и `managed_agents/.env`
- **Изменение:** Путь 3 (переход на Anthropic Managed Agents API) остановлен. Причина: доп. изучение показало, что Managed Agents имеет то же ограничение одноуровневой делегации, что и Claude Code, — путь не решал бы проблему вложенности сам по себе.
- **Мотивация:** Корректная проверка документации Anthropic (msg 746-747).
- **Вердикт:** прямое решение Владельца.
- **Статус:** код работы сохранён в `managed_agents/` для возможно��о использования в будущем, ког��а понадобится паралле��изм сессий.

## v1.1 — 2026-04-17

### Принято
- ADR 0009 Pod-архитектура M-OS (approve 4/4)
- ADR 0010 Таксономия субагентов M-OS (approve 4/4, 5 типов)
- CODE_OF_LAWS v1.0 → v1.1: Книга VII + правки ст. 1,2,9,29-30,46 + Приложение А
- Миграция docs в pod-структуру: phases/stories/wireframes/specs → docs/pods/cottage-platform/
- Bulk-правка 48 frontmatter: добавлено поле agent_type
- ADR 0008 amendment: coordinata56-pod → cottage-platform-pod

### Источники
- Заявка: docs/governance/requests/2026-04-16-m-os-reframing.md
- Аудит: docs/governance/audits/2026-04-16-adr-0009-0010-audit.md
- Вердикт: docs/governance/verdicts/2026-04-16-m-os-reframing-verdict.md
- Решения Владельца: Telegram msg 861, 867, 869

## Sync-2 — 2026-04-17

### Принято
- CODE_OF_LAWS ст. 9: 6 → 9 Директоров (добавлены governance, R&I, Innovation)
- CODE_OF_LAWS ст. 30: добавлен 9-й департамент Innovation
- CODE_OF_LAWS ст. 46: добавлен ADR 0011 (утверждён), ADR 0012 (черновик)
- Граница R&I vs Innovation зафиксирована в ст. 30

### Источники
- Governance audit 2026-04-17: P1-01, P1-02, P1-03, P2-06, P2-07
- Решение Владельца: Telegram msg 1005

## 2026-04-17 — CODE_OF_LAWS v1.1 -> v2.0: реформа под Конституцию M-OS
- **Заявка:** прямая задача Координатора (реализация ст. 6.3 Конституции — устранение противоречий в 30-дневный срок)
- **Документы (правки):**
  - `docs/agents/CODE_OF_LAWS.md` — полная перезапись v1.1 -> v2.0
  - `docs/agents/regulations_draft_v1.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.1.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.2.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.3.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.4.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.5.md` — пометка SUPERSEDED
  - `docs/agents/regulations_addendum_v1.6.md` — пометка SUPERSEDED
- **Изменение:**
  - Преамбула: добавлена ссылка на Конституцию M-OS с приоритетом
  - Книга I: ст. 1-8 (определение, миссия, принципы) и Книга VII (pod-архитектура, ст. 57-61) мигрированы в Конституцию — заменены ссылочными статьями 1-9
  - Книги II-VI: операционное содержимое сохранено, статьи перенумерованы 10-47
  - Добавлена ссылка на Процессуальный кодекс M-OS (docs/PROCEDURAL_CODE.md)
  - Добавлен 9-й департамент Innovation в таблице ст. 26
  - ADR 0011, 0012 добавлены в список ст. 42
  - Карта документов в Приложении А обновлена: включает иерархию уровней 0-6, Процессуальный кодекс, superseded-блок
  - Глоссарий: добавлен термин Superseded, ссылка на полный глоссарий Конституции
  - Addendum v1.0-v1.6 помечены SUPERSEDED в шапке каждого файла
- **Мотивация:** ст. 6.3 Конституции M-OS: «Противоречия между ранее принятыми документами и Конституцией устраняются Координатором в срок не более 30 дней». Реализация Варианта В из плана реформы правовой системы.
- **Вердикт:** approved (governance-director). Мажорная версия — требует утверждения Владельцем (ст. 65.2 Конституции).
- **Аудитор:** pending — проверить: (1) все ссылки на статьи Конституции корректны, (2) ни одно операционное правило не потеряно при миграции, (3) ссылки на разделы addendum из CODE_OF_LAWS ведут на существующие разделы в superseded-файлах.

## 2026-04-17 — CODE_OF_LAWS v2.1: статьи 45а/45б — правило интеграционного шлюза (финализация)
- **Заявка:** `docs/governance/requests/2026-04-17-integration-gate-rule.md` — статус изменён на approved
- **Документы:**
  - `docs/agents/CODE_OF_LAWS.md` v2.0 → v2.1: добавлен Раздел V Книги IV «Правило интеграционного шлюза» — статьи 45а (запрет живых интеграций до production-gate; три обязательных столпа) и 45б (обязательный доклад Владельцу о предложениях новых интеграций)
  - `docs/agents/regulations/coordinator.md` v1.1 → v1.2: статья 11.9 дополнена ссылкой на три столпа production-gate согласно ст. 45а; версия документа обновлена
  - `docs/pods/cottage-platform/m-os-1-plan.md` v1.1 → v1.2: добавлены разделы «Production-gate критерии (три обязательных столпа)» и «Активация frontend-director — обязательное условие запуска M-OS-1.1»; раздел «Зависимость — юрист» расширен до трёх столпов; Риск 2 и сноска по PWA обновлены; governance-вопросов 0
- **Изменение:** Production-gate расширен с одного юридического чек-листа до трёх обязательных столпов: юр (F-02/F-03/F-05/F-07) + внешний security-аудит + staging симуляции. Активация frontend-director переведена из рекомендации в обязательное предварительное условие запуска M-OS-1.1.
- **Мотивация:** финальные ответы Владельца на governance-вопросы (Telegram msg 1111, 2026-04-17). Три ответа: (1) формулировки 45а/45б утверждены; (2) production-gate — три столпа; (3) PWA — обязательное условие M-OS-1.1.
- **Вердикт:** approved (governance-director; минорная версия Свода, реализует прямые решения Владельца)
- **Аудитор:** clean — противоречий не выявлено. Три столпа production-gate не конфликтуют с Конституцией ст. 8 (ПДн): запрет работает в пользу защиты ПДн, а не против неё. С ADR 0012 (Orchestration Layer) конфликта нет: ADR технический, ст. 45а — процессная норма доступа. Примечание: детальный чек-лист staging-симуляций (столп 3) формируется отдельной задачей перед M-OS-2 — этот пробел в плане зафиксирован явно, не является уязвимостью.

## 2026-04-17 — Обновление плана M-OS-1 (v1.1) + заявка на правило интеграционного шлюза
- **Заявка:** `docs/governance/requests/2026-04-17-integration-gate-rule.md`
- **Документы (применены):**
  - `docs/pods/cottage-platform/m-os-1-plan.md` v1.0 → v1.1: новые сроки M-OS-1.1 (3 нед. → 7-8 нед.), два Event Bus, полный admin-UI конструктор, per-company лимиты (`company_settings`), Telegram как единственная живая интеграция до production-gate, Риски 4 и 5, уточнение DoD п. 2 и п. 8
  - `docs/agents/regulations/coordinator.md` v1.0 → v1.1: добавлены ст. 4а (формат доклада о предложениях интеграций) и ст. 11.9 (запрет активации без решения Владельца)
- **Документы (ожидают вердикта Владельца):**
  - `docs/agents/CODE_OF_LAWS.md` — новые ст. 45а и 45б (Книга IV, Раздел V); тексты в заявке, в Свод не вносятся до подтверждения Владельцем
- **Мотивация:** прямые решения Владельца (Telegram msg 1094, 1101, 1103, 1105, 2026-04-17)
- **Вердикт (plan + coordinator.md):** approved (governance-director; операционные правки, реализующие прямые решения Владельца)
- **Вердикт (CODE_OF_LAWS ст. 45а/45б):** pending — ожидает подтверждения Владельцем
- **Аудитор:** pending — проверить конфликт новых ст. 45а/45б с Конституцией ст. 8 (ПДн) и ADR 0012 (Orchestration Layer)
