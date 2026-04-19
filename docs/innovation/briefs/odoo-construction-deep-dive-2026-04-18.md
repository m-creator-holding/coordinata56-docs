# Innovation Brief — Odoo Construction vs M-OS cottage-pod (deep-dive)

> **Тип документа:** Innovation Brief, deep-dive сравнительный разбор
> **Дата:** 2026-04-18
> **Автор:** innovation-director (Департамент инноваций и развития)
> **Заказчик:** Координатор → Владелец
> **Привязка:** competitor-watch.md строка #18 (Odoo Construction, «deep-dive R5»), Holding ERP Market Scan 2026-04-18 §2.5
> **Потребитель результата:** Владелец (финальное решение adopt/mix/reject), Координатор (маршрутизация заимствований в backend/frontend/design департаменты)
> **Формат:** live web-sensing Odoo pricing pages, Odoo Apps Store, OCA GitHub, Odoo forums, Consultant.ru (КС-акты), сравнительные обзоры Odoo vs 1С

---

## TL;DR — вердикт

- **Вердикт: REJECT как альтернативу + MIX (заимствовать паттерны).** Odoo не заменяет M-OS для холдинга Владельца, но содержит конкретные UX- и архитектурные паттерны, которые стоит перенести в cottage-pod.
- **Почему не альтернатива:** нет 214-ФЗ, нет КС-2/КС-3 из коробки, multi-company isolation — «косметический» (shared products/contacts по умолчанию), русская локализация — силами сообщества, а не вендора, Voice AI / CV / крипто-аудит отсутствуют полностью.
- **Топ-3 заимствования:**
  1. **Developer mode** (runtime-кастомизация полей через UI, без деплоя) — паттерн для Admin UI конструктора M-OS.
  2. **BoQ + Work Packages + Cost Center** как структура стройпроекта — референс для модели `Project → Phase → WorkPackage → Task` в cottage-pod.
  3. **Kanban + вкладки (notebook) + календарь** — три базовых представления для каждой сущности; готовый UX-паттерн для frontend-департамента.
- **Сигнал мониторинга:** Odoo не конкурент в сегменте «российский холдинг ≥5 юрлиц со стройкой». Следим quarterly, не weekly.

---

## 1. Что такое Odoo Construction — фактура

### 1.1. Структура продукта

Odoo — это не единый «строительный ERP», а **конструктор из ~80 модулей**, из которых под стройку собирается пакет:

| Модуль Odoo | Что делает для стройки |
|---|---|
| **Project** | иерархия Project → Task, Kanban-доски, Gantt (в Enterprise), таймшиты |
| **Manufacturing (MRP)** | BoM (Bill of Materials) переиспользуется как BoQ (Bill of Quantities) для стройки — косвенно |
| **Purchase** | заявки на закупку, RFQ, контракты с поставщиками/субподрядчиками |
| **Inventory** | склад материалов на объекте, приходы/расходы, резервирование под задачи |
| **Accounting** | план счетов, первичка, бух.проводки — в западном формате (IFRS/локальные планы по странам) |
| **HR + Payroll + Timesheets** | кадры, табели, зарплата (в РФ — частично) |
| **Fleet** | техника (экскаваторы, краны) |
| **Field Service** | выездные бригады, наряды |
| **Helpdesk / Quality** | дефект-менеджмент, приёмки |
| **Documents / Sign** | документооборот, электронная подпись (западная, не УКЭП РФ) |

### 1.2. Сторонние апсы — где «Construction» появляется как термин

На Odoo Apps Store и в OCA (Odoo Community Association, GitHub `OCA/vertical-construction`) лежат апсы трёх категорий:

- **Вендорские** (BrowseInfo, Probuse, Apagen Solutions, TNC) — типичная функциональность: Cost Code, Work Package, BoQ, Job Order/Work Order, Material Request. Это **надстройки Project + MRP**, не самостоятельный продукт.
- **OCA `vertical-construction`** — open-source коллекция, поддерживаемая сообществом: `construction_management`, `contract_management_with_retention`, `project_boq`. Качество — «community grade», не vendor-grade.
- **Нишевые РФ** — единичные попытки (`l10n_ru` от сообщества, `1C Connector`), **не являются официальной локализацией Odoo S.A.**

