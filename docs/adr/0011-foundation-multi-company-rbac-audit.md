# ADR 0011 — M-OS-1 Foundation: Multi-company, Fine-grained RBAC, Crypto Audit

- **Статус**: утверждён (governance, 2026-04-17, вердикт docs/governance/verdicts/2026-04-17-adr-0011-verdict.md)
- **Дата**: 2026-04-16
- **Автор**: Архитектор (субагент `architect`, Claude Code)
- **Утверждающий**: governance-director, затем Владелец (Мартин)
- **Контекст фазы**: Фаза M-OS-1 «Скелет», Спринт 1 — Foundation Critical
- **Связанные документы**:
  - ADR 0001 (модель данных v1) — не ломать
  - ADR 0003 (auth MVP) — расширяется, не заменяется
  - ADR 0007 (audit log) — расширяется крипто-цепочкой
  - ADR 0008 (определение M-OS) — принципы 1, 5, 6, 10
  - ADR 0009 (pod-архитектура) — ядро общее, данные принадлежат компании
  - docs/legal/phase-3-legal-check.md — находки F-01 (file_id), F-04 (start/end dates)
  - docs/security/phase-3-owasp-sweep.md — FIND-02 (SELECT FOR UPDATE)
  - docs/m-os-vision.md §2 (принципы 5, 6, 10), §9 (M-OS-1 must-have: А1, А2, Е1)

---

## Проблема

Система находится в состоянии flat-модели: один `User`, одна роль из четырёх (owner, accountant, construction_manager, read_only), все объекты (Project, Contract, Payment, Contractor) в едином неразграниченном пространстве. AuditLog ведётся, но его записи ничем не защищены от подмены задним числом.

Это блокирует M-OS-1 по трём направлениям.

**Первое.** Холдинг Мартина — несколько юридических лиц: ООО «Металл», ООО «АЗС», ИП и другие. При добавлении gas-stations-pod бухгалтер АЗС не должен видеть договоры и платежи коттеджного девелопмента. При текущей flat-модели это физически невозможно: все объекты общие, фильтрация отсутствует. Принцип 5 ADR 0008 «Multi-company с первого дня» нарушен с момента появления второго юрлица в системе.

**Второе.** Четыре плоские роли описывают должность, но не объект и не действие. «Бухгалтер» — это единая роль для бухгалтера АЗС и бухгалтера строительства, хотя их объекты, суммы и процессы принципиально разные. Принцип 6 ADR 0008 «Доступ = роль + объект + действие» не реализован.

**Третье.** AuditLog по ADR 0007 содержит записи, которые можно удалить или изменить напрямую в PostgreSQL без какого-либо следа. Для системы с юридически значимыми согласованиями платежей, подписанием договоров и контролем доступа это означает отсутствие доказательной базы. Принцип 1 ADR 0008 «всё записывается» выполнен только наполовину: журнал есть, но он не является неизменяемым.

Дополнительно: модель `Contract` не хранит файл подписанного договора (F-01 legal) и не содержит сроков работ (F-04 legal). Оба поля добавляются в рамках той же миграции Foundation, что делает их частью этого ADR.

---

## Контекст

Текущие модели на момент написания ADR:

- `User`: email, password_hash, full_name, role (UserRole), is_active, last_login_at
- `Project`: code, name, description, status
- `Contract`: number, signed_at, amount_cents, subject, house_id, stage_id, status, contractor_id, project_id
- `Payment`: contract_id, amount_cents, paid_at, payment_method, status, approved_at, approved_by_user_id, rejected_at, rejected_by_user_id, rejection_reason
- `AuditLog`: user_id, action, entity_type, entity_id, changes_json, ip_address, user_agent, timestamp

`AuditLog` существующий — append-only по регламенту, но без технической гарантии неизменности.

Текущий RBAC реализован через декоратор `require_role` в FastAPI. Проверка: JWT payload содержит `role`, декоратор сопоставляет с кортежем допустимых ролей. Компании и pod-ы в проверку не входят.

Данный ADR фиксирует три архитектурных решения как единый блок: они взаимозависимы. RBAC зависит от multi-company (проверка прав включает company_id). Crypto audit покрывает оба изменения (любая смена роли или создание объекта компании пишется в цепочку).

---

## Решение

### Часть 1. Multi-company

#### 1.1. Новая модель Company

