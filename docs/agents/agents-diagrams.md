# Визуальные схемы системы субагентов M-OS

**Версия:** 1.1
**Дата:** 2026-04-17
**Источник данных:** `agents-map.yaml`

> **Примечание v1.1:** С введением ADR 0010 (таксономия) каждый агент имеет тип: `executive`, `core_department`, `domain_pod`, `governance`, `advisory`. Поле `agent_type` добавлено в `agents-map.yaml`. Полная перерисовка диаграмм под pod-структуру -- в следующем обновлении.

Все схемы — в нотации Mermaid. Рендерятся в GitHub Markdown, VS Code Mermaid extension, mermaid.live.

**Как читать:**
- Сплошная стрелка `-->` — подчинение (делегирование сверху вниз)
- Пунктирная стрелка `-.->` — консультация / информационный поток (советники, ревью)
- Прямоугольник — активный агент
- Пунктирный прямоугольник — dormant (файл есть, но задачи не получает до активации направления)

---

## А. Общая оргструктура (по уровням)

```mermaid
flowchart TB
    Owner["Владелец (Мартин)<br/>L0"]
    TG["Telegram / Terminal<br/>канал общения"]
    Coord["Координатор (CEO)<br/>L1 · Opus"]

    Owner -->|ставит задачи| TG
    TG --> Coord
    Coord -->|отчёт| TG

    subgraph L2 ["L2 — Директора (8: 7 активных + 1 dormant)"]
        BD["backend-director 🟢"]
        QD["quality-director 🟢"]
        GD["governance-director 🟢"]
        RD["ri-director 🟢"]
        FD["frontend-director 🟢"]
        DsD["design-director 🟢"]
        ID["infra-director 🟢"]
        LD["legal-director 💤"]
    end

    Coord --> BD
    Coord --> QD
    Coord --> GD
    Coord --> RD
    Coord --> FD
    Coord --> DsD
    Coord --> ID
    Coord -.-> LD

    subgraph Advisors ["Штабные советники (не в иерархии)"]
        A1["architect"]
        A2["analyst"]
        A3["legal (универсальный)"]
        A4["construction-expert"]
        A5["tech-writer"]
        A6["memory-keeper"]
        A7["tutor"]
        A8["data-analyst"]
    end

    Coord -.-> Advisors
```

**Комментарий:** 7 активных директоров реально получают задачи (backend, quality, governance, ri, frontend, design, infra); 1 dormant (legal-director) — файл создан, задачи получает только при боевых данных. Активация frontend/design/infra — 2026-04-16 msg 665+695.

---

## Б. Структура по департаментам (для читаемости — 4 схемы)

### Б.1 Бэкенд и Инфраструктура (активно)

```mermaid
flowchart TB
    Coord["Координатор"]
    BD["backend-director 🟢"]
    ID["infra-director 💤"]

    Coord --> BD
    Coord --> ID

    BD --> BH["backend-head 🟢"]
    BD --> IH["integrator-head 🟢"]
    BH --> BDev1["backend-dev-1"]
    BH -.-> BDev2["backend-dev-2 (при нагрузке)"]
    BH -.-> BDev3["backend-dev-3 (при нагрузке)"]
    BD --> INT["integrator"]

    ID --> DOH["devops-head 🟢"]
    ID --> DBH["db-head 🟢"]
```

### Б.2 Качество (активно полностью)

```mermaid
flowchart TB
    Coord["Координатор"]
    QD["quality-director 🟢"]

    Coord --> QD
    QD --> QH["qa-head 🟢"]
    QD --> RH["review-head 🟢"]

    QH --> Q1["qa-1"]
    QH -.-> Q2["qa-2 (при нагрузке)"]

    RH --> Rev["reviewer"]
    RH --> Sec["security"]
```

### Б.3 Governance и R&I (особые, активны с 2026-04-15)