**Важно:** официально **Odoo S.A. не поддерживает русскую локализацию** с 2022 года — всё, что есть, — это OCA и партнёры (NetFrame, ICode), то есть поддержка зависит от сторонних подрядчиков, не от вендора.

### 1.3. Цены (2026-04)

| Вариант | Цена | Примечание |
|---|---|---|
| **Community Edition** | бесплатно (LGPL v3) | сам хостишь, сам обновляешь, часть модулей недоступна (Accounting с отчётностью, Marketing Automation, Studio, IoT) |
| **Enterprise Standard** | ~$31/user/month (annual) | все модули, Odoo Online / Odoo.sh / On-premise |
| **Enterprise Custom** | ~$47/user/month (annual) | + Studio (no-code конструктор), Multi-company, External API |
| **В РФ-эквиваленте** | ~2 500–3 800 руб/user/мес | зависит от региона биллинга Odoo; санкционные блокировки платежей из РФ — отдельный риск |
| **OCA модули** | бесплатно | для Community; для Enterprise совместимость — на свой страх |

**Скрытые статьи затрат:** внедрение (партнёр-интегратор, 50–500 тыс. руб в мес × 3–6 мес), кастомизация (~$80–150/час), хостинг on-premise (PostgreSQL + Nginx + Odoo worker pool), обновления между мажорными версиями (17→18→19 — миграция данных ломает кастомы каждый год).

### 1.4. Хостинг

- **Odoo Online (SaaS)** — самый дешёвый, но без кастомных модулей; для стройки почти бесполезен, так как нужны минимум 2–3 OCA аддона.
- **Odoo.sh** — managed PaaS от Odoo S.A., допускает custom modules; **санкционные риски оплаты из РФ**.
- **On-premise** — единственный реалистичный путь для РФ-холдинга; требует DevOps-команды.

---

## 2. Что Odoo делает хорошо (для девелопера коттеджей уровня Мартина)

### 2.1. План/факт бюджета проекта

- Модель: `Project` → `Analytic Account` (аналитическая проводка) → `Budget` + `Budget Lines`.
- Каждая задача/закупка/табель/расход привязывается к аналитическому счёту проекта.
- Отчёт «Budget vs Actuals» — готовый, без разработки.
- **Сильная сторона:** аналитический учёт (analytic accounting) — одна из наиболее зрелых частей Odoo, работает с v6 (2011 год).
- **Для M-OS:** архитектурный паттерн «analytic account = проект/дом/этап» — **прямой референс** для финансового модуля M-OS-2/M-OS-3.

### 2.2. Управление подрядчиками

- Subcontractor = Vendor (Partner с флагом) + договор (`Purchase Order`/`Subcontracting Agreement`) + `Retention` (удержание гарантийного платежа, есть в OCA).
- Наряд-задания — через Field Service или Project Task.
- **Ограничение:** нет понятия «бригада» как первоклассной сущности (в 1С:УСО 2 — есть), нет «сменного рапорта» в РФ-формате.

### 2.3. Складские остатки материалов

- `Inventory` — full-featured WMS: multi-warehouse, multi-location, routes, putaway strategies, lots/serials, barcode.
- Резервирование материалов под задачу проекта — через MRP или кастомный flow.
- **Сильная сторона:** один из лучших складских движков среди open-source ERP.
- **Для M-OS:** переизбыточен для cottage-pod, но референс для будущего `warehouse-pod` холдинга (металлобаза, карьер).

### 2.4. Табели / HR

- Timesheets (часы на задачу/проект) + Attendances (вход/выход) + Payroll.
- **Ограничение РФ:** Payroll-модуль Odoo не закрывает российский расчёт (НДФЛ, страховые взносы, 6-НДФЛ, СЗВ-ТД, ЕФС-1). Русский Payroll в Odoo — community, неполный.
- **Для M-OS:** НЕ используем как референс для HR-ядра холдинга; только паттерн «таймшит → аналитический счёт проекта» для cottage-pod.

### 2.5. Бухгалтерия