Вводится сущность `Company` — юридическое лицо холдинга.

```
Company:
  id:           int (PK, autoincrement)
  inn:          str(12) | None, unique среди active (партиальный индекс WHERE is_active=TRUE)
  kpp:          str(9) | None
  full_name:    str(512), NOT NULL
  short_name:   str(255), NOT NULL
  company_type: enum(ООО, АО, ИП, ДРУГОЕ), NOT NULL
  is_active:    bool, NOT NULL, default=True
  created_at:   timestamptz, NOT NULL, server_default=now()
  updated_at:   timestamptz, NOT NULL, server_default=now(), onupdate=now()
```

Поле `inn` nullable: seed-запись холдинга по умолчанию создаётся с `inn=None` (реальный ИНН вносится при настройке). Для production-записей `inn` обязателен на уровне бизнес-правил (валидация в сервисном слое), но не на уровне DDL — это позволяет безопасно seeding без подстановки заглушек.

Модель живёт в `backend/app/core/master_data/` (общее ядро по ADR 0009), таблица `companies`.

#### 1.2. Связь User — Company

Связь many-to-many реализована через промежуточную таблицу `user_company_roles`:

```
UserCompanyRole:
  id:            int (PK, autoincrement)
  user_id:       int, FK → users.id, NOT NULL
  company_id:    int, FK → companies.id, NOT NULL
  role_template: enum(owner, accountant, construction_manager, read_only), NOT NULL
  pod_id:        str(64) | None  -- если доступ ограничен конкретным подом
  granted_at:    timestamptz, NOT NULL, server_default=now()
  granted_by:    int | None, FK → users.id, SET NULL

  UNIQUE (user_id, company_id, role_template, pod_id)
```

Одна запись в `user_company_roles` = одна роль пользователя в одной компании, опционально в конкретном поде.

Пример: бухгалтер АЗС получает одну запись `(user_id=42, company_id=3, role=accountant, pod_id="gas_stations")`. Доступ только к объектам компании 3 внутри gas-stations-pod.

#### 1.3. company_id во всех объектах

Каждая сущность предметной логики получает `company_id: int, FK → companies.id, NOT NULL, index=True`.

Затронутые таблицы (существующие): `projects`, `contracts`, `contractors`, `payments`.

Правило: объект принадлежит компании. Запрос без явного `WHERE company_id = ?` (исходящего из токена пользователя) не допускается на уровне сервисного слоя.

Технически: базовый класс `CompanyScopedService` в ядре реализует метод `_scoped_query(user_context)`, который автоматически добавляет фильтр по `company_id`. Все сервисы предметной логики наследуют его.

**Payment получает собственный `company_id` (денормализация для быстрой фильтрации в `CompanyScopedService`).** Значение при create копируется из `Contract.company_id` — синхронно в сервисном слое, не триггером.

**Исключение — суперадмин.** Пользователь с `role_template=owner` и `company_id=NULL` в токене (специальный флаг `is_holding_owner: bool`) получает bypass company filter. Такого пользователя может создать только другой holding-owner. В системе должен всегда существовать хотя бы один holding-owner.

#### 1.4. Внутригрупповые сделки

В модели `Contract` добавляется поле:

```
is_internal:          bool, NOT NULL, default=False
counterparty_company_id: int | None, FK → companies.id
```

`is_internal=True` означает, что договор заключён между двумя юрлицами холдинга. `counterparty_company_id` — компания-вторая сторона. Это служит маркером для будущей консолидированной отчётности (elimination внутренних оборотов, ADR 0008 §8.9).

На M-OS-1 поля добавляются в модель, бизнес-логика консолидации — отдельный ADR при активации финансового контроллинга.

#### 1.5. Миграция существующих данных

При применении миграции Foundation выполняется однократный seed:

1. Создаётся запись `Company(id=1, inn=None, full_name="Холдинг (по умолчанию)", short_name="Холдинг", company_type=ООО)`. Поле `inn=None` допустимо: реальный ИНН вносится администратором при первичной настройке системы.
2. Все существующие записи в `projects`, `contracts`, `contractors`, `payments` получают `company_id=1`.
3. Для каждого существующего `User` создаётся запись `UserCompanyRole(user_id=X, company_id=1, role_template=<текущая роль пользователя>)`.
4. Поле `role` в таблице `users` не удаляется при upgrade — оставляется как deprecated с пометкой. Удаление — в отдельной миграции после стабилизации M-OS-1 и подтверждения, что все проверки прав идут через `UserCompanyRole`.