```mermaid
flowchart TB
    Coord["Координатор"]
    GD["governance-director 🟢"]
    RD["ri-director 🟢"]

    Coord --> GD
    Coord --> RD

    GD --> GA["governance-auditor 🟢<br/>L3 особый"]
    RD --> RS["ri-scout 🟢<br/>L3 особый"]
    RD --> RA["ri-analyst 🟢<br/>L3 особый"]

    RS -.->|расшифровка простым языком| Brief[(docs/research/briefs/)]
    RS -.->|находки| Find[(docs/research/findings.md)]
    RA -.->|RFC| RFC[(docs/research/rfc/)]

    GA -.->|еженедельный отчёт| Aud[(docs/governance/audits/)]
    GD -.->|changelog| CL[(docs/governance/CHANGELOG.md)]
```

### Б.4 Фронтенд и Дизайн (dormant, активация Фаза 4)

```mermaid
flowchart TB
    Coord["Координатор"]
    FD["frontend-director 🟢"]
    DsD["design-director 🟢"]

    Coord --> FD
    Coord --> DsD

    FD --> FH["frontend-head 🟢"]
    FH --> FDev["frontend-dev"]
    FH -.-> FDev2["frontend-dev-2 (при нагрузке)"]

    DsD --> UXH["ux-head 🟢"]
    DsD -.-> VH["visual-head 💤"]
    DsD -.-> CH["content-head 💤"]

    UXH -.-> UXR["ux-researcher 💤"]
    UXH -.-> UXD["ux-designer 💤"]
    VH -.-> UID["ui-designer 💤"]
    VH -.-> AA["accessibility-auditor 💤"]
    CH -.-> UXW["ux-writer 💤"]
    CH -.-> CW["copywriter 💤"]

    UXH --> Dsg["designer"]
```

### Б.5 Юридическое направление (dormant, активация при боевых данных)

```mermaid
flowchart TB
    Coord["Координатор"]
    LD["legal-director 💤"]
    LegalAdvisor["legal (советник)<br/>штаб"]

    Coord -.-> LD
    Coord --> LegalAdvisor

    LD -.-> LH["legal-head 💤"]
    LH -.-> LR["legal-researcher 💤"]
    LH -.-> LA["legal-analyst 💤"]
    LH -.-> LC["legal-copywriter 💤"]

    LegalAdvisor -.->|при активации роль разделяется| LR
    LegalAdvisor -.-> LA
    LegalAdvisor -.-> LC
```

---

## В. Маршрут типовой задачи от входа до отчёта

```mermaid
flowchart TB
    Start(["Задача от Владельца<br/>(Telegram)"])
    Triage{"Координатор:<br/>определяет tier"}

    Start --> Triage

    Triage -->|XS: 1 файл, <1ч| OneDept["Координатор → Директор → Head → Worker"]
    Triage -->|S: 2–10 файлов, 1 отдел| OneDept
    Triage -->|M: модуль, 1 направление| OneDept
    Triage -->|L: фаза / многонаправленная| Multi["Координатор → несколько Директоров → Heads → Workers"]

    OneDept --> Work
    Multi --> Work

    Work["Сотрудники исполняют<br/>(backend-dev, qa, designer, ...)"]
    Work --> SelfCheck["Self-check сотрудника"]
    SelfCheck --> HeadRev["Первичное ревью у Начальника"]
    HeadRev --> DirRev["Финальное ревью у Директора"]
    DirRev --> Reviewer["reviewer до git commit"]
    Reviewer -->|approve| Commit["Координатор коммитит"]
    Reviewer -->|request-changes| Work
    Commit --> Report["Координатор отчитывается Владельцу в Telegram"]
    Report --> Memory[("Запись в память:<br/>project_tasks_log.md<br/>+ retros при закрытии фазы")]
```

---

## Г. Схема делегирования (кто кому может)