- Отличная для IFRS / US GAAP / большинства ЕС-стран (100+ локализаций от Odoo S.A.).
- **Российская локализация (`l10n_ru`) — community, устаревшая, не покрывает:** бух.отчётность РФ, декларации, первичку в формах Росстата, КУДиР, ККТ, ОФД, ЭДО (СБИС/Диадок/Контур).
- **Вывод:** для российской бухгалтерии Odoo **непригоден без тесной интеграции с 1С**, где бухгалтерия ведётся в 1С, а Odoo — операционный контур.

---

## 3. Что Odoo НЕ делает или делает плохо (дельта vs M-OS)

### 3.1. 214-ФЗ (долевое строительство) — отсутствует полностью

- Нет понятий: ДДУ (договор долевого участия), ЭДО с Росреестром, эскроу-счёт, проектная декларация, передача квартиры по акту приёма-передачи с указанием 214-ФЗ, раскрытие информации на наш.дом.рф.
- Нет готовых отчётов для надзорных органов (Росстрой, Москомстройинвест).
- **В M-OS cottage-pod** — это ядро domain-слоя (ADR 0008, pod-миграция).

### 3.2. КС-2 / КС-3 / КС-6а / КС-11 / КС-14 — нет из коробки

- Odoo оперирует западными «invoice + timesheet + delivery slip». Российские унифицированные формы (КС-2 «Акт о приёмке выполненных работ», КС-3 «Справка о стоимости выполненных работ и затрат», КС-6а «Журнал учёта выполненных работ», КС-11 «Акт приёмки законченного строительством объекта», КС-14 «Акт приёмки законченного строительством объекта приёмочной комиссией») — **отсутствуют**.
- Попытки community-аддонов единичные, не production-grade.
- **В 1С:УСО 2** — это штатная функциональность, закрыта из коробки.
- **В M-OS** — планируется как часть cottage-pod (legal-skeleton-first по решению Владельца 2026-04-18 msg 1409).

### 3.3. Интеграция с 1С — только через сторонние коннекторы

- Официального коннектора Odoo ↔ 1С нет.
- Доступен OCA/вендорский `o1c` (1C Connector), позиционируется как «конструктор правил маппинга».
- Production-зрелость — низкая; каждая интеграция — индивидуальный проект интегратора.
- **Вывод:** в сценарии «Odoo — оперативный контур, 1С — бухгалтерия» интеграция превращается в постоянную статью затрат, а не одноразовый проект.
- **В M-OS** — интеграция 1С ↔ M-OS через anti-corruption layer закладывается архитектурно в ADR (как must-have для переходного периода 3–5 лет).

### 3.4. Voice AI для прораба — нет

- Odoo не имеет voice-интерфейса. Есть Discuss (чат), есть mobile app с ручным вводом.
- Чтобы добавить voice — нужен самостоятельный R&D (ASR провайдер + интеграция с Odoo API).
- **В M-OS-2** — Voice AI (Yandex SpeechKit) заложен как базовый канал (см. `briefs/voice-ai-russia-deep-dive-2026-04-18.md`).

### 3.5. Компьютерное зрение / фото-воркфлоу — нет

- В Odoo можно прикрепить фото к задаче, но нет CV-анализа (подрядчик на объекте, СИЗ, прогресс по фото).
- У Procore — Photo Intelligence; у Odoo — нет.
- **В M-OS** — заложено в Technology Radar как Assess/Trial для Фазы 3+.

### 3.6. Крипто-цепочка аудита (hash-chain, иммутабельный аудит) — нет

- В Odoo аудит — через `mail.thread` (лог изменений, chatter). Это **мутабельный лог в БД**, не иммутабельный.
- Ничего подобного ФЗ-152-совместимой крипто-цепочке нет.
- **В M-OS** — иммутабельный аудит через hash-chain (ADR 0007 + CODE_OF_LAWS) — **ключевой дифференциатор**.

### 3.7. UI для стройки — общий ERP, не специализированный

- Kanban / List / Form / Calendar / Gantt — универсальные views Odoo.
- Нет специализированных view: «дом в разрезе этажей», «проектный календарь с погодой», «фото-таймлайн объекта», «карта посёлка со state transitions».
- Мобильное приложение Odoo — универсальное, не заточено под полевую работу прораба (сравн. PlanRadar, Procore).
- **В M-OS cottage-pod** — специализированные UI-представления заложены в frontend-roadmap.

