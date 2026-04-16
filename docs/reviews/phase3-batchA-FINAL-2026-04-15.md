# Финальное ревью — Phase 3, Batch A
**Дата**: 2026-04-15  
**Ревьюер**: reviewer (субагент)  
**Скоуп**: 8 сущностей Батча A (Project, Stage, HouseType, OptionCatalog, HouseTypeOptionCompat, House, HouseConfiguration, HouseStageHistory)  
**Вердикт**: **READY-TO-CLOSE** (с одним обязательным условием — см. §3)

---

## 1. Единообразие паттерна между 8 сущностями

### 1.1 Структура файлов

| Слой | Project | Stage | HouseType | OptionCatalog | House / HouseConf / HouseStageHistory |
|---|---|---|---|---|---|
| `schemas/` | `schemas/project.py` | `schemas/stage.py` | `schemas/house_type.py` | `schemas/option_catalog.py` | `schemas/house.py` (все три) |
| `repositories/` | `repositories/project.py` | `repositories/stage.py` | `repositories/house_type.py` | `repositories/option_catalog.py` | `repositories/house.py` (все три) |
| `services/` | `services/project.py` | `services/stage.py` | `services/house_type.py` | `services/option_catalog.py` | `services/house.py` (три класса) |
| `api/` | `api/projects.py` | `api/stages.py` | `api/house_types.py` | `api/option_catalog.py` | `api/houses.py` (всё вложенное) |

Структура единая. House, HouseConfiguration и HouseStageHistory объединены в один тройной файл на каждом слое — архитектурно оправдано (тесная связь, единый ресурс `/houses`).

**Отклонение от ADR 0004 (заявленное, приемлемое):** 5 файлов роутеров вместо 8. HouseConfiguration и HouseStageHistory реализованы как вложенные ресурсы `/houses/{id}/configurations` и `/houses/{id}/stage-history` в `api/houses.py`. HouseTypeOptionCompat — в `api/house_types.py` как `GET/PUT /house-types/{id}/options`. Отклонение от «3 файла на сущность» обоснованно (REST-семантика вложенности), не нарушает безопасность и совместимость.

### 1.2 Имена методов в сервисах

| Метод | Project | Stage | HouseType | OptionCatalog | HouseService | HouseConfigService |
|---|---|---|---|---|---|---|
| `list` | ✓ | ✓ | ✓ | ✓ | ✓ | — (list_for_house) |
| `get` / `get_or_404` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `create` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `update` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `delete` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Имена единые. `list_for_house` в `HouseConfigurationService` — приемлемое отклонение: конфигурации не имеют независимого list без родительского `house_id`.

### 1.3 Подключение в main.py — 5 роутеров

```
projects_router    /api/v1/projects      tags=["projects"]
stages_router      /api/v1/stages        tags=["stages"]
house_types_router /api/v1/house-types   tags=["house-types"]
option_catalog_r   /api/v1/option-catalog tags=["option-catalog"]
houses_router      /api/v1/houses        tags=["houses"]
```

Все 5 роутеров зарегистрированы с тегами. 8 сущностей Батча A покрыты через 5 префиксов.

### 1.4 Pydantic-схемы

Паттерн `*Create / *Update / *Read` соблюдён для каждой сущности. Для House добавлены специфичные схемы `HouseBulkCreate`, `HouseBulkResult`, `HouseStageChange` — необходимы для action-эндпоинтов. `HouseStageHistoryRead` — только Read (append-only). Всё логично и однородно.

---

## 2. Дрейф паттерна от эталона Project

| Аспект | Эталон (Project) | Отличие | Оправдано? |
|---|---|---|---|
| Soft-delete | `soft_delete` | Stage и HouseType — физическое удаление | Да: нет `SoftDeleteMixin` в модели, поведение задокументировано в сервисах |
| `list` фильтрация | `extra_conditions` в `list_paginated` | HouseService использует `list_paginated_filtered` с отдельными аргументами | Да: House имеет 4 специфичных фильтра; переиспользуемый механизм `extra_conditions` сохранён в BaseRepository для Батча B |
| Action-endpoint | Отсутствует | `PATCH /houses/{id}/stage`, `PUT /house-types/{id}/options`, `POST /houses/bulk` | Да: предусмотрено scope, ADR 0004 Amendment |
| Помощник `_make_service` | ✓ | ✓ во всех роутерах | Паттерн единый |

Незаявленных отклонений, нарушающих безопасность или контракт API, не обнаружено.

---

## 3. Покрытие мини-DoD Батча A

| Пункт | Статус | Примечание |
|---|---|---|
| 8 роутеров реализованы | ✓ | 5 файлов покрывают 8 сущностей |
| Swagger: summary/description/response_model | ✓ | Все эндпоинты проверены |
| RBAC × 4 роли | ✓ | Матрица полная после step 5 |
| Аудит на всех write | ✓ | Проверено в step 4 и step 5 |
| Soft-delete семантика | ✓ | House: soft-delete; Stage/HouseType/OptionCatalog: физическое с защитой ссылок |
| Action-endpoints | ✓ | /bulk, /stage, PUT /options, /configurations реализованы |
| Формат ошибок ADR 0005 | ✓ | Три exception_handler в main.py |
| Пагинация ADR 0006 | ✓ | ListEnvelope + limit 200 |
| ≥1 happy + ≥1 403 + ≥1 422 на эндпоинт | ✓ | 211 тестов, все зелёные |
| **Ретро-заметка `phase_3_batch_a_notes.md`** | **ОТСУТСТВУЕТ** | **Нарушение мини-DoD** |