##### Downgrade strategy

Downgrade миграции Foundation выполняется в обратном порядке:

1. Удаляются таблицы `companies`, `user_company_roles`, `role_permissions` через `DROP TABLE CASCADE`. Каскад автоматически убирает FK-ограничения дочерних таблиц.
2. Поле `company_id` удаляется из всех затронутых таблиц: `ALTER TABLE projects DROP COLUMN company_id`, аналогично для `contracts`, `contractors`, `payments`.
3. Поле `role` в таблице `users` **не восстанавливается** при downgrade — оно не удалялось при upgrade (deprecated, но живо). После downgrade декоратор `require_role` снова читает его напрямую.
4. Поля крипто-цепочки (`prev_hash`, `hash`) в таблице `audit_log` удаляются через `ALTER TABLE audit_log DROP COLUMN prev_hash, DROP COLUMN hash`.
5. Round-trip (upgrade → downgrade → upgrade) обязан проходить чисто без ошибок. Это требование проверяется в CI как часть DoD каждого шага.

---

### Часть 2. Fine-grained RBAC v2

#### 2.1. Принцип проверки прав

Функция проверки права принимает три аргумента:

```
can(user_context, action: str, resource) -> bool
```

- `user_context` — объект с id пользователя и списком его `UserCompanyRole`
- `action` — строка: `"read"`, `"write"`, `"approve"`, `"delete"`, `"admin"`
- `resource` — объект с `company_id` и, опционально, `pod_id`

Логика:

1. Если `user_context.is_holding_owner=True` — возвращает `True` без дальнейшей проверки.
2. Иначе: фильтрует `UserCompanyRole` по `company_id == resource.company_id`.
3. Из отфильтрованных записей выбирает те, где `pod_id` совпадает с `resource.pod_id` или `pod_id IS NULL` (доступ ко всем подам компании).
4. По каждой подходящей роли проверяет матрицу `ROLE_PERMISSIONS[role_template][action]`.
5. Если хотя бы одна роль разрешает — возвращает `True`.

#### 2.2. Матрица прав (Configuration-as-data)

Матрица прав хранится в таблице `role_permissions` (принцип 10 ADR 0008 — configuration as data):

```
RolePermission:
  id:            int (PK)
  role_template: enum(owner, accountant, construction_manager, read_only)
  action:        str(64)       -- "read", "write", "approve", "delete", "admin"
  resource_type: str(64)       -- "contract", "payment", "project", "*"
  pod_id:        str(64) | None -- None = для всех подов
  is_allowed:    bool
```

Начальные значения матрицы загружаются seed-скриптом при миграции, соответствуют текущим четырём ролям:

| Роль | contract.read | contract.write | payment.approve | payment.read | payment.write |
|---|---|---|---|---|---|
| owner | + | + | + | + | + |
| accountant | + | + | - | + | + |
| construction_manager | + | - | - | + | - |
| read_only | - | - | - | + | - |

Матрица редактируется через будущий admin-UI (M-OS-1, ядро). До появления UI — через seed-скрипт при деплое. На M-OS-1 это сознательное временное отступление от полной editability; admin-UI для ролей — обязательная задача M-OS-1 (m-os-vision §9).

#### 2.3. Обновление декоратора require_role

Существующий декоратор `require_role` заменяется на `require_permission`:

```python
# Было:
@require_role(UserRole.OWNER, UserRole.ACCOUNTANT)

# Стало:
@require_permission(action="write", resource_type="contract")
```

Декоратор `require_permission`:
1. Получает текущего пользователя из JWT (как сейчас).
2. Строит `user_context` — загружает `UserCompanyRole` из БД (кешируется в Redis на M-OS-1 или в памяти на период сессии на M-OS-0).
3. Получает `resource` из параметров запроса (company_id берётся из объекта, который запрашивается).
4. Вызывает `can(user_context, action, resource)`.
5. При `False` — возвращает 403.

**Обратная совместимость.** На период миграции сохраняется `require_role` как обёртка поверх `require_permission` с маппингом старых ролей на новую проверку. Все 351 существующих тест продолжают работать: тестовые фикстуры создают пользователей с `UserCompanyRole` для company_id=1.