### 3.8. Multi-company isolation — базовая, не холдинговая

По официальной документации Odoo 18/19 и обсуждениям на forum.odoo.com:

- По умолчанию **Products, Contacts, Equipment — shared across companies**. Нужно вручную выключать в `General Settings`.
- **Record Rules** (row-level security) работают не везде — известные дыры: CRM Leads (до v12), Calendar Events, часть Accounting-отчётов.
- **Инцидент «company switch»:** пользователь, залогиненный в обе компании A и B, может создать SO в A с продуктами из B — система покажет ошибку только после выхода из B. Это **бизнес-риск при аудите**.
- **Вывод:** для холдинга Мартина (5 направлений × несколько юрлиц в каждом, плюс требование изоляции «карьер не видит АЗС») — Odoo multi-company **недостаточен**. Пришлось бы дополнять кастомными record rules поверх каждого модуля.
- **В M-OS** — per-company isolation решена архитектурно (ADR 0009 pod-архитектура + per-company limits, решения Владельца 2026-04-17 по M-OS-1).

### 3.9. Прочее, что отсутствует

- УКЭП (квалифицированная ЭП) — есть только Odoo Sign (западный аналог DocuSign).
- ЭДО с российскими операторами (СБИС, Диадок, Контур.Экстерн) — нет официального коннектора.
- Касса ККТ 54-ФЗ, ОФД — нет.
- Росреестр, ФНС, Росстат, Роспотребнадзор — нет.
- СМЭВ (межведомственный обмен) — нет.
- BIM/IFC viewer — только через сторонние аддоны с viewer3d; в Procore / Autodesk — встроено.

---

## 4. Когда Odoo — правильный выбор

Odoo **имеет смысл** как ERP для стройки, если выполняются **все** условия:

1. **Небольшой девелопер** — до 15–20 одновременных проектов, один юрлицо или 2–3 без сложной консолидации.
2. **Нет требований российской compliance** — не ДДУ (работа с коттеджами без 214-ФЗ, ИЖС по ГК 549), либо бух.учёт ведётся в 1С параллельно и связь руками.
3. **Есть готовый партнёр-интегратор Odoo** в РФ/СНГ (например, NetFrame, ICode) и бюджет на внедрение ~1.5–4 млн руб + постоянный support.
4. **Приоритет — быстрый старт**, а не долгосрочная уникальность. Odoo даёт 70% готовой функциональности за 3–4 месяца — это его главное преимущество.
5. **Английский / европейский контекст** приемлем — команда принимает западные формы документов, аналитику в IFRS-логике.

**Для подобных игроков Odoo — реальная альтернатива 1С:УСО 2** за счёт лучшего UX, Kanban/Gantt, open-source кастомизации и дешевле по лицензиям (при >10 пользователях Odoo дешевле 1С-лицензий).

---

## 5. Когда M-OS — правильный выбор (почему для Владельца — это M-OS)

M-OS выигрывает в нашем конкретном сценарии по **6 факторам**:

1. **Холдинг ≥5 юрлиц из 5 разных отраслей** — per-company и per-pod isolation. Odoo это не тянет без массивной кастомизации.
2. **РФ-compliance обязательна** — 214-ФЗ (коттеджи бизнес-класса с продажей ДДУ), ГК 549 (ИЖС), ФЗ-152 (ПД с маскированием), КС-акты, ЭДО с 1С, УКЭП, ОФД, банковские выписки. Всё это в Odoo — ноль или community-grade.
3. **Уникальные функции как дифференциатор бизнеса:** Voice AI прораба, CV-анализ фото объектов, крипто-цепочка аудита, глубокая интеграция с 1С через ACL, AI-native агентская модель (Конституция M-OS, департаменты субагентов).
4. **Мультиотраслевая платформа одной pod-архитектуры** (cottage-pod, gas-stations-pod, quarry-pod, metal-pod, mkd-pod) — ни один конкурент, включая Odoo, не предлагает модульность «по отрасли холдинга»; Odoo даёт модульность «по функции» (Sales/Purchase/Inventory).
5. **Собственность на код и данные.** M-OS — собственное ПО Владельца, без зависимости от западного вендора, без санкционных рисков, без ежемесячных per-user лицензий. Odoo Enterprise — $30–47/user/мес × десятки пользователей × 12 мес = 2–5 млн руб/год только лицензий, навсегда.
6. **AI-native с первого дня.** Odoo добавляет AI как layer поверх классической ERP (чат-боты, предиктивные поля); M-OS спроектирована как оркестратор AI-агентов (Конституция, 17 субагентов, Координатор-транспорт). Архитектурно разные парадигмы.

