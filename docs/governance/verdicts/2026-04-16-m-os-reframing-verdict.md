# Вердикт комиссии — ADR 0009 + ADR 0010 (M-OS Reframing, Фаза M-OS-0)

**Дата:** 2026-04-16
**Председатель комиссии:** `governance-director`
**Тип решения:** финальный вердикт по заявке крупного amendment (CODE_OF_LAWS v1.0 → v1.1)
**Заявка:** `docs/governance/requests/2026-04-16-m-os-reframing.md`
**Аудит:** `docs/governance/audits/2026-04-16-adr-0009-0010-audit.md` (+ delta-review)

---

## 1. Предмет рассмотрения

Два архитектурных решения в рамках Фазы M-OS-0 «Reframing»:

- **ADR 0009** — Pod-архитектура M-OS: общее ядро, контракты данных, шина событий (249 строк).
- **ADR 0010** — Таксономия субагентов M-OS: пять типов `executive / core_department / domain_pod / governance / advisory` (~330 строк).

Оба ADR — фундамент M-OS-0, от их утверждения зависит последующая миграция документации, обновление Свода, bulk-правка frontmatter 48 файлов субагентов.

## 2. История рассмотрения

| Этап | Участник | Результат |
|---|---|---|
| 1. Черновики | `architect` (Советник) | Первая редакция ADR 0009 и 0010 опубликована в `docs/adr/` |
| 2. Первичный аудит | `governance-auditor` | `request-changes`: 1 critical + 3 major + 7 minor (файл аудита) |
| 3. Правки по замечаниям | `architect` | Закрыто 10 из 11 полностью, 1 partially (арифметика §5 ADR 0010) |
| 4. Delta-review | `governance-auditor` | `approve-with-minor-changes` — остался только M1 (арифметика) |
| 5. Закрытие M1 | `architect` | §4 и §5 ADR 0010 сведены: 48 файлов + 1 coordinator без файла = 49 агентов |
| 6. Обзор Координатора | Координатор | `approve` — технических возражений и практической значимости нет |
| 7. **Финальный вердикт** | **`governance-director`** | **Настоящий документ** |

## 3. Мнения комиссии

### 3.1 `governance-auditor` — approve-with-minor-changes (до закрытия M1)

Цитата из delta-review (`docs/governance/audits/2026-04-16-adr-0009-0010-audit.md`, секция «Delta-review 2026-04-16»):

> 10/11 закрыто полностью, 1/11 partially. M1 (остаток): coordinator (executive без файла) учтён как «1 файл» в колонке «Количество файлов» таблицы §5 ADR 0010. Сумма строк = 49, а итог = 48. Правка: в колонке «Количество файлов» для executive поставить «0»… В §4 финальная сводка — переписать: «48 файлов агентов + 1 coordinator без файла = 49 агентов нашей системы». Не блокирует M-OS-0 — одна строка правки. Рекомендация Директору: подписать approve-with-minor-changes.

Сверка сегодня (после правок architect): в §5 ADR 0010 для `executive` стоит «0 (coordinator — без файла в `~/.claude/agents/`; это сам Claude Code)», итог файлов = 48, всего агентов системы = 49. Сумма строк: 0 + 38 + 1 + 2 + 7 = 48 — сходится. В §4 явная сводка: «48 файлов агентов + coordinator (executive без файла) = 49 агентов нашей системы». **M1 закрыто.**

### 3.2 `architect` — автор, проходил через два раунда правок, представил финальную редакцию

Позиция не фиксируется отдельным голосом — автор черновика не голосует, отвечает за соответствие правкам. Три стратегических развилки (5-й тип `executive`, единое имя `cottage-platform-pod`, `legal-director` как `core_department`) решены Владельцем (Telegram msg 867) и отражены в ADR 0010 §«Принятые решения по открытым вопросам». Это не компромисс комиссии, а директива L0 — пересмотру не подлежит.

### 3.3 Координатор — approve

Цитата из постановки задачи (формулировка Координатора при передаче мне на финальный вердикт):