```mermaid
flowchart LR
    Owner["Владелец"]
    Coord["Координатор"]
    Dirs["Директора (7 активных + 1 dormant)"]
    Heads["Начальники / особые L3 (6 активных)"]
    Workers["Сотрудники (9 активных)"]
    Advisors["Советники (8)"]
    Rev["reviewer / security / governance-auditor"]
    Mem[("Память / Документы")]

    Owner -->|ставит| Coord
    Coord -->|делегирует| Dirs
    Coord -.->|консультации| Advisors
    Dirs -->|делегируют| Heads
    Dirs -.->|консультация| Advisors
    Heads -->|распределяют| Workers
    Heads -.->|Head↔Head: рутинное| Heads
    Dirs -.->|Директор↔Директор: серьёзное| Dirs

    Workers -.->|результат → ревью| Rev
    Rev -.->|вердикт| Coord
    Coord -.->|фиксация| Mem
```

**Правило кросс-вертикали (v1.4 §7.1):**
- Начальники разных направлений общаются между собой — можно (рутина)
- Директора разных направлений общаются — можно (серьёзное)
- Сотрудники разных направлений напрямую — **запрещено всегда**

---

## Д. Жизненный цикл задачи (статусы)

```mermaid
stateDiagram-v2
    [*] --> new: Задача пришла от Владельца
    new --> triaged: Координатор определил tier
    triaged --> delegated: Назначен исполнитель
    delegated --> in_progress: Работа начата
    in_progress --> needs_review: Код / артефакт готов
    needs_review --> approved: Ревью approve
    needs_review --> in_progress: Ревью request-changes
    needs_review --> failed: Ревью reject
    approved --> integrated: Координатор закоммитил
    integrated --> reported: Отчёт Владельцу в Telegram
    reported --> archived: Запись в память / retros
    archived --> [*]

    in_progress --> blocked: Внешний блокер
    blocked --> in_progress: Блокер снят
    in_progress --> needs_user_input: Нужно решение Владельца
    needs_user_input --> in_progress: Решение получено
    in_progress --> failed: Критический дефект без пути вперёд
    integrated --> rollback_required: Регрессия обнаружена
    rollback_required --> in_progress: Откат + переработка
```

**Комментарий к статусам:**
- `new / triaged / delegated` — в руках Координатора (классификация и назначение).
- `in_progress` — у исполнителя (Worker / Head).
- `needs_review` — у reviewer/security/Head/Директора — зависит от уровня задачи.
- `approved` — готово к коммиту.
- `integrated` — закоммичено, но ещё не отчитались Владельцу.
- `reported` — Владелец в курсе через Telegram.
- `archived` — записано в `project_tasks_log.md` (всегда) и в ретроспективу фазы (при закрытии фазы).

**Специальные состояния:**
- `blocked` — ждём внешнего (ответ от API, запуск сервиса, решение подрядчика).
- `needs_user_input` — нужно бизнес-решение Владельца, работа стоит.
- `failed` — критический дефект, работа невозможна в текущем подходе → эскалация Координатору, возможен `architect`-ревью для смены подхода.
- `rollback_required` — после `integrated` обнаружена регрессия в другой фиче → откат через git + переработка.

---

## Е. Как Governance и R&I встроены в поток

```mermaid
flowchart LR
    Work["Основной поток работы<br/>(фичи, Батчи)"]
    GovDir["governance-director"]
    GovAud["governance-auditor"]
    RI_Dir["ri-director"]
    RI_Scout["ri-scout"]
    RI_Anlst["ri-analyst"]

    Work -.->|еженедельный аудит| GovAud
    GovAud -->|отчёт| GovDir
    GovDir -->|заявки на правку| Req[(docs/governance/requests/)]
    Req -->|вердикт approve| Reg[(Регламентные документы)]
    Reg -.->|читают все субагенты| Work

    Scan["Внешние источники<br/>GitHub / Anthropic / HN / Simon Willison"] --> RI_Scout
    RI_Scout -->|находки + мини-брифы| Find[(findings.md + briefs/)]
    Find --> RI_Anlst
    RI_Anlst -->|RFC с расшифровкой| RFC[(rfc/)]
    RFC --> RI_Dir
    RI_Dir -->|weekly digest ПН 10:00| TG["Telegram Владельцу"]
    RI_Dir -->|решение pilot| Pilot["Пилот через backend-dev/qa<br/>(через Координатора)"]
```

