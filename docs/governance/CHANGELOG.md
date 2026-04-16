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

## 2026-04-16 — Managed Agents (Путь 3) отложен
- **Заявка:** не оформлялась — отложено прямым решением Владельца (msg 748 «останови managed»)
- **Документы:**
  - `managed_agents/STATUS.md` — пояснение, код сохранён для будущего использования при необходимости параллелизма
  - `.gitignore` — исключены `managed_agents/.venv/` и `managed_agents/.env`
- **Изменение:** Путь 3 (переход на Anthropic Managed Agents API) остановлен. Причина: доп. изучение показало, что Managed Agents имеет то же ограничение одноуровневой делегации, что и Claude Code, — путь не решал бы проблему вложенности сам по себе.
- **Мотивация:** Корректная проверка документации Anthropic (msg 746-747).
- **Вердикт:** прямое решение Владельца.
- **Статус:** код работы сохранён в `managed_agents/` для возможного использования в будущем, когда понадобится параллелизм сессий.
