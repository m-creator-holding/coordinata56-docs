# ADR-0025 (Draft) — 1С:Предприятие Integration Adapter

- **Статус**: draft (требует ratification governance-director перед переводом в enabled_mock)
- **Дата создания**: 2026-04-19
- **Автор**: integrations-head (субагент L3), делегировано от backend-director
- **Контекст фазы**: M-OS-2 (запланировано), скелет создан в M-OS-1 как адаптер на полке
- **Решение Владельца**: 1С — первый приоритет интеграций (msg 1411, 2026-04-18)
- **Текущее состояние адаптера в integration_catalog**: `written` (ADR-0015 seed)

**Связанные документы**:
- ADR-0014 (Anti-Corruption Layer) — каркас адаптеров, три состояния, guard
- ADR-0015 (Integration Registry) — реестр, таблица `integration_catalog`, seed
- ADR-0018 (Production Gate Definition) — условия перевода в `enabled_live`
- `docs/m-os-vision.md` §3.4 — 1С как первая интеграция в Vision
- `CODE_OF_LAWS.md` ст. 45а/45б — запрет живых вызовов без production-gate

---

## Проблема

1С:Предприятие является основной учётной системой холдинга. M-OS требует двусторонней синхронизации данных:
- Контрагенты из 1С → база M-OS (избегаем двойного ввода)
- Платежи из M-OS → 1С (фиксация в бухгалтерском учёте)
- Акты выполненных работ из 1С → M-OS (сверка с договорами и бюджетами)

Без формального адаптера-скелета существует риск: при наступлении M-OS-2 разработчик начнёт писать HTTP-вызовы к 1С прямо в бизнес-логике, минуя ACL (Anti-Corruption Layer). ADR-0014 явно запрещает такой подход.

Данный ADR закрепляет архитектурные решения для будущей реализации, пока адаптер находится на полке.

---

## Контекст

**Что уже есть (M-OS-1, скелет на полке):**
- `backend/app/integrations/onec/` — модуль с четырьмя файлами (client, schemas, mapper, service)
- Состояние в `integration_catalog`: `written`, `enabled=False`
- Полный mock-транспорт (`OneCMockTransport`) с тремя сценариями
- 25+ unit-тестов, все проходят без сетевых вызовов
- Dev-trigger endpoint (`POST /dev/integrations/onec/test-sync`) — только dev-env

**Ограничения:**
- Живые вызовы к 1С запрещены до production-gate (CODE_OF_LAWS ст. 45а/45б)
- Первый живой вызов — только после явного решения Владельца
- 1С-инсталляция холдинга — внутренний сервер, не облако; URL и порт определяются при настройке

---

## Рассмотренные варианты подключения к 1С

### Вариант A — REST через HTTP-публикацию 1С (выбранный)

1С:Предприятие поддерживает публикацию информационной базы через веб-сервер (Apache/IIS) с REST API (odata/standard.odata или hs/-маршруты).

**Плюсы:**
- Стандартный протокол, нет специфических зависимостей на стороне M-OS
- Basic Auth из коробки; опционально — OAuth2
- Поддерживается в 1С 8.3+ (широко распространена)
- Синхронные и асинхронные режимы

**Минусы:**
- Необходима настройка HTTP-публикации на сервере 1С (задача DevOps)
- Basic Auth — слабее OAuth2; для production рекомендуется переход на OAuth2 или mTLS
- Скорость зависит от нагрузки на 1С-сервер

**Вердикт**: принимается как основной подход для MVP.

### Вариант B — COM-интерфейс / V8.ComConnector

Прямое COM-подключение к 1С (только Windows-среды).

**Минусы**: требует Windows-сервера для M-OS, нарушает принцип платформонезависимости (Linux-deploy). Отклонён.

### Вариант C — Обмен через файлы (XML, CSV)

Пакетная выгрузка/загрузка через файловый обмен.

**Минусы**: нет возможности near-realtime синхронизации; управление файлами усложняет операционку; в 2024 году это устаревший подход для B2B-интеграции. Отклонён.

### Вариант D — Брокер событий (Kafka/RabbitMQ между 1С и M-OS)

Асинхронный обмен через message broker.

**Плюсы**: высокая надёжность, развязка.
**Минусы**: требует настройки брокера как в 1С (через расширения / внешние компоненты), так и в M-OS; избыточно для первого MVP-цикла синхронизации; вернуться в M-OS-3 если объём синхронизации вырастет.

---

## Решение (принятый подход для реализации в M-OS-2)

**REST API через HTTP-публикацию 1С + Basic Auth → OAuth2/mTLS при production-gate.**

### Структура модуля