#### 2.4. Держатель контекста компании в JWT

JWT-токен расширяется: добавляются клеймы `company_ids: list[int]` и `is_holding_owner: bool`. Клеймы вычисляются при логине по записям `UserCompanyRole` пользователя.

При запросах с несколькими компаниями: клиент передаёт заголовок `X-Company-ID: <id>`. Если заголовок отсутствует и у пользователя одна компания — берётся она. Если несколько и заголовка нет — 400 Bad Request с понятным сообщением.

---

### Часть 3. Crypto Audit Chain

#### 3.1. Поле hash в AuditLog

Модель `AuditLog` получает два новых поля:

```
prev_hash: str(64) | None  -- hash предыдущей записи (NULL для первой)
hash:      str(64), NOT NULL  -- SHA-256 этой записи
```

Алгоритм вычисления `hash` при INSERT:

```
hash = SHA-256(
    prev_hash or SHA-256("genesis")
    + entity_type
    + str(entity_id or "")
    + action.value
    + str(user_id or "")
    + timestamp.isoformat()
    + json.dumps(changes_json, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
)
```

Все поля конкатенируются через разделитель `"|"` перед хешированием.

`prev_hash` при INSERT берётся из последней записи таблицы по глобальной последовательности (MAX id). Блокировка: `SELECT hash FROM audit_log ORDER BY id DESC LIMIT 1 FOR UPDATE` — это закрывает race condition (FIND-02 из OWASP sweep применим и здесь). Хеширование — O(1): только одна предыдущая запись, не вся цепочка.

Первая запись в системе: `prev_hash = None`, в хеш подставляется `SHA-256("genesis")`.

#### 3.2. Endpoint верификации цепочки

Новый endpoint в составе ядра:

```
GET /api/v1/audit/verify?from=<ISO8601>&to=<ISO8601>
```

Доступен только роли `owner` (is_holding_owner=True).

Логика: загружает все записи за период упорядоченно по `id`, пересчитывает каждый `hash` и сравнивает с сохранённым. Возвращает:

```json
{
  "status": "ok",
  "checked": 1240,
  "broken_links": []
}
```

или при обнаружении нарушения:

```json
{
  "status": "broken",
  "checked": 1240,
  "broken_links": [
    {"audit_log_id": 842, "reason": "hash_mismatch"}
  ]
}
```

Верификация — O(n) по записям периода. Для больших периодов (>100 000 записей) рекомендуется запускать задачей в фоне, не синхронно.

#### 3.3. Ретроактивная миграция

Однократный скрипт `scripts/audit_chain_backfill.py` вычисляет и проставляет `hash` для всех существующих записей `AuditLog` в порядке возрастания `id`. Первая запись использует `prev_hash = SHA-256("genesis")`, каждая следующая — хеш предыдущей. Скрипт идемпотентен: пропускает записи, у которых `hash` уже заполнен.

Скрипт запускается как часть процедуры деплоя после применения миграции, до открытия трафика.

---

### Часть 4. Дополнения к Contract (F-01, F-04 legal)

В модель `Contract` добавляются поля в рамках той же миграции Foundation:

```
file_id:    int | None  -- nullable int без FK; CHECK (file_id IS NULL) на M-OS-1
                        -- FK на таблицу files будет добавлен при создании файлового
                        -- хранилища (отдельный ADR M-OS-2)
start_date: date | None  -- дата начала работ по договору (ст. 708 ГК РФ)
end_date:   date | None  -- дата окончания работ по договору (ст. 708 ГК РФ)
```

`file_id` на M-OS-1 — заглушка: поле присутствует в схеме, FK отсутствует. Ограничение `CHECK (file_id IS NULL)` гарантирует, что никакой код не запишет значение до создания таблицы `files`. При введении файлового хранилища CHECK заменяется реальным FK в отдельной миграции.

`start_date` и `end_date` — nullable: не все договоры имеют фиксированные сроки в момент создания записи. Сервис предупреждает (не блокирует) если статус переходит в `active` без заполненных дат.

---

## Диаграмма