**Условие закрытия Батча A: создать `docs/knowledge/retros/phase_3_batch_a_notes.md`.**  
Без этого файла мини-DoD формально не выполнен (см. чек-лист: «Ретро-заметка по батчу в `docs/knowledge/retros/phase_3_batch_X_notes.md`»).  
Допустимо создать файл в этом же коммите или отдельным коммитом — не требует повторного ревью.

---

## 4. Готовность к Батчу B

| Компонент | Статус | Применимость в Батче B |
|---|---|---|
| `BaseRepository` с `extra_conditions` | Стабильный | Переиспользуем для фильтров BudgetPlan по (project_id × category_id × stage_id) |
| `BaseService.get_or_404` | Стабильный | Переиспользуем для BudgetCategory, BudgetPlan |
| `AuditService` | Стабильный | Переиспользуем без изменений |
| `ListEnvelope` + `PaginationParams` | Стабильный | Переиспользуем без изменений |
| Error handlers в `main.py` | Стабильный | Без изменений |
| `extra_conditions` механизм | Стабильный | Основа для фильтрации финансов |
| Action-endpoint паттерн (`POST /resource/action`) | Отработан на `/houses/{id}/stage` | Применяем для `/payments/{id}/approve` в Батче C |

**Кросс-срезовые компоненты заморожены** согласно правилу перехода между батчами. Изменения в BaseRepository/BaseService/AuditService/ListEnvelope в Батчах B/C — только через отдельный ADR amendment.

---

## 5. Регрессии Фазы 2 (auth)

### 5.1 Литеральные пароли в test_auth.py

Устранены в step 4 Round 2 (подтверждено ревьюером). Текущее состояние `test_auth.py`:
- Фикстуры `owner_user`, `accountant_user` — пароли через `secrets.token_urlsafe(16)` ✓
- Неправильные пароли в тестах 401 (`"wrong_password"`, `"any_password"`) — допустимо (не реальные credentials) ✓
- Строка подключения к тест-БД с `change_me_please_to_strong_password` — конфигурация dev-окружения, не production-секрет ✓

### 5.2 Auth-тесты (19 штук)

Не затронуты изменениями Батча A. Все 19 тестов входят в 211 зелёных. Регрессий нет.

---

## 6. Открытые tech-debt позиции (не блокируют закрытие)

| # | Позиция | Приоритет | Срок |
|---|---|---|---|
| P3-1 | `# type: ignore[attr-defined]` в `base.py` для `self.model.id` | minor | До деплоя в production |
| P3-2 | Python 3.12+ не зафиксировано в ADR 0002 | minor | До CI-настройки (Фаза 9) |
| P3-3 | `print()` в `seeds.py` | nit | При следующем касании файла |
| P3-4 | Тест на soft-delete + повторное создание с тем же code | minor | До Фазы 5 |
| P3-5 | Silent `except` в `StageRepository.has_references` без логирования | minor | До production (Фаза 9) |
| P3-6 | `TEST_DATABASE_URL` не загружается автоматически | minor | До CI (Фаза 9) |
| step5-nit | `from app.models.house import HouseStageHistory` внутри метода (строка 1235) | nit | В следующем коммите |

---

## 7. Замечания финального ревью (новые)

### 7.1 — nit

**Файл**: `backend/tests/test_batch_a_coverage.py`, строка 1235  
`from app.models.house import HouseStageHistory` — импорт внутри тела метода. Модель не импортирована в заголовке (строки 24–29). Исправляется переносом одной строки. Не блокирует закрытие.

### 7.2 — minor (уже зафиксировано в tech-debt P3-5, не новое)

**Файл**: `backend/app/repositories/stage.py`, строки 65–67  
`except Exception: pass` без логирования. Корректно для dev (Батч B ещё не реализован), опасно в production. Зафиксировано в tech-debt. Не блокирует закрытие.

### 7.3 — blocker-условие (не код, а процесс)

**Файл**: отсутствует  
`docs/knowledge/retros/phase_3_batch_a_notes.md` — не создан. Мини-DoD явно требует ретро-заметку для каждого батча. Создание не требует ревью, но обязательно до объявления Батча A закрытым.

---

## Резюме (≤200 слов)

**Что хорошо.** Трёхслойная архитектура ADR 0004 выдержана строго: SQL только в repositories, бизнес-логика только в services, аудит — в той же транзакции. Базовые компоненты (BaseRepository, BaseService, AuditService, ListEnvelope) стабильны и готовы к Батчу B. IDOR-защита для HouseConfiguration закрыта с правильной 404-семантикой. Матрица RBAC × 4 роли полная. Паттерн между 8 сущностями единообразен. 211 тестов зелёные, литеральных паролей нет, password_hash в схемы не утекает.

**Что просто хорошо.** Swagger-документация полная (summary/description/response_model/responses везде). Формат ошибок ADR 0005 унифицирован. Отклонения от ADR 0004 (физическое удаление Stage/HouseType, объединение 3 сущностей в один файл) — заявленные и оправданные.

**Что плохо.** Отсутствует `docs/knowledge/retros/phase_3_batch_a_notes.md` — прямое нарушение мини-DoD. Один nit-импорт не перенесён из метода в заголовок (строка 1235).

**Итоговый вердикт: READY-TO-CLOSE** при условии создания ретро-заметки. Технических блокеров нет.

---

*Ревьюер: reviewer | coordinata56 | Phase 3 Batch A FINAL | 2026-04-15*
