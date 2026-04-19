# Precheck к 2-му еженедельному аудиту регламента — 2026-04-22

**Автор:** governance-director
**Дата подготовки:** 2026-04-18
**Статус:** precheck (подготовительный документ; не отчёт аудита)
**Плановая дата аудита:** 2026-04-22 (понедельник, согласно `departments/governance.md` «Периодический аудит»)
**Первый аудит:** `docs/governance/audits/weekly/2026-04-15-first-audit.md`

## Назначение документа

Этот precheck собирает на одном листе (а) статус закрытия находок первого аудита, (б) перечень новых нормативных и квази-нормативных артефактов, появившихся за неделю 16–18 апреля, (в) кандидатов в новые нарушения/замечания, (г) предлагаемую повестку и (д) состав привлекаемых агентов. Документ служит брифом для `governance-auditor` при старте аудита 2026-04-22 и чек-листом для Координатора при приёмке отчёта.

---

## 1. Статус закрытия находок первого аудита

### 1.1 W-находки (P1)

| # | Находка (кратко) | Статус | Подтверждение | Примечание |
|---|---|---|---|---|
| W1 | CODE_OF_LAWS ст. 30 отставал от departments/README на 2 отдела (+governance, +research); статусы backend/quality | **закрыт** | CHANGELOG запись Sync-1 от 2026-04-15 (правка ст. 30, Приложение А) | нужна проверка: не появились ли с 2026-04-15 новые департаменты (Innovation в Sync-2 — добавлен 2026-04-17, 9-й) |
| W2 | Книга V Свода описывала «dormant compliance» параллельно отделу Governance | **закрыт** | CHANGELOG Sync-1 — Книга V переформулирована, ст. 50-54 удалены | clean, возврата нет |
| W3 | Триггеры эскалации «рутинное/серьёзное» не прописаны в regulations/director.md ст. 12 | **закрыт** | CHANGELOG Sync-1 — ст. 12.4 (триггеры эскалации) | clean |
| W4 | governance-auditor.md vs departments/governance.md расходились по видам аудита (поведенческий отсутствовал в departments) | **закрыт** | CHANGELOG Sync-1 — добавлены разделы «Поведенческий аудит», «SLA комиссии» | clean |
| W5 | Приоритет коллизий в departments/governance.md vs преамбула Свода (обратный приоритет «первоисточник бьёт Свод») | **закрыт** | CHANGELOG Sync-1 — преамбула Свода обновлена, приоритет → ссылка на governance.md | clean; дополнительно CODE_OF_LAWS v1.1 → v2.0 (2026-04-17) окончательно переопределил иерархию через Конституцию |

### 1.2 M-находки (P2, минорные)

| # | Находка (кратко) | Статус | Примечание |
|---|---|---|---|
| M3 | Статусы ⏳ черновик у regulations_addendum_v1.1, v1.2 | **закрыт** | Sync-1: проставлено «✅ утверждено Владельцем 2026-04-11» |
| M4 | Статус ⏳ у regulations_addendum_v1.3 | **закрыт** | Sync-1: «✅ утверждено Владельцем 2026-04-15»; дополнительно v1.3 переведён в SUPERSEDED при реформе v2.0 |
| M5 | CODE_OF_LAWS ст. 46 не отражал ADR 0004 Amendment | **закрыт** | Sync-1: ст. 46 обновлена, упомянут Amendment |
| M7 | reviewer.md ссылался на regulations_draft_v1.md + v1.1 + v1.2 (устарело при v1.4/v1.5) | **закрыт** | Sync-1: футер обновлён 2026-04-16 (CLAUDE.md проекта, CODE_OF_LAWS, regulations/worker.md, departments/quality.md, v1.3 §1, ADR 0005/0006/0007) |
| M8 | memory-keeper.md — та же проблема + неявный обход по v1.2 §A4.7 | **закрыт** | Sync-1: футер обновлён, исключение Координатора зафиксировано |
| M1 | regulations/head.md — «11 Начальников», при полной активации ≥12 | **открыт** | ожидал обработки во втором аудите; переформулировка после реформы CODE_OF_LAWS v2.0 могла сделать находку неактуальной — требует перепроверки |
| M2 | CODE_OF_LAWS ст. 9 — цифры 11 Head / 22+ Worker без разбивки | **открыт** | аналогично M1; в v2.0 ст. 9 мигрирована в Конституцию — проверить актуальность |
| M6 | Ссылка на https://github.com/m-creator-holding/coordinata56 в coordinator.md | **открыт** | в памяти пользователя reference_docs_mirror фиксирует публичное зеркало; личный репозиторий — проверить |
| M10 | research.md позиционирует отдел, Свод ст. 30 не уточнял статус «штабного/производственного» | **открыт** | после добавления 9-го Innovation (Sync-2) картина ещё усложнилась — нужен отдельный раздел классификации штаб/производство |