```
┌─────────────────────────────────────────────────────────────────┐
│                        ОБЩЕЕ ЯДРО M-OS                          │
│                                                                  │
│  ┌──────────────┐   ┌────────────────────────────────────────┐  │
│  │   Company    │   │          UserCompanyRole                │  │
│  │  (юрлицо)   │◄──│  user_id | company_id | role | pod_id  │  │
│  └──────┬───────┘   └────────────────────────────────────────┘  │
│         │                         ↑                              │
│         │                  JWT-клейм company_ids                 │
│         │                                                        │
│  ┌──────▼───────┐   ┌────────────────────────────────────────┐  │
│  │    User      │   │         can(user, action, resource)     │  │
│  │  (сотрудник) │──►│  → проверяет company_id + pod_id +     │  │
│  └──────────────┘   │    role_permissions matrix              │  │
│                      └────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                       AuditLog                             │ │
│  │  id | ... | prev_hash | hash (SHA-256 крипто-цепочка)     │ │
│  │  → /api/v1/audit/verify проверяет цепочку за период       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

         ↓ company_id во всех объектах пода ↓

┌────────────────────────────────────────────────────────┐
│              cottage-platform-pod                       │
│  Project(company_id)                                   │
│  Contract(company_id, file_id, start_date, end_date,   │
│           is_internal, counterparty_company_id)        │
│  Payment(company_id)  ← денормализован из Contract     │
│  Contractor(company_id)                                │
└────────────────────────────────────────────────────────┘
```

---

## Последствия

### Положительные

**Multi-company.** Бухгалтер АЗС не видит договоры коттеджей — требование Владельца выполнено. Добавление gas-stations-pod не требует архитектурной переработки ядра: добавляем Company, создаём UserCompanyRole для сотрудников. Консолидированная отчётность по холдингу возможна на уровне запросов с `is_holding_owner=True`.

**RBAC v2.** Права конфигурируются через данные, а не через код. Новая роль или новое ограничение — изменение строки в `role_permissions`, а не деплой. Принцип 10 ADR 0008 соблюдён.

**Crypto audit.** Подмена или удаление записи AuditLog обнаруживается при следующей верификации цепочки (`/api/v1/audit/verify`). Это придаёт журналу юридический вес: при споре с сотрудником или подрядчиком журнал доказывает целостность истории действий.

**Contract legal.** Поля `file_id`, `start_date`, `end_date` закрывают F-01 и F-04 из legal check. Модель соответствует ст. 708 ГК РФ.

### Отрицательные

**Overhead при каждом запросе.** Каждый HTTP-запрос теперь нагружает запрос к `user_company_roles` для построения `user_context`. Контрмера: кеш `user_context` на время сессии (в памяти на M-OS-1, Redis на M-OS-2). TTL кеша — 5 минут; при изменении ролей пользователя — инвалидация.

**Overhead при аудит-записи.** SHA-256 при INSERT добавляет ~1 мс на запись. `SELECT FOR UPDATE` на последнюю строку `audit_log` создаёт точку сериализации при конкурентных записях. Для MVP-нагрузки (десятки событий в секунду) некритично. При высокой конкурентности (M-OS-2+) — отдельная секционированная цепочка per-company или per-pod.

**Миграция ролей ломает текущий RBAC.** Существующий декоратор `require_role` должен быть обновлён или заменён обёрткой. Все 351 тест адаптируются: фикстура пользователя создаёт `UserCompanyRole` для company_id=1. Контрмера: `require_role` остаётся как deprecated alias до завершения M-OS-1.

---

## Риски

| Риск | Вероятность | Влияние | Контрмера |
|---|---|---|---|
| Scope creep: три больших изменения в одном спринте | Высокая | Среднее | Последовательная реализация: multi-company → RBAC → audit, каждый шаг с отдельным ревью. Не начинать следующую часть до закрытия предыдущей. |
| Обратная несовместимость тестов | Средняя | Высокое | Миграция создаёт `Company(id=1)` и маппит все роли. Фикстура `pytest` расширяется вспомогательной функцией `create_user_with_role(role, company_id=1)`. Все 351 тест должны пройти зелёными до мержа в main. |
| Разрастание user_context в JWT | Низкая | Среднее | JWT содержит только `company_ids: list[int]` и `is_holding_owner`. Детальные роли загружаются из БД при каждом запросе (с кешем). Токен не разрастается при добавлении новых компаний. |
| `SELECT FOR UPDATE` на audit_log — узкое место | Низкая на M-OS-1 | Высокое на M-OS-2+ | На M-OS-1 нагрузка пренебрежимо мала. При росте — секционирование `audit_log` по `company_id` и per-company цепочки. Перед переходом к M-OS-2 — нагрузочное тестирование. |
| Ретроактивный backfill audit нарушит работу | Низкая | Высокое | Скрипт запускается ДО открытия трафика, идемпотентен, останавливается при ошибке. После backfill — верификация через `/api/v1/audit/verify` за весь период. |
| Round-trip downgrade не проходит чисто | Средняя | Среднее | Downgrade strategy задокументирована явно (§1.5). DROP TABLE CASCADE и DROP COLUMN покрывают все зависимости. Проверяется в CI. |