**Ключевые артефакты цикла:**
- Governance: `docs/governance/audits/weekly/YYYY-MM-DD-*.md`, `docs/governance/requests/`, `docs/governance/CHANGELOG.md`
- R&I: `docs/research/findings.md`, `docs/research/briefs/<slug>.md`, `docs/research/rfc/rfc-NNN-*.md`

---

## Как обновлять схемы

1. **При создании нового агента** — добавить узел в соответствующую схему (оргструктура + департаментская).
2. **При активации dormant-агента** — заменить `💤` на `🟢`, убрать пунктирные стрелки.
3. **При изменении правил делегирования** — обновлять схему Г + соответствующий регламент через комиссию Governance.
4. **Проверка валидности** — `mermaid-cli` или `mermaid.live` перед коммитом.

---

# ДОБАВЛЕНИЕ 2026-04-16: схемы по v1.6 «Координатор-транспорт»

Три новых схемы, отражающих архитектуру «логическая иерархия + центральный оркестратор», по прямому указанию Владельца (Telegram msg 754). Источник данных связей — `delegation-rules.yaml`, источник схемы событий — `task-event-log.schema.yaml`.

## Ж. Логическая оргструктура (как Вы это видите)

На этой схеме видно **кто кому подчиняется логически**, как если бы субагенты могли физически делегировать друг другу. Это ментальная модель для Владельца и команды — ответственность, подчинение, ревью.

```mermaid
flowchart TB
    classDef owner fill:#262626,stroke:#ffffff,stroke-width:3.5px,color:#ffffff
    classDef coord fill:#202020,stroke:#ffffff,stroke-width:3.5px,color:#ffffff
    classDef director fill:#1f1f1f,stroke:#ffffff,stroke-width:3px,color:#ffffff
    classDef head fill:#181818,stroke:#dddddd,stroke-width:2px,color:#ffffff
    classDef worker fill:#151515,stroke:#cccccc,stroke-width:1.5px,color:#ffffff
    classDef staff fill:#181818,stroke:#888888,stroke-width:1.5px,color:#d0d0d0
    classDef dormant fill:#0a0a0a,stroke:#4a4a4a,stroke-dasharray:3 3,color:#777777

    OWNER[⬢ Владелец]:::owner
    COORD{{◈ Координатор}}:::coord
    OWNER --> COORD

    subgraph BE[Бэкенд]
      BD[backend-director]:::director
      BH[backend-head]:::head
      IH[integrator-head]:::head
      BDEV[backend-dev]:::worker
      INT[integrator]:::worker
      BD --> BH --> BDEV
      BD --> IH --> INT
    end

    subgraph QU[Качество]
      QD[quality-director]:::director
      QH[qa-head]:::head
      RH[review-head]:::head
      Q[qa]:::worker
      REV[reviewer]:::worker
      SEC[security]:::worker
      QD --> QH --> Q
      QD --> RH
      RH --> REV
      RH --> SEC
    end

    subgraph GO[Governance]
      GD[governance-director]:::director
      GA[governance-auditor]:::head
      GD --> GA
    end

    subgraph RI[R&I]
      RD[ri-director]:::director
      RS[ri-scout]:::head
      RA[ri-analyst]:::head
      RD --> RS
      RD --> RA
    end

    subgraph FR[Фронтенд]
      FD[frontend-director]:::director
      FH[frontend-head]:::head
      FDEV[frontend-dev]:::worker
      FD --> FH --> FDEV
    end

    subgraph DE[Дизайн]
      DD[design-director]:::director
      UH[ux-head]:::head
      DSG[designer]:::worker
      DD --> UH --> DSG
    end

    subgraph IN[Инфра]
      ID[infra-director]:::director
      DOH[devops-head]:::head
      DBH[db-head]:::head
      DO[devops]:::worker
      DBE[db-engineer]:::worker
      ID --> DOH --> DO
      ID --> DBH --> DBE
    end

    subgraph LE[Юр-вопросы dormant]
      LD[legal-director]:::dormant
    end

    COORD --> BD
    COORD --> QD
    COORD --> GD
    COORD --> RD
    COORD --> FD
    COORD --> DD
    COORD --> ID
    COORD -.-> LD

    subgraph ST[Штабные советники]
      ARC[architect]:::staff
      AN[analyst]:::staff
      LEG[legal]:::staff
      CE[construction-expert]:::staff
      TW[tech-writer]:::staff
      MK[memory-keeper]:::staff
      TU[tutor]:::staff
      DA[data-analyst]:::staff
    end
    COORD -.->|консультации| ST
```