**Итог:** 10 из 14 находок первого аудита закрыты (все W1–W5 + все M из Sync-1). Остаются M1, M2, M6, M10 — их нужно обработать в 2026-04-22.

---

## 2. Новые нормативные и квази-нормативные артефакты за неделю 16–18 апреля

### 2.1 Артефакты, прошедшие полный governance-цикл (CHANGELOG-запись есть)

| Артефакт | Дата | CHANGELOG-запись | Тип вердикта |
|---|---|---|---|
| `docs/agents/agents-system-map.md`, `agents-map.yaml`, `agents-diagrams.md`, шаблоны | 2026-04-16 | «Карта системы субагентов + bootstrap dormant» | approved (Owner directive) |
| Amendment v1.4 §5 «строгая цепочка делегирования» | 2026-04-16 | «Amendment v1.4 §5» | approved (Owner directive) |
| `regulations_addendum_v1.6.md` + `skills/delegate-chain/SKILL.md` + incident ri-director | 2026-04-16 | «v1.6 Координатор-транспорт» | approved (Owner directive) |
| YAML-багфикс `delegation-rules.yaml`, `agents-map.yaml`, `task-event-log.schema.yaml` | 2026-04-16 | «P0-багфикс YAML-синтаксиса» | approved (governance-director), аудит skipped с обоснованием |
| Managed Agents (Путь 3) — отложен | 2026-04-16 | «Managed Agents (Путь 3) отложен» | прямое решение Владельца |
| ADR 0009, ADR 0010, CODE_OF_LAWS v1.0 → v1.1, миграция docs в pod | 2026-04-17 | «v1.1 — 2026-04-17» | approved 4/4 (комиссия) |
| CODE_OF_LAWS ст. 9/ст. 30/ст. 46 — Sync-2 (+ Innovation, +ADR 0011/0012) | 2026-04-17 | «Sync-2 — 2026-04-17» | approved по решению Владельца msg 1005 |
| CODE_OF_LAWS v1.1 → v2.0 (миграция под Конституцию) | 2026-04-17 | «CODE_OF_LAWS v1.1 → v2.0» | approved (governance-director), **мажорная, формально требует утверждения Владельцем по ст. 65.2 Конституции — проверить, получено ли** |
| CODE_OF_LAWS v2.0 → v2.1 (ст. 45а/45б, интеграционный шлюз) | 2026-04-17 | «CODE_OF_LAWS v2.1» | approved (governance-director) по msg 1111 |
| Документальные правки по внешнему аудиту + инцидент ст. 45а | 2026-04-17 | «Устранение противоречий по результатам внешнего аудита» | approved (governance-director) |
| Обновление плана M-OS-1 v1.1 + ст. 4а, 11.9 coordinator.md | 2026-04-17 | «Обновление плана M-OS-1» | approved (governance-director) |
| ADR 0013 approved + amendment alembic.command | 2026-04-18 | «ADR 0013 approved (force-majeure)» | approved Координатор force-majeure → ratified governance-director |
| RFC-005 Top-10 quick-wins pack | 2026-04-18 | «RFC-005 Top-10 quick-wins» | approved Координатор force-majeure → ratified conditionally |
| backend.md v1.0 → v1.1 | 2026-04-18 | «backend.md v1.0 → v1.1» | approved (backend-director departmental + Координатор) |
| design.md v0.1 → v1.0 | 2026-04-18 | «design.md v0.1 → v1.0» | approved (design-director departmental + Координатор) |
| ADR 0004 Amendment (CompanyScopedService предикаты) | 2026-04-18 | «ADR 0004 Amendment» | approved Координатор force-majeure → ratified governance-director |
| Ретроспективный вердикт по 4 force-majeure заявкам | 2026-04-18 | «Ретроспективный вердикт» | all 4 ratified |