> Я прошёл все изменения, согласен со всеми решениями Владельца (5-й тип executive, cottage-platform-pod единое имя, editability принцип 10, legal-director как core_department). Технических возражений нет, практической значимости — нет.

Координатор покрывает два аспекта обязательной комиссии (§6 заявки): «подписант финального approve» и «понятно ли новому члену команды». Оба закрыты.

### 3.4 `governance-director` (председатель) — собственная проверка

**Формальное соответствие CODE_OF_LAWS:**

- Иерархия L0–L4 (ст. 9) не меняется. ADR 0010 §«Контекст» явно: «Этот ADR не меняет иерархию — он добавляет ортогональное измерение» — корректно.
- Строгая цепочка делегирования (ст. 12, CLAUDE.md раздел «Процесс», правило Мартина msg 665): типы `core_department` и `domain_pod` работают по той же вертикали Координатор → Директор → Head → Worker. `advisory` остаётся исключением «вне иерархии» — совпадает со статусом Советников. `executive` — новый тип для L1, устраняет прежнюю неоднозначность Координатор vs `governance-director`. **Цепочка не нарушена.**
- Приоритет коллизий (`departments/governance.md` §«Приоритет коллизий»): `agent_type` во frontmatter — уровень 6 (самый низкий). Никогда не переопределит CLAUDE.md, Свод, addendum'ы, departments, ADR. **Иерархия выдержана.**
- Координатор-транспорт (v1.6): ADR 0010 не затрагивает механику Agent-вызовов. **Не пересекается.**
- Определение `advisory` («вне иерархии, без подчинённых») — после исправления M8 соблюдено: `legal-director` получил тип `core_department` dormant, при активации встанет в вертикаль Директор → Head → Worker.

**Практическая исполнимость:**

- Миграция `docs/phases/` → `docs/pods/cottage-platform/phases/` — технически выполнимо через `git mv`, в заявке §9 День 6 прописан pre-check grep'ом и sed-replace. Опасность — битые ссылки в памяти и past-коммитах — закрыта через массовый post-check. Приемлемо.
- Bulk-правка 48 frontmatter — ADR 0010 §Риски строка 305 теперь включает контрмеру M5: `yaml.safe_load` каждого файла, откат из backup при падении, тестовый прогон на 2–3 файлах. Приемлемо.
- Батч C Phase 3 не блокируется (заявка §2.3, ADR 0009 §«Что явно не входит» m6): новый код до M-OS-1 пишется в `backend/app/`, не в pod-структуре. Параллельная работа без конфликтов.
- Публичное зеркало `coordinata56-docs` синхронизируется в последнюю очередь, после merge в main (заявка §5 и §8.3 п.5) — правильно.

**Согласованность с ADR 0001–0008:**

- ADR 0001–0007 не затрагиваются (заявка §2.3) — это технические решения конкретного pod'а, остаются действующими.
- ADR 0008 — имя пилот-пода было `coordinata56-pod`, в ADR 0009/0010 — `cottage-platform-pod`. Проверка по тексту ADR 0009 (строки 30, 73, 207, 218) и ADR 0010 (строки 51, 60, 228) — теперь везде `cottage-platform-pod`. Это закрытие M7. **Требуется amendment к ADR 0008** — короткая запись «имя пилот-пода уточнено: `cottage-platform-pod`» — включён в план ниже как параллельный артефакт.

**Собственные замечания сверх delta-review auditor'а — нет.** Комиссия исчерпала содержательные замечания на этапах 2–5.

---

## 4. Вердикт комиссии

# **APPROVE**

ADR 0009 и ADR 0010 **утверждены**. Готовы к применению — запуск миграционных работ М-OS-0 разрешён Координатору немедленно после публикации настоящего вердикта.

**Основания:**