Эта схема является логической проекцией: она показывает цепочку ответственности (`ri-director → ri-scout`), а не runtime-вызовы. Технически все вызовы проходят через Координатора-транспорт (см. следующую схему З). Для понимания команды и ответственности — логическая проекция корректна.

## З. Фактический runtime-flow (что происходит под капотом)

А так выглядит архитектура, как её видит платформа Claude Code: **все стрелки-запуски идут от одного центра — main-orchestrator (Координатор)**. Директора и Начальники — это субагенты, они не запускают других субагентов, они только возвращают `delegation_requested` событие, которое читает оркестратор.

```mermaid
flowchart TB
    classDef owner fill:#262626,stroke:#ffffff,stroke-width:3.5px,color:#ffffff
    classDef coord fill:#202020,stroke:#ffffff,stroke-width:3.5px,color:#ffffff
    classDef agent fill:#1f1f1f,stroke:#dddddd,stroke-width:2px,color:#ffffff

    OWNER[⬢ Владелец]:::owner
    COORD{{◈ main-orchestrator<br/>coordinator}}:::coord
    OWNER <-->|Telegram| COORD

    BD[backend-director]:::agent
    BH[backend-head]:::agent
    BDEV[backend-dev]:::agent
    QD[quality-director]:::agent
    RH[review-head]:::agent
    REV[reviewer]:::agent
    RD[ri-director]:::agent
    RS[ri-scout]:::agent
    RA[ri-analyst]:::agent
    MK[memory-keeper]:::agent

    COORD -->|spawn| BD
    COORD -->|spawn| BH
    COORD -->|spawn| BDEV
    COORD -->|spawn| QD
    COORD -->|spawn| RH
    COORD -->|spawn| REV
    COORD -->|spawn| RD
    COORD -->|spawn| RS
    COORD -->|spawn| RA
    COORD -->|spawn| MK

    BD -.->|delegation_requested| COORD
    BH -.->|delegation_requested| COORD
    QD -.->|delegation_requested| COORD
    RD -.->|delegation_requested| COORD

    BDEV -.->|result_returned| COORD
    BH -.->|result_returned + review| COORD
    BD -.->|review_completed| COORD
    REV -.->|review_completed| COORD
    RS -.->|result_returned| COORD
    RA -.->|result_returned| COORD
```

**Сплошные стрелки** — Координатор **запускает** субагента (тул-вызов `Agent(subagent_type=X)`).
**Пунктирные стрелки** — субагент **возвращает** событие (delegation_requested / result_returned / review_completed) в контекст Координатора.

Технически вся система — звезда с центром в Координаторе. Иерархия — на уровне данных (`requested_by` в каждом событии), не на уровне физических вызовов.

## И. Пример прохождения задачи (end-to-end)

Задача: Владелец в Telegram прислал «добавить Contract CRUD в бэкенд». Вот полная цепочка событий для tier=M задачи, в формате таймлайна:

```mermaid
flowchart TB
    classDef step fill:#1f1f1f,stroke:#ffffff,color:#ffffff
    classDef agent fill:#151515,stroke:#dddddd,color:#ffffff
    classDef artifact fill:#0a1a2a,stroke:#7c9fff,color:#dbeafe
    classDef memory fill:#2a1a4a,stroke:#a78bfa,color:#ede9fe

    T0(("⬢ Владелец в Telegram:<br/><i>добавить Contract CRUD</i>")):::step
    E1[task_created · source=telegram<br/>tier=M · direction=backend]:::step
    T0 --> E1

    E1 --> S1[COORD → backend-director:<br/>напиши бриф для backend-head]:::agent
    S1 --> E2[delegation_requested<br/>requested_by=coord → target=backend-director]:::step
    E2 --> E3[agent_spawned<br/>spawned_by=coord · target=backend-director]:::step
    E3 --> R1[backend-director возвращает бриф<br/>для backend-head + FILES_ALLOWED]:::agent
    R1 --> E4[result_returned<br/>from=backend-director · to=coord]:::step

    E4 --> S2[COORD → backend-head:<br/>дословный бриф Директора]:::agent
    S2 --> E5[delegation_requested<br/>requested_by=backend-director → target=backend-head]:::step
    E5 --> E6[agent_spawned<br/>spawned_by=coord · target=backend-head]:::step
    E6 --> R2[backend-head возвращает план распределения<br/>3 подзадачи для backend-dev]:::agent
    R2 --> E7[result_returned<br/>from=backend-head]:::step

    E7 --> S3[COORD → backend-dev ×3 параллельно:<br/>3 подзадачи с FILES_ALLOWED]:::agent
    S3 --> E8[3× agent_spawned<br/>target=backend-dev]:::step
    E8 --> R3[3 результата:<br/>code + tests + miграция]:::agent
    R3 --> E9[3× result_returned]:::step

    E9 --> S4[COORD → backend-head:<br/>первичное ревью]:::agent
    S4 --> E10[review_requested → backend-head]:::step
    E10 --> R4[backend-head: approve]:::agent
    R4 --> E11[review_completed<br/>reviewer=backend-head · approve]:::step

    E11 --> S5[COORD → backend-director:<br/>финальная приёмка]:::agent
    S5 --> E12[review_requested → backend-director]:::step
    E12 --> R5[backend-director: approve]:::agent
    R5 --> E13[review_completed<br/>reviewer=backend-director · approve]:::step

    E13 --> S6[COORD → reviewer:<br/>pre-commit на git diff --staged]:::agent
    S6 --> E14[review_requested → reviewer]:::step
    E14 --> R6[reviewer: approve]:::agent
    R6 --> E15[review_completed<br/>reviewer=reviewer · approve]:::step

    E15 --> C1[COORD: git commit + push]:::artifact
    C1 --> E16[memory_written<br/>project_tasks_log.md update]:::memory
    E16 --> E17[user_reported<br/>Telegram msg → Владельцу:<br/>Contract CRUD готов · commit &#60;sha&#62;]:::step
```

Всего на одну M-задачу — **17 событий**, **6 тул-вызовов Agent** (S1-S6), **5 ревью-точек** (Head → Director → reviewer), и только ОДИН коммит (C1) в финале. На дашборде Вы видите всё это живьём: по ленте проходят 17 событий, на схеме подсвечивается цепочка Координатор → Директор → Head → Workers, вспыхивает зелёным при approve.

## Как пользоваться схемами Ж-И

- **Схема Ж** — для обсуждения команды, ответственности, планирования. «Кто за это отвечает» → смотри reports_to.
- **Схема З** — для отладки платформенных ограничений. «Почему бот висит» → смотри runtime-flow.
- **Схема И** — как шаблон для task-routing-template.md. Новую задачу раскладываете по тем же стадиям.