### 2.2 Артефакты за 2026-04-18 без CHANGELOG-записи (требуют governance-оценки на аудите)

Это ядро риска «параллельного спринта» — 14+ документов за час, governance видит их впервые в сводном виде:

| Артефакт | Путь | Автор | Статус | Риск |
|---|---|---|---|---|
| ADR 0016 Domain Event Bus (draft) | `docs/adr/0016-domain-event-bus.md` | architect (советник) | proposed | подписи «governance-director, затем Владелец» — требует формального governance-прохода (заявка + аудит); обратите внимание — есть пропуск нумерации: ADR 0015 отсутствует в файлах, только 0014 и 0016 |
| ADR 0014 Anti-Corruption Layer | `docs/adr/0014-anti-corruption-layer.md` | — | нужно проверить статус | упоминается в `m-os-1-foundation-adr-plan.md` v3.1 и в closure-draft инцидента ст. 45а; в CHANGELOG до 2026-04-18 approve не фиксировался — проверить, ratified или proposed |
| ADR 0022 Analytics Reporting Data Model | `docs/adr/0022-analytics-reporting-data-model.md` | — | новый файл | нарушение нумерации (пропуски 0015, 0017-0021); governance-audit нужен: (а) причина нумерационного скачка, (б) статус |
| Design System v1.0 (draft) | `docs/design/design-system-v1.md` | design-director | черновик, ждёт RFC-006 (20-21 апр) и UI/UX axis (22 апр) | квази-норматив (токены цвета/типографики обязательны к применению frontend); формально — departmental artifact design, но содержит нормативные утверждения «в коде только semantic-токены, никогда primitive» → требует либо ADR, либо явной пометки «нормативно для frontend-директората» |
| Design System Initiative brief | `docs/design/design-system-initiative-brief.md`, `design-system-initiative.md` | design-director | статус и вердикт Координатора не проверены | часть RFC-006 (frontend stack + design system) |
| Legal PD consent flow, user profile fields | `docs/pods/cottage-platform/stories/legal-pd-consent-flow.md`, `legal-pd-user-profile-fields.md` | — | User Stories (не регламент) | не требуют governance-review напрямую; но в закрытии PR #2 затронут ФЗ-152 C-1 блокер — нужно убедиться что Legal PD skeleton-first зафиксирован процессуально (см. §3.3) |
| Code audit interim | `docs/reviews/code-audit-interim-2026-04-18.md` | quality-director | interim-отчёт, не pre-commit review | не требует governance-review (в скоуп исключений `docs/reviews/*` по departments/governance.md); но содержит замечания, которые могут породить заявки |
| RFC-004 Hooks Phase 0 plan | `docs/research/rfc/rfc-004-hooks-phase-0-plan.md` | ri-director | plan-draft | приложение к RFC-2026-004 «Оптимизация маршрутизации»; упоминает governance-director как reviewer DoD — формально требует вердикта до старта пилота (2 дня backend-dev); governance-audit нужен для валидации DoD и критериев acceptance |
| Closure-draft инцидента ст. 45а | `docs/governance/incidents/2026-04-17-external-audit-art45a-violation-closure-draft.md` | governance-director (самоподготовил) | черновик, ожидает коммита ADR-0014 в main для финализации | внутренний документ, не требует отдельного governance-review; но содержит три кандидатные формулировки для правок (CODE_OF_LAWS / departments/backend / departments/research / CLAUDE.md / departments/governance) — каждая должна пройти отдельной заявкой |
| Pod-миграция pr2-wave1-rbac-v2-pd-consent task | `docs/pods/cottage-platform/tasks/pr2-wave1-rbac-v2-pd-consent.md` | — | task-file pod | не регламент, но затрагивает ФЗ-152 и production-gate — проверить соответствие ст. 45а |
| Inbox usage policy v1.0 | `docs/agents/inbox-usage.md` | Координатор | зафиксирован 2026-04-18 | тип: policy, находится в `docs/agents/` — формально попадает в governance-scope. **CHANGELOG-записи нет.** Требует ретроспективного approve на 2026-04-22 |

### 2.3 Документы, уже находившиеся в обработке (контекст)