1. Консенсус обязательных участников комиссии достигнут (governance-director + governance-auditor + architect + Координатор = 4/4 approve). Критерий §6 заявки выполнен.
2. Одна критичная находка (C1), четыре major (M1, M2, M7, M8) и все применимые minor закрыты полностью. Оставшийся M1 (арифметика §5 ADR 0010) устранён architect'ом после delta-review: сумма колонки «файлы» = 48, «Всего агентов системы» = 49 — сходится.
3. Концептуальных проблем с иерархией L0–L4, цепочкой делегирования, приоритетом коллизий нет. Таксономия — ортогональное измерение, не конкурирует со Сводом.
4. Практическая исполнимость подтверждена: миграция документации, обновление yaml-карты, bulk-правка frontmatter — прописаны с контрмерами для каждого из рисков R1–R7 заявки.
5. Согласованность с ADR 0001–0008: единственное расхождение (имя пилот-пода в ADR 0008) закрывается amendment'ом в том же коммите M-OS-0 — см. план ниже.
6. Решения Владельца (Telegram msg 856, 867) по стратегическим развилкам отражены в ADR точно и пересмотру не подлежат.

**Решение `m10` (tech-writer/memory-keeper как advisory, но участвуют в bulk-правке 48 файлов)** — принято как deferred: прецедент «advisory получает исполнительскую задачу через Координатора-транспорт» допустим разово на M-OS-0, но регулярные исполнительские задачи из их frontmatter'а должны уходить `core_department`-агентам. Для систематизации — отдельная заявка в regulations_addendum_v1.7 позднее, не блокер сейчас.

---

## 5. План немедленных действий (после утверждения)

План расставлен в том порядке, в котором Координатор должен его исполнить. Все правки собираются в **один атомарный коммит** (заявка §8.3 п.1). Никто из комиссии не делает git-операций — коммитит Координатор.

### 5.1 Pre-migration подготовка

- [ ] **Бэкап папок** (обратимость, заявка §5):
  - `cp -r /root/.claude/agents /root/.claude/agents.pre-m-os-0.bak`
  - `cp -r /root/coordinata56/docs /root/coordinata56/docs.pre-m-os-0.bak` (или снапшот через tar)
- [ ] **Pre-check входящих ссылок** на мигрируемые пути (заявка §6.R4):
  - `grep -rn "docs/phases/\|docs/stories/\|docs/wireframes/\|docs/specs/" /root/coordinata56/docs /root/.claude/ /root/coordinata56/CLAUDE.md`
  - Вывод сохранить в `/tmp/m-os-0-references.txt` для sed-replace
- [ ] Проверить отсутствие активных параллельных коммитов Батча C Phase 3 (чтобы не смерджились случайно).

**Ответственный:** Координатор.

### 5.2 ADR 0008 amendment (M7 единое имя пода)

- [ ] В `docs/adr/0008-m-os-system-definition.md` в секции «Модульная структура (поды)» таблицы: `coordinata56-pod → cottage-platform-pod` (везде, где встречается). В конец ADR добавить короткий блок:

```
## Amendment 2026-04-16

Имя пилот-пода уточнено: `cottage-platform-pod` вместо исходного `coordinata56-pod`.
Обоснование: универсальность имени (pod-тип = «платформа коттеджей», а не имя одного проекта).
Имя проекта `coordinata56` сохраняется как идентификатор первого посёлка.
Утверждено: ADR 0009 и ADR 0010 (governance-approve 2026-04-16), комиссия Governance.
```

- [ ] Параллельная правка `docs/m-os-vision.md` §3.2 (таблица подов) — то же переименование.