**Добавим экономику.** На горизонте 3 лет для холдинга Мартина:

| Статья | Odoo Enterprise | M-OS |
|---|---|---|
| Лицензии 40 пользователей × 36 мес × $31 | ~3.8 млн руб | 0 |
| Внедрение партнёром | 2–4 млн руб | 0 (делаем сами с Claude Code) |
| Русская локализация (доработка до 1С-уровня) | 3–6 млн руб (отдельный проект) | включена by design |
| КС-акты, 214-ФЗ, УКЭП, ОФД | 2–5 млн руб (кастом) | включена by design |
| Multi-company усиление | 1–2 млн руб (кастом record rules) | включена by design |
| Поддержка/обновления | 0.5–1 млн руб/год | собственная команда |
| **Итого 3 года** | **12–22 млн руб** | 0 (собственная разработка) |

При этом на выходе у Odoo — **всё равно не совсем под Владельца**, а у M-OS — **точно под Владельца**.

---

## 6. Рекомендация

**REJECT как альтернативу M-OS. Продолжаем свою разработку.** Odoo не решает ключевые требования РФ-compliance, multi-industry холдинга и AI-native архитектуры. Миграция на Odoo как замена M-OS — экономически и функционально проигрышный сценарий.

**Статус в competitor-watch:** «Референс архитектурный» (не прямой конкурент). Мониторинг — **quarterly**, не weekly.

**Триггеры повторного рассмотрения:**
- Если Odoo S.A. официально запустит русскую локализацию с КС-актами и 214-ФЗ (крайне маловероятно в условиях санкций).
- Если у Владельца появится необходимость обеспечить ERP в страну с зрелой Odoo-экосистемой (ЕС, СНГ без РФ).
- Если темп разработки M-OS потребует bridge-решения на 6–12 мес (маловероятно — cottage-pod MVP в work).

---

## 7. Что можно заимствовать у Odoo (MIX-часть вердикта)

Odoo — это 15 лет R&D поверх принципов, которые стоит изучить и частично перенести в M-OS:

### 7.1. Топ-3 заимствования (приоритетные)

**Заимствование №1 — Developer Mode (runtime-кастомизация через UI).**
- Паттерн: админ включает «debug mode», видит технические имена полей, может добавить/скрыть/переименовать поле, изменить view (Kanban/Form/List) — **без пересборки и перезапуска**.
- В Odoo это делается через Studio (Enterprise) или `ir.ui.view` + XML (Community).
- **Перенос в M-OS:** Admin UI «Полный конструктор» (решение Владельца M-OS-1 от 2026-04-17) — сделать по этому паттерну. Хранить метаданные форм/view в БД (Config-as-Data), редактировать через UI, применять на лету. Ключевое — версионирование схемы (B2 migration strategy уже решена).
- **Маршрутизация:** Координатор → backend-director (модель `view_metadata`) + frontend-director (динамический рендер форм) + design-director (UX конструктора).

**Заимствование №2 — BoQ + Work Package + Analytic Account как структура стройпроекта.**
- Паттерн: `Project → Work Package → Task`, параллельно `Analytic Account` пронизывает всё (закупка, табель, складская операция, бух.проводка — все получают `analytic_account_id = project_id`).
- Это даёт автоматический план/факт на любом срезе (проект / WP / задача).
- **Перенос в M-OS cottage-pod:** модель `Project (коттеджный посёлок) → Phase (участок/этап) → WorkPackage (тип работы) → Task (конкретная задача)`, + `analytic_account_id` на каждой финансовой операции через ACL с 1С.
- **Маршрутизация:** Координатор → backend-director + construction-expert (advisory) для валидации соответствия РФ-практике.