- RFC-005 (cross-audit 8 департаментов) — одобрен Владельцем (msg 1271), оформлен в ratified заявке 2026-04-18; детали реализации пунктов 2, 3, 4 в документации — проверить `departments/governance.md` (разделы «ADR Lifecycle», «RFC vs ADR»), `departments/research.md` (RFC Naming).
- RFC-004 «Оптимизация маршрутизации» — Phase 0 Hooks plan готов (см. выше).
- RFC-006 «Frontend stack + Design System» — упомянут в шапке Design System v1.0 («ждёт RFC-006 20–21 апреля») — в папке `docs/research/rfc/` файла RFC-006 **нет**; оформлен как brief в `docs/design/`? Это несогласованность — проверить наличие/статус.
- RFC-007 «Department Automation & Acceleration» — согласно weekly digest 2026-04-18 §3 «не начат, файл отсутствует», задача отправлена SendMessage'ом в inbox → застряла по инциденту Inbox-архив (см. §3.1).

---

## 3. Возможные новые нарушения и замечания для анализа

### 3.1 Inbox-архив: RFC-006/RFC-007/2026-008 умерли в inboxes

**Суть:** Координатор 2026-04-17 вечером отправил ~7 SendMessage к dormant-директорам (task-постановки по RFC-006, RFC-007, ADR 0017-0021, quick-wins, DB drafts). По feedback_no_live_external_integrations и CLAUDE.md раздел «Процесс» + политике `docs/agents/inbox-usage.md` от 2026-04-18 — SendMessage к dormant субагенту не запускает сессию, сообщение остаётся в JSON-файле inbox и не обрабатывается. По состоянию 2026-04-18: 30 unread сообщений в 10 inbox, ни одно не отработано за ночь.

**Процессный эффект:** RFC-007 (запрошен 2026-04-17 22:45 UTC) физически не существует как файл; RFC-006 аналогично. Weekly digest 2026-04-18 §3 это фиксирует. Quick-wins по RFC-005 исполняются Координатором, не dormant субагентами.

**Кандидат на governance-аудит:**
- (а) Проверить, что политика inbox-usage.md покрывает все классы ситуаций (dormant, live-session, advisor).
- (б) Проверить, что по инциденту 2026-04-18 оформлен **процессный инцидент** в `docs/governance/incidents/` (по аналогии с ri-director sensing 2026-04-16) — на момент подготовки precheck файла инцидента Inbox-архив не обнаружено, хотя 7 задач утеряны.
- (в) Оценить: нужен ли retrospective перевыпуск задач RFC-006/RFC-007/2026-008 как Agent-вызовов (weekly digest 2026-04-18 §5 это рекомендует).

**Вопрос аудитору:** где формальная запись о принятии Inbox-usage policy v1.0 (CHANGELOG отсутствует)? Если policy введена без комиссии — это процессное нарушение либо требует ретроактивной заявки.

### 3.2 Параллельный спринт 2026-04-18 — 14 документов за час без governance-цикла

**Суть:** В течение дня 2026-04-18 в репозитории появились: ADR 0014, 0016, 0022, 4 force-majeure заявки (все ratified), Design System v1.0, Design System Initiative brief, Code audit interim, RFC-004 Hooks Phase 0 plan, closure-draft инцидента ст. 45а, Inbox-usage policy, PR #1 Wave 1 (10 коммитов с hotfix'ами), Legal PD stories.

**Риск:** governance видит их впервые в сводном виде на precheck; 4 заявки оформлены как force-majeure из-за недоступности `governance-director` через Agent tool (API Error «violates Usage Policy», воспроизводилось дважды за утро). Ретроспективный вердикт вынесен 2026-04-18 в той же CHANGELOG-записи — все 4 ratified, но заявка 3 (RFC-005) — conditionally ratified, требует отдельного прицельного аудита по 5 точкам.

**Кандидат на governance-аудит:**
- (а) Прицельный аудит RFC-005 по 5 точкам (из тела ретроспективного вердикта): ADR frontmatter ссылки, RFC Naming конфликты, RFC-vs-ADR дубли в Конституции/Процессуальном кодексе, Security gate CI совместимость с quality.md, общий сверочный прогон по приоритету коллизий.
- (б) Аудит нумерационного пропуска ADR: 0014, затем 0016, 0022 — где 0015, 0017-0021? Возможны зарезервированные номера; нужно подтвердить или устранить пропуски (влияет на связанность ст. 42 Свода).
- (в) Аудит статуса ADR 0014 — в какой момент перешёл `proposed → accepted` (упоминается в closure-draft инцидента ст. 45а как условие FULLY-RESOLVED, но в CHANGELOG за 2026-04-18 я не вижу отдельной записи про ADR 0014 approve).
- (г) Стабильность Agent-вызовов L2 Opus — verify-before-scale по feedback Владельца msg 1280 (это добавлено в «Системную находку» ретроспективного вердикта, нужно зафиксировать как трек).