**Ответственный:** Координатор (правка короткая, не требует architect'а).

### 5.3 Обновление CODE_OF_LAWS (v1.0 → v1.1)

Правки — по шаблону заявки §7.2, строго точечно:

- [ ] **Статья 1** — переформулирована под M-OS (формулировка в заявке §7.2).
- [ ] **Статья 2** — добавить предложение про фазы M-OS-0 — M-OS-5.
- [ ] **Статья 9** — **без изменения уровней**, добавить **Примечание** про таксономию 5 типов из ADR 0010 (в заявке указано «4 типа», но после решения Владельца msg 867 типов стало **5** — учесть при формулировке: «executive, core_department, domain_pod, governance, advisory»).
- [ ] **Статья 29–30** — в таблице департаментов добавить столбец «таксономия».
- [ ] **Статья 46** — добавить ADR 0008 (утверждён), ADR 0009 (утверждён настоящим вердиктом), ADR 0010 (утверждён настоящим вердиктом), а также ADR 0008 Amendment от 2026-04-16.
- [ ] **Новая Книга VII «Pod-архитектура и таксономия»** — статьи 57–61 (перечень в §7.2 заявки).
- [ ] **Приложение А** — перерисовать карту документов под pod-структуру.
- [ ] **История версий** — запись v1.1 (формулировка в §7.2 заявки).

**Ответственный:** Координатор (правка регламента — моя зона, но сам коммит делает Координатор; я ревьюю diff).

### 5.4 Миграция документации (pod-specific → `docs/pods/cottage-platform/`)

Строго в таком порядке:

- [ ] `git mv /root/coordinata56/docs/phases/ /root/coordinata56/docs/pods/cottage-platform/phases/`
- [ ] `git mv /root/coordinata56/docs/stories/ /root/coordinata56/docs/pods/cottage-platform/stories/` (если существует)
- [ ] `git mv /root/coordinata56/docs/wireframes/ /root/coordinata56/docs/pods/cottage-platform/wireframes/` (если существует)
- [ ] `git mv /root/coordinata56/docs/specs/ /root/coordinata56/docs/pods/cottage-platform/specs/` (если существует)
- [ ] `git mv /root/coordinata56/docs/phase-3-checklist.md /root/coordinata56/docs/pods/cottage-platform/phase-3-checklist.md` (если существует — проверить: в `docs/` я вижу только `docs/agents/phase-3-checklist.md`, он остаётся)
- [ ] **Массовый sed-replace** старых путей в оставшихся файлах (по `/tmp/m-os-0-references.txt`):
  - `docs/phases/ → docs/pods/cottage-platform/phases/`
  - аналогично для остальных
- [ ] **Post-check:** повторить `grep -rn "docs/phases/\|docs/stories/\|docs/wireframes/\|docs/specs/"` — должен дать 0 совпадений по старым путям.

**Ответственный:** Координатор.

### 5.5 Обновление `agents-system-map.yaml` (= `agents-map.yaml` фактически)

В репозитории файл называется `docs/agents/agents-map.yaml` (проверено), не `agents-system-map.yaml`. В заявке — упомянут и тот и другой. Истина: один файл `agents-map.yaml` + один документ `agents-system-map.md`.

- [ ] **Добавить поле `agent_type`** (не `taxonomy` — согласно ADR 0010 §2 формулировка «agent_type в frontmatter» и §4 мэппинг) в каждую запись `agents-map.yaml` по таблицам §4 ADR 0010. Значения: `executive` (1), `core_department` (38), `domain_pod` (1), `governance` (2), `advisory` (7).
- [ ] В блок `meta:` добавить поле: `taxonomy_source_of_truth: docs/adr/0010-subagent-taxonomy.md`.
- [ ] Обновить `docs/agents/agents-system-map.md` — раздел «Таксономия»: описание 5 типов, ссылка на ADR 0010.
- [ ] Обновить `docs/agents/agents-diagrams.md` — Mermaid-схемы: добавить цветовую кодировку по agent_type (5 цветов), отметить `cottage-platform-pod` как отдельный контейнер для `domain_pod`-агента (`construction-expert`).

**Ответственный:** Координатор (с привлечением `memory-keeper` или `tech-writer` как исполнителя на bulk-правку yaml — консультация через меня не требуется, задача техническая).

### 5.6 Bulk-правка 48 frontmatter агентов

**Критически важное правило (ADR 0010 §Риски R2 + заявка §6.R3 + глобальный CLAUDE.md «Безопасность»):**

- [ ] **Сначала dry-run на 2–3 файлах** (`architect.md`, `construction-expert.md`, `coordinator.md` если есть, или любые три из 48). Проверить `python3 -c "import yaml; print(yaml.safe_load(open('~/.claude/agents/X.md').read().split('---')[1]))"` для каждого.
- [ ] Если dry-run чист — запустить **скрипт с yaml-парсером** (не `sed`) на все 48 файлов.
- [ ] Поле: `agent_type: <executive|core_department|domain_pod|governance|advisory>` согласно таблице §4 ADR 0010. Значения подставить **точно по таблицам** L2/L3/L4/Советники/параллельные слоты.
- [ ] **Валидация:** для каждого файла — `yaml.safe_load` на frontmatter; при падении — откат из `~/.claude/agents.pre-m-os-0.bak`.
- [ ] **Smoke-test:** запустить любые 3 агента через Agent-tool, проверить что загружаются без ошибок.

Распределение по типам для проверки итога:
- `executive`: 0 файлов (coordinator — без файла)
- `core_department`: 38 файлов
- `domain_pod`: 1 файл (`construction-expert.md`)
- `governance`: 2 файла (`governance-director.md`, `governance-auditor.md`)
- `advisory`: 7 файлов (`architect.md`, `analyst.md`, `legal.md`, `tech-writer.md`, `memory-keeper.md`, `tutor.md`, `data-analyst.md`)
- **Сумма: 48** — сходится.

Отдельно: `security.md` — `core_department` (закрытие C1).

**Ответственный:** Координатор (или делегирование `memory-keeper`/`tech-writer` с обязательной самопроверкой).

### 5.7 Обновление `departments/*.md` (8 файлов)

- [ ] В каждом `docs/agents/departments/<name>.md` добавить преамбулу:
  - `backend.md`, `quality.md`, `research.md`, `governance.md`, `frontend.md`, `design.md`, `infrastructure.md`, `legal.md` — все 8 относятся к типу `core_department` (или в случае `governance.md` — тип `governance`).
- [ ] Формат преамбулы (одна строка): `**Таксономия:** все агенты отдела — тип `core_department` по ADR 0010` (или `governance` для одноимённого отдела).

**Ответственный:** Координатор (это преамбула, не содержательная правка — можно единым sed-скриптом или вручную по 8 файлам).

### 5.8 Обновление `/root/coordinata56/CLAUDE.md`

- [ ] Одна строка в раздел «Процесс» (заявка §2.1 и §7.2):
  - `- **Pod-архитектура и таксономия субагентов.** M-OS построена на подах (ADR 0008/0009), субагенты классифицированы по 5 типам (ADR 0010: executive / core_department / domain_pod / governance / advisory). Любое изменение состава общего ядра или добавление нового типа субагента — через ADR, не молча.`

**Ответственный:** Координатор.

### 5.9 Запись в `docs/governance/CHANGELOG.md`

- [ ] Добавить блок (формат CHANGELOG):

```
## 2026-04-16 — M-OS Reframing: ADR 0008 amendment + ADR 0009 + ADR 0010, CODE_OF_LAWS v1.1
- **Заявка:** `docs/governance/requests/2026-04-16-m-os-reframing.md`
- **Вердикт комиссии:** `docs/governance/verdicts/2026-04-16-m-os-reframing-verdict.md`
- **Аудит:** `docs/governance/audits/2026-04-16-adr-0009-0010-audit.md`
- **Документы (новые):**
  - `docs/adr/0009-pod-architecture.md` — pod-архитектура M-OS
  - `docs/adr/0010-subagent-taxonomy.md` — 5 типов субагентов
- **Документы (правки):**
  - `docs/adr/0008-m-os-system-definition.md` — Amendment: имя пилот-пода `cottage-platform-pod`
  - `docs/m-os-vision.md` §3.2 — та же правка имени
  - `docs/agents/CODE_OF_LAWS.md` — ст. 1, 2, 9, 29–30, 46, новая Книга VII, Приложение А, История версий v1.1
  - `docs/agents/agents-map.yaml` — поле `agent_type` для каждой записи, meta.taxonomy_source_of_truth
  - `docs/agents/agents-system-map.md` — раздел «Таксономия» под 5 типов
  - `docs/agents/agents-diagrams.md` — Mermaid под pod-структуру и agent_type
  - `docs/agents/departments/*.md` (8 файлов) — преамбула с таксономией
  - `/root/coordinata56/CLAUDE.md` — строка про pod-архитектуру и таксономию
  - `~/.claude/agents/*.md` (48 файлов) — поле `agent_type` во frontmatter
- **Миграция (git mv):**
  - `docs/phases/` → `docs/pods/cottage-platform/phases/`
  - `docs/stories/`, `docs/wireframes/`, `docs/specs/` (если существуют) → `docs/pods/cottage-platform/{stories,wireframes,specs}/`
- **Мотивация:** стратегическое решение Владельца (Telegram msg 808-856, 867) перевести проект в M-OS; перестройка Свода под pod-архитектуру.
- **Вердикт:** approved (консенсус комиссии 4/4; 10/11 находок аудита закрыто полностью, 1/11 доработано post-factum architect'ом).
- **Аудитор:** clean — после правок architect'а C1+M1-M8 и все применимые minor закрыты. Deferred: m10 (tech-writer/memory-keeper в bulk-правке — прецедент, не регулярная практика; систематизировать в regulations_addendum_v1.7).
```

**Ответственный:** Координатор (записывает в коммите; я, `governance-director`, финальный апрув diff'а).

### 5.10 Reviewer перед коммитом и атомарный коммит

- [ ] **`reviewer`** по staged diff (CLAUDE.md раздел «Процесс», v1.3 §1) — до `git commit`.
- [ ] **Атомарный коммит** (заявка §8.3 п.1), формат:

```
docs(m-os): M-OS-0 Reframing — ADR 0008 amendment + ADR 0009/0010 approved, CODE_OF_LAWS v1.1, pod-architecture migration

Approve ADR 0009 (pod-architecture) and ADR 0010 (subagent taxonomy, 5 types).
Amendment ADR 0008: pilot pod renamed coordinata56-pod → cottage-platform-pod.
CODE_OF_LAWS bumps v1.0 → v1.1 with Book VII (pod-architecture & taxonomy).
Migrate docs/phases|stories|wireframes|specs → docs/pods/cottage-platform/.
Bulk-add agent_type frontmatter to 48 subagent files per ADR 0010 mapping.
Governance verdict: docs/governance/verdicts/2026-04-16-m-os-reframing-verdict.md.
```

- [ ] **Синхронизация публичного зеркала** `coordinata56-docs` — **в последнюю очередь**, после merge в main (заявка §5 и §8.3 п.5).

**Ответственный:** Координатор.

### 5.11 Финальное уведомление

- [ ] Координатор сообщает Владельцу: «M-OS-0 Reframing завершена. CODE_OF_LAWS v1.1, ADR 0009+0010 действуют. Готовность к M-OS-1 подтверждена.» (заявка §9 День 8).

---

## 6. Что остаётся после коммита

- **Weekly audit 2026-04-22** (по расписанию `governance-auditor`): подтвердить консистентность yaml ↔ файлов `~/.claude/agents/` ↔ ADR 0010, проверить что нет «битых ссылок» на старые пути `docs/phases/*`.
- **Deferred-заявка** в regulations_addendum_v1.7: систематизация правил «может ли `advisory` получать исполнительскую задачу» (m10).
- **ADR 0009 §«Что явно не входит»** — новый технический RFC по брокеру сообщений (R&I, Фаза M-OS-2), отдельный ADR по multi-company (Фаза M-OS-1), отдельный ADR по оффлайн-синхронизации мобильных.
- **Правило для `memory-keeper`** (рекомендация аудитора): при добавлении нового типа субагента — обязательная проверка всех списков примеров во всех разделах ADR для предотвращения повторения C1. Зафиксировать в памяти.

---

## 7. Сводка для Координатора (одной строкой)

**Вердикт: APPROVE.** ADR 0009 и ADR 0010 утверждены. Запускайте миграцию M-OS-0 по плану §5 настоящего документа. Все правки — в один атомарный коммит. Публичное зеркало — в последнюю очередь.

---

*Вердикт вынесен `governance-director` 2026-04-16 в рамках SLA комиссии (≤2 рабочих дня от подачи заявки; фактически — в ту же сессию после закрытия всех находок аудита).*