**Заимствование №3 — базовый набор views: Kanban + Notebook-вкладки + Calendar.**
- Паттерн Odoo: **каждая сущность** имеет минимум 3 представления:
  - **Kanban** — карточки со статусами (для dashboard, «что в работе сегодня»).
  - **Form с вкладками (notebook)** — детальная карточка, вкладки группируют связанные данные (Overview / Tasks / Files / Audit).
  - **Calendar** — любая сущность с датами автоматически ложится на календарь.
- Плюс List и Pivot как аналитика.
- **Перенос в M-OS:** design-system Initiative (уже обсуждается в governance) — зафиксировать 5 базовых view (Kanban, Form+Notebook, Calendar, List, Pivot) как обязательный набор для каждой доменной сущности.
- **Маршрутизация:** Координатор → frontend-director + design-director для design-system.

### 7.2. Второстепенные заимствования (в backlog)

- **Chatter (mail.thread) + followers + @-mentions на каждой сущности** — универсальный лог комментариев и уведомлений. В M-OS может лечь поверх иммутабельного аудита как «комментарийный слой».
- **Model inheritance (`_inherit`) через точечное расширение** — архитектурный паттерн для pod-архитектуры M-OS (pod расширяет базовую сущность core, не форкает).
- **Kanban states + color-coded** — визуальный паттерн «в работе / заблокировано / на ревью / готово» с цветом.
- **Report Engine (QWeb)** — XML-шаблоны для печатных форм. Для M-OS можно подсмотреть идею «template = HTML + переменные», применить к КС-актам.
- **Scheduled Actions (`ir.cron`)** — декларативные cron-задачи с параметрами. Паттерн для M-OS BPM.
- **Export / Import CSV на каждой модели** — встроенная функция, обязательна для любой админской сущности.

### 7.3. Что НЕ заимствовать

- **ORM Odoo (`models.Model`)** — устаревшая, leaky abstractions, monkey-patching. У нас SQLAlchemy — правильный выбор.
- **Payroll / HR РФ** — community, неполная, риск наследовать баги.
- **Accounting РФ** — community, не покрывает РФ-отчётность; в M-OS бух.учёт остаётся в 1С, ACL-интеграция.
- **Odoo mobile app** — generic, не заточен под стройку; у нас Telegram + специализированный веб-UI.

---

## 8. Риски для M-OS, если мы проигнорируем Odoo-паттерны

1. **Изобретение велосипеда в UX.** Если frontend-department построит formы без notebook-вкладок, Kanban-досок и календарей «на каждой сущности» — пользователи будут сравнивать не в нашу пользу с любой виденной ERP (включая 1С:УСО 2 с его неуклюжим, но знакомым UI).
2. **Admin UI конструктора без developer-mode-паттерна.** Если админ не сможет менять поля/формы без деплоя — мы получим ту же жалобу, которую Odoo решил 10 лет назад.
3. **Финансовый модуль без analytic accounting.** Если план/факт будет считаться только на уровне проекта, но не на WP/задаче — вернёмся переделывать через 3–6 месяцев.

---

## 9. Действия по итогам брифа

### Решения, которые Владелец может принять сейчас (0–1 день)

- [ ] **Утвердить вердикт REJECT+MIX** — не мигрируем на Odoo, забираем паттерны.
- [ ] Подтвердить заимствования №1–3 как вход в backlog M-OS.

### После утверждения — Координатор маршрутизирует

- [ ] **Задача backend-director:** RFC «Analytic Account pattern для финансового модуля M-OS-2/M-OS-3» (заимствование №2).
- [ ] **Задача backend-director + frontend-director:** RFC «View-metadata model + runtime конструктор форм» для Admin UI M-OS-1 (заимствование №1).
- [ ] **Задача design-director:** расширить Design System Initiative требованием «5 базовых views на каждую сущность: Kanban, Form+Notebook, Calendar, List, Pivot» (заимствование №3).
- [ ] **Задача construction-expert (advisory):** валидация BoQ/WP модели на соответствие РФ-практике.

### В competitor-watch.md

- [ ] Обновить строку #18: статус «Референс архитектурный», мониторинг quarterly, последний deep-dive — 2026-04-18, ссылка на этот бриф.

### В tech-radar.md