### 3.3 Legal PD skeleton-first — зафиксирован как feedback в памяти, процессуального акта нет

**Суть:** В памяти Мартина есть feedback_skeleton_mode.md — «строим MVP-скелет coordinata56; глубокая безопасность — отдельной фазой перед подключением к боевым базам». Legal PD user stories (`stories/legal-pd-consent-flow.md`, `legal-pd-user-profile-fields.md`) и task pr2-wave1-rbac-v2-pd-consent.md — практическая реализация этого подхода для C-1 блокера ФЗ-152.

**Риск:** feedback пользователя → память агента, но в `CLAUDE.md` проекта / `departments/legal.md` / `departments/backend.md` принципа skeleton-first для Legal PD нет как явного правила. При смене контекста агента или новом разработчике (внешний консультант, новый субагент) это знание не передаётся. По CODE_OF_LAWS приоритету коллизий память — не источник правил; правила живут в документах.

**Кандидат на governance-аудит:**
- (а) Проверить, есть ли упоминание «skeleton-first для Legal PD» в `CLAUDE.md` проекта или в departmental-документах. Если нет — кандидат на явную норму в `CLAUDE.md` (раздел «Процесс» или «Данные и БД») либо в `departments/legal.md` (пока dormant, но stub-файл `~/.claude/agents/legal-director.md` существует).
- (б) Либо явный отказ (reject): «skeleton-first — это feedback_mode в конкретной фазе, не нормативное правило, не должно попадать в регламент». В этом случае — зафиксировать рассмотрение в CHANGELOG с мотивировкой.

### 3.4 Пропуски нумерации ADR

**Суть:** В `docs/adr/` обнаружены: 0001-0014, 0016, 0022. Отсутствуют 0015, 0017, 0018, 0019, 0020, 0021. В closure-draft инцидента ст. 45а упоминается «ADR-0015 Integration Registry (Волна 2)» — возможно, 0015 забронирован. ADR 0018 упоминается в `m-os-1-plan.md` v1.2 (поэтапность Admin-UI).

**Риск:** пустые номера в публичной нумерации создают непрозрачность; внешний консультант, глядя на публичное зеркало, не понимает, что заняты, что свободны. По практике ADR Lifecycle (RFC-005, пункт 1 Quick-Wins) статус `proposed` должен существовать в файле; бронь номера без файла не описана.

**Кандидат на governance-аудит:** ввести правило «ADR номер бронируется только с момента создания файла со статусом `proposed`»; либо создать stub-файлы для 0015, 0017-0021, 0023+ если они действительно забронированы.

### 3.5 ADR 0011 §2.4 backup для governance-director

В ретроспективном вердикте 2026-04-18 упомянута Системная находка: «Если появится повторная force-majeure — активировать `governance-auditor` как backup через делегирование полномочий Директора по вынесению вердиктов до восстановления (временное, через отдельную заявку)». Формального акта делегирования нет. Если Agent-вызов Директора снова упадёт на Usage Policy фильтре — непонятен путь.

**Кандидат на правку `departments/governance.md`:** раздел «Исключение быстрый путь» расширить — ввести «procedure при недоступности governance-director через Agent tool: Координатор делегирует governance-auditor полномочие ratify-approve на срок до восстановления; все ratify auditor'а автоматически идут на ретроспективный approve Директором после восстановления».

---

## 4. Предлагаемая повестка 2026-04-22 (5 пунктов)