```
backend/app/integrations/onec/
  __init__.py    — документация модуля, статус адаптера
  client.py      — OneCClient (httpx), OneCConfig, CircuitBreaker, OneCMockTransport
  schemas.py     — Pydantic DTO: OneCContractorDTO, OneCPaymentDTO, OneCActDTO, OneCAccountDTO
  mapper.py      — маппинг 1С DTO ↔ ContractorCreate, PaymentCreate
  service.py     — OneCService: sync_contractors, post_payment, fetch_acts
```

### ACL-изоляция (ADR-0014)

Адаптер НЕ наследует `IntegrationAdapter` напрямую в скелете — базовый класс ещё не реализован в коде (DoD ADR-0014 Sprint 3). При реализации базового класса (`backend/app/core/integrations/base.py`) — OneCService подключается к нему. Текущий guard реализован встроенным методом `_guard_live_call()` в OneCClient, который в состоянии `written` всегда бросает `OneCLiveCallForbiddenError`.

### Жизненный цикл (ADR-0014 + ADR-0015)

```
written (сейчас) → enabled_mock (M-OS-2, dev-тест) → enabled_live (production-gate)
```

| Переход | Условие |
|---|---|
| written → enabled_mock | Решение governance-director + ratification ADR-0025 |
| enabled_mock → enabled_live | Production-gate: юрист + Владелец + ADR-0018 |

### Конвертация данных

- Суммы: 1С хранит в рублях (float), M-OS — в копейках (int). Правило: `round(rubles * 100)`.
- Даты: 1С может возвращать naive datetime. Адаптер приводит к UTC timezone-aware.
- Пустые строки: 1С возвращает `""` вместо `null` — нормализуются в `None` в Pydantic validator.

### Маскирование ПД

ИНН в логах маскируется (последние 4 символа): `****3893`. Конституция ст. 84-85.

### Retry и отказоустойчивость

- Таймаут: 15 сек (read), 5 сек (connect)
- Retry: до 3 раз с exponential backoff (1, 2, 4 сек)
- Circuit Breaker: 5 последовательных сбоев → OPEN (60 сек recovery)

---

## Что нужно для перевода в enabled_mock (M-OS-2)

1. Ratification данного ADR governance-director
2. Реализация `IntegrationAdapter` базового класса (ADR-0014 DoD, Sprint 3)
3. Подключение OneCService к `IntegrationRegistry.get_state()` вместо встроенного guard
4. DevOps: настройка HTTP-публикации 1С в dev-окружении (внутренний сервер)
5. Заполнение `ONEC_BASE_URL` в dev `.env` (не секрет — URL, не пароль)
6. Пароль в `ONEC_PASSWORD` — через vault (не в `.env` и не в коде)
7. E2E smoke-тест: один запрос sync_contractors в dev → verify ответ реального 1С

## Что нужно для production-gate (enabled_live)

1. Прохождение production-gate ADR-0018
2. Юридическое согласование: данные о контрагентах / платежах — ПД?
3. Явное решение Владельца с записью в AuditLog
4. Vault-ref для ONEC_PASSWORD: `vault:secret/onec/api-password`
5. Egress-правило для IP-адреса 1С-сервера (infra-director)

---

## Открытые вопросы для Владельца (разрешить при старте M-OS-2)

1. **URL 1С-сервера**: какой адрес/порт HTTP-публикации 1С в dev-контуре?
2. **Аутентификация**: достаточно Basic Auth или нужен OAuth2 / клиентский сертификат?
3. **Конфигурационный объект 1С**: в какой информационной базе размещены контрагенты и платежи? (разные базы = разные `base_url`)
4. **Направление синхронизации**: M-OS читает из 1С (one-way) или двусторонняя запись?
5. **Частота синхронизации**: по расписанию (cron) или по событию (webhook из 1С)?

---

## DoD для ratification ADR-0025

- [ ] Владелец ответил на открытые вопросы 1–5 (перед M-OS-2)
- [ ] governance-director ratified ADR-0025
- [ ] Базовый класс `IntegrationAdapter` реализован (ADR-0014 DoD)
- [ ] OneCService подключён к `IntegrationRegistry`
- [ ] HTTP-публикация 1С настроена в dev (DevOps-задача)
- [ ] E2E smoke-тест в dev пройден
- [ ] `integration_catalog` запись `1c` переведена в `enabled_mock`

---

## Влияние на существующие ADR

**ADR-0014** — адаптер реализует паттерн из этого ADR. При реализации базового класса — подключиться к нему. Изменений в ADR-0014 не требуется.

**ADR-0015** — запись `1c` уже присутствует в seed-данных со статусом `written`. Изменений в ADR-0015 не требуется.

**ADR-0018** — перевод в `enabled_live` требует production-gate согласно ADR-0018. Изменений не требуется.

---

*Draft создан integrations-head (субагент L3) в рамках M-OS-1 «полка», 2026-04-19.*
*Ratification — перед стартом M-OS-2, governance-director.*