- [ ] Добавить 3 паттерна как Adopt/Trial:
  - «View-metadata + developer mode» — Trial T1.
  - «Analytic Account pattern» — Adopt.
  - «5 базовых views (Kanban/Form-Notebook/Calendar/List/Pivot)» — Adopt.

---

## 10. Библиография

### Цены и структура Odoo
- Odoo Pricing — https://www.odoo.com/pricing
- Odoo Pricing Explained 2025 (Heliconia) — https://www.heliconia.io/odoo-pricing
- Odoo Pricing 2026 (Whizzbridge) — https://www.whizzbridge.com/blog/odoo-pricing
- Odoo Pricing Breakdown 2026 (Biztech) — https://www.biztechcs.com/blog/odoo-pricing-breakdown/
- Odoo Pricing 2026 per country (OEC) — https://oec.sh/odoo-pricing

### Construction modules
- construction_management_app (Odoo Apps Store, v13) — https://apps.odoo.com/apps/modules/13.0/construction_management_app
- Construction Management in Odoo (v15) — https://apps.odoo.com/apps/modules/15.0/construction_management
- tnc_construction_management (v15) — https://apps.odoo.com/apps/modules/15.0/tnc_construction_management
- OCA/vertical-construction (GitHub) — https://github.com/OCA/vertical-construction
- OCA/project (GitHub) — https://github.com/OCA/project
- Odoo for Construction (Apagen) — https://www.apagen.com/odoo-construction-management/
- Odoo for Construction (First Line Software) — https://firstlinesoftware.com/blog/odoo-for-construction-project-management/

### Russia-specific и 1С интеграция
- Russia - Accounting (Odoo Apps Store, v13 l10n_ru) — https://apps.odoo.com/apps/modules/13.0/l10n_ru
- 1C Connector (Odoo Apps Store) — https://apps.odoo.com/apps/modules/12.0/o1c
- Russia - Accounting (OCA) — https://odoo-community.org/shop/russia-accounting-715517
- Where Russian localization? (Odoo forum) — https://www.odoo.com/forum/help-1/where-russian-localization-50207
- Odoo vs 1C (Solvve) — https://solvve.odoo.com/odoo-vs-1c
- Replacing 1C with Odoo (NetFrame) — https://www.netframe.org/blog/gid-po-odoo-3/netframe-ofitsiinii-partner-self-erp-vash-krok-do-nezalezhnosti-vid-vorozhogo-softu-53
- ICode: Odoo в Belarus & Russia — https://www.odoo.com/blog/partner-stories-8/icode-bringing-innovative-it-solutions-to-belarus-russia-689

### КС-акты РФ (контекст 214-ФЗ)
- КС-2, КС-3 (Контур.Экстерн) — https://support.kontur.ru/extern/48281-forma_ks2_i_ks3
- Форма КС-2 (КонсультантПлюс) — https://www.consultant.ru/document/cons_doc_LAW_26303/d7e7d105e01770fac8296c4832201fd3f313d0b5/
- КС-3 (Диадок) — https://www.diadoc.ru/docs/forms/ks-3

### Multi-company
- Multi-company Guidelines (Odoo 18) — https://www.odoo.com/documentation/18.0/developer/howtos/company.html
- Multi-company Guidelines (Odoo 19) — https://www.odoo.com/documentation/19.0/developer/howtos/company.html
- Multi-company (Odoo 18 Applications) — https://www.odoo.com/documentation/18.0/applications/general/multi_company.html
- Multi-Company Setup Best Practices (Surekha Tech) — https://www.surekhatech.com/blog/odoo-multi-company-setup-best-practices
- Multicompany — limit access to users (forum) — https://www.odoo.com/forum/help-1/multicompanies-limit-access-to-users-to-access-others-companies-and-users-156272

---

## Приложение. Коротко, что меняется в связанных документах

- **competitor-watch.md** строка #18 — обновить дату, статус, ссылку на этот бриф.
- **tech-radar.md** — добавить 3 паттерна (Analytic Account — Adopt, View-metadata — Trial, 5-views-на-сущность — Adopt).
- **board.md** — добавить запись «Odoo deep-dive выполнен, вердикт REJECT+MIX, 3 задачи маршрутизированы».
- **findings.md** — добавить finding «Odoo-паттерны заимствованы в backlog M-OS».