---

## Что явно не входит в этот ADR

- Хранилище файлов (MinIO, S3, локальный диск): отдельный ADR M-OS-2 при реализации document management
- BPM-движок (процессы согласования): ADR 0009 описал намерение, реализация — отдельно в M-OS-1
- MFA для owner/accountant: ADR 0003 extension, отдельный спринт
- Event bus: ADR 0009 зафиксировал, реализация — отдельно в M-OS-1
- Frontend RBAC (отображение элементов по роли): отдельная задача фронтенда
- Интеграции с банками, 1С: M-OS-2
- Клиентские программы для покупателей коттеджей: после MVP внутренней системы
- Admin-UI для управления ролями и компаниями: отдельная задача M-OS-1 (этот ADR фиксирует data model и контракты, не интерфейс)
- FIND-02 из OWASP sweep (SELECT FOR UPDATE на Payment approve): решается при обновлении `PaymentService` на `CompanyScopedService` — approve вызывает `SELECT ... FOR UPDATE` на строку `Contract` перед проверкой лимита 120%
- Перенос бизнес-лимитов (`PAYMENT_OVERRUN_LIMIT_PCT`) в Configuration-as-data: отдельная задача M-OS-1

---

## Порядок реализации (рекомендация)

Шаг 1 **Multi-company** (db-engineer + backend-dev) — оценка: **1.5–2 недели**:
- Миграция: таблицы `companies`, `user_company_roles`, поле `company_id` во всех объектах, seed `Company(id=1, inn=None)`, маппинг ролей
- Базовый класс `CompanyScopedService` в ядре (включая денормализацию `company_id` в `Payment` из `Contract`)
- Обновление JWT: добавить `company_ids`, `is_holding_owner`
- Тесты: все зелёные
- DoD: round-trip миграции чистый, все 351 тест зелёные, мерж в main

Шаг 2 **RBAC v2** (backend-dev, зависит от шага 1) — оценка: **1.5–2 недели**:
- Таблица `role_permissions`, seed матрицы
- Функция `can(user_context, action, resource)`
- Декоратор `require_permission` + deprecated alias `require_role`
- Обновление всех endpoint-декораторов
- Тесты: все зелёные, включая граничные случаи (holding_owner bypass, cross-company block)
- DoD: тесты зелёные, мерж в main

Шаг 3 **Crypto Audit** (backend-dev, зависит от шагов 1 и 2) — оценка: **1–1.5 недели** (совместно с шагом 3a):
- Миграция: поля `prev_hash`, `hash` в `audit_log`
- Обновление сервиса аудита: `SELECT FOR UPDATE` + SHA-256
- Endpoint `/api/v1/audit/verify`
- Backfill-скрипт
- Тесты: верификация цепочки после 10+ записей, проверка обнаружения разрыва

Шаг 3a **Contract legal** (вместе с шагом 3 или отдельно) — входит в оценку шага 3:
- Миграция: `file_id` (nullable int, CHECK (file_id IS NULL)), `start_date`, `end_date`, `is_internal`, `counterparty_company_id` в `contracts`
- Обновление Pydantic-схем и сервиса Contract (предупреждение при active без дат)
- Тесты: создание Contract с датами и без
- DoD: тесты зелёные, мерж в main

**Итого: 4–5.5 недель (3 спринта, каждый с DoD и мержем в main).**

---

*ADR составлен субагентом `architect` (Claude Code) в рамках Фазы M-OS-1, Спринт 1 — Foundation Critical. Правки governance-комиссии (M1, M2, M3, m1–m5) применены 2026-04-16. Черновик передаётся governance-director для утверждения.*