| # | Пункт | Приоритет | Привлечь |
|---|---|---|---|
| 1 | Закрытие хвоста первого аудита (M1, M2, M6, M10) — обычная проверка с учётом изменений после реформы CODE_OF_LAWS v2.0 и добавления 9-го департамента Innovation | P2 | governance-auditor |
| 2 | Ретроспективный governance-проход по артефактам 2026-04-18 без CHANGELOG-записи: Inbox-usage policy v1.0, Design System v1.0 (квази-норматив), RFC-004 Hooks Phase 0 plan (DoD validation), ADR 0014 статус, ADR 0016/0022 proposed → заявка | P0 | governance-auditor + architect (для ADR) |
| 3 | Прицельный аудит RFC-005 Quick-Wins по 5 точкам (из ретроспективного вердикта 2026-04-18) — ADR frontmatter, RFC Naming, RFC-vs-ADR дубли, Security gate CI, приоритет коллизий | P1 | governance-auditor |
| 4 | Процессный инцидент Inbox-архив (§3.1 precheck) — оформить либо инцидент в `docs/governance/incidents/`, либо отдельной заявкой перевыпустить 7 утерянных задач как Agent-вызовы (RFC-006, RFC-007, ADR 0017-0021, quick-wins, DB drafts) | P1 | governance-auditor + Координатор (последний — для решения о перевыпуске) |
| 5 | Пропуски нумерации ADR (0015, 0017-0021) + процессуализация skeleton-first для Legal PD (либо явная норма в CLAUDE.md/departments/legal.md, либо reject с мотивировкой) + backup governance-director процедура (§3.5) | P2 | governance-auditor + Координатор |

---

## 5. Кого привлекать к аудиту

### 5.1 Обязательно
- **`governance-auditor`** — основной исполнитель аудита по стандартной процедуре `departments/governance.md`. Бриф — этот precheck + первый аудит как бейслайн. Оценка трудоёмкости: скоуп вырос примерно вдвое (24 → 40+ документов регламентного уровня после реформы v2.0 и 14 новых артефактов), читабельный eженедельный ритм нарушается — разумно ожидать 90–120 минут (вместо 20–30 по прогнозу первого аудита).

### 5.2 По запросу
- **`architect`** (советник) — для пункта 2 (оценка ADR 0014, 0016, 0022 — статус, совместимость с Конституцией, наличие связей supersedes/superseded_by где применимо; ADR 0016 имеет отсылки к ADR 0008, 0009, 0011, 0014 — проверить согласованность).
- **`legal`** (советник, dormant direction) — для пункта 5 (skeleton-first для Legal PD в регламенте или явный отказ). Если направление Legal ещё не активировано, привлечь `legal` как advisor.

### 5.3 Не привлекать
- **Владелец** — до финализации отчёта. По регламенту — эскалация только через Координатора.
- **`governance-director`** (я сам) — исполнителем выступает auditor; я принимаю отчёт и выношу вердикты.

---

## 6. Ожидаемые артефакты по итогам 2026-04-22

1. `docs/governance/audits/weekly/2026-04-22-second-audit.md` — отчёт auditor'а по структуре первого аудита (P0/P1/P2, рекомендации, оценка ритма).
2. `docs/governance/requests/2026-04-22-*.md` — заявки по P0/P1 находкам (по правилу SLA: в одной сессии после получения отчёта завести все W-заявки или явно reject).
3. `docs/governance/CHANGELOG.md` — записи о ретроактивных approve (Inbox-usage policy, Design System v1.0 если квалифицировано как норматив, ADR 0014 approve если ещё не в changelog), о вынесенных вердиктах.
4. Если подтверждён §3.1 — новый инцидент `docs/governance/incidents/2026-04-18-inbox-archive.md` с post-mortem по SendMessage-инциденту.

---

## 7. Ссылки

- Первый аудит (бейслайн): `docs/governance/audits/weekly/2026-04-15-first-audit.md`
- CHANGELOG: `docs/governance/CHANGELOG.md`
- Регламент отдела: `docs/agents/departments/governance.md`
- CODE_OF_LAWS v2.1: `docs/agents/CODE_OF_LAWS.md`
- Inbox-usage policy: `docs/agents/inbox-usage.md`
- Closure-draft инцидента ст. 45а: `docs/governance/incidents/2026-04-17-external-audit-art45a-violation-closure-draft.md`
- Weekly digest R&I 2026-04-18: `docs/research/digests/2026-04-18-weekly.md`
- RFC-004 Hooks Phase 0 plan: `docs/research/rfc/rfc-004-hooks-phase-0-plan.md`
- Design System v1.0: `docs/design/design-system-v1.md`
- ADR 0016: `docs/adr/0016-domain-event-bus.md`
- Code audit interim: `docs/reviews/code-audit-interim-2026-04-18.md`

---

**Конец precheck.** Ожидаю запуск аудита 2026-04-22 с этим документом как брифом для `governance-auditor`.
