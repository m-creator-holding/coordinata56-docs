# Фаза 3 — Статус

**Последнее обновление:** 2026-04-16 (после закрытия Фазы 3 как инженерной вехи)
**Статус фазы:** ✅ **CLOSED (инженерная веха)** — согласовано Владельцем 2026-04-16 msg 861.
**Production gate:** ⚠️ **НЕ ПРОЙДЕНО** — требуются организационные действия с живым юристом до включения реальных данных (см. ниже).
**Автор текущей версии:** Координатор + backend-director

---

## Обзор батчей

| Батч | Скоуп | Статус | Коммиты | Тесты | Ретро |
|---|---|---|---|---|---|
| A — Каталог и справочники | Project, Stage, HouseType, OptionCatalog, HouseTypeOptionCompat, House, HouseConfiguration, HouseStageHistory | ✅ closed | 12 | 211 | `docs/knowledge/retros/phase_3_batch_a_notes.md` |
| B — Финансы-план | BudgetCategory, BudgetPlan (+ bulk upsert) | ✅ closed | ~5 | 52 (итого 263) | `docs/knowledge/retros/phase_3_batch_b_notes.md` |
| C — Финансы-факт | Contractor, Contract, Payment, MaterialPurchase | ✅ ready-to-close | 4 (e08b9b8, 3e279ea, bb1310f, 6cd337e) | 88 (итого 351) | `docs/knowledge/retros/phase_3_batch_c_retro.md` |

**Итого по Фазе 3:** 14 сущностей, ~57 эндпоинтов, 351 тест passed, 0 failed.

---

## Батч C — детальный статус (Шаг C.5 замыкание)

### Финальные прогоны

**pytest:**

```
351 passed, 34 warnings in 215.85s (0:03:35)
```

Все 34 warnings — `DeprecationWarning` от внешних библиотек (passlib использует `crypt`, starlette использует `HTTP_422_UNPROCESSABLE_ENTITY`). Не блокируют.

**ruff check backend/app backend/tests:**

- Код Батча C (`api/`, `services/`, `repositories/`, `schemas/`, `tests/`): чисто.
- 3 pre-existing ошибки в `app/db/seeds.py` (I001, B007, UP017) — Фаза 1, `seeds.py` не трогался в Батче C. Зафиксировано в tech-debt как `P3-NEW-1`.

**Swagger (`GET /openapi.json`):**

22 эндпоинта Батча C, 4 тэга:

| Тэг | Количество | Эндпоинты |
|---|---|---|
| `contractors` | 5 | POST, GET list, GET id, PATCH, DELETE |
| `contracts` | 5 | POST, GET list, GET id, PATCH, DELETE |
| `payments` | 7 | POST, GET list, GET id, PATCH, DELETE, POST /approve, POST /reject |
| `material-purchases` | 5 | POST, GET list, GET id, PATCH, DELETE |

- У всех 22 — `summary` (русский) и `description`.
- У 18/22 есть JSON-schema response_model. У 4 DELETE — 204 No Content (response_model не применим, это корректно).
- У всех задокументированы `responses`: 204/201/200, 403, 404, 409 (где применимо), 422.

### Миграции Батча C

- `e1f2a3b4c5d6_contractor_inn_partial_unique` (Шаг C.1) — partial UNIQUE `contractors.inn WHERE deleted_at IS NULL`.
- `d1e2f3a4b5c6_payment_approve_reject_audit` (предшествовала Шагу C.3) — 5 полей approval/rejection в `payments`.
- `2026_04_16_1450_contract_contractor_number_unique_partial` (коммит `bb1310f`) — partial UNIQUE `contracts (contractor_id, number) WHERE deleted_at IS NULL`.

Alembic round-trip проверен.

### Ревью-история Батча C

| Шаг | Файл ревью | Round 1 | Round 2 | Round 3 |
|---|---|---|---|---|
| C.1 + C.4 | `docs/reviews/phase3-batchC-steps1-4-2026-04-15.md` | request-changes (3 P1, 2 P2, 2 P3) | approve | — |
| C.2 | `docs/reviews/phase3-batchC-step2-2026-04-16.md` + `...-round2-...` | request-changes (1 P1 ADR 0004 + 1 P1 RBAC + 2 P2 + 1 P3) | approve | — |
| bb1310f (docstring-долг) | `docs/reviews/phase-3-batch-c-contract-unique-index.md` | approve | — | — |
| C.3 | `docs/reviews/phase-3-batch-c-step-c3-payment.md` | request-changes (2 P2, 2 minor) | approve | (после ручных правок Round 3) |

### Reviewer-pass Батча C как целого

**Статус:** ✅ approved — `docs/reviews/phase-3-batch-c-consolidated.md`, коммит `15e89e4`.

---

## Закрытие Фазы 3 — итоги 2026-04-16

### Финальные 3 трека (прошли после consolidated review)

| Трек | Исполнитель | Вердикт | Отчёт |
|---|---|---|---|
| OWASP-прогон | `security` | ✅ approve-to-close (4 P2/P3 без блокеров) | `docs/security/phase-3-owasp-sweep.md` |
| Legal проверка | `legal` | ✅ approve инженерию; ⚠️ 1 P0 + 4 P1 на production gate | `docs/legal/phase-3-legal-check.md` |
| Tech-writer | `tech-writer` | ✅ README + ONBOARDING + glossary обновлены | (в этом же коммите) |

### Production gate — не пройден (для боевых данных)

Список организационных/юр-действий и доработок модели, которые ДОЛЖНЫ быть выполнены до включения реальных ПД и денег (блокеры M-OS-2 «боевые интеграции»):

**Требуют живого юриста (лицензированного):**
- F-02 (P1) Подача уведомления в реестр операторов ПДн (Роскомнадзор). Обязательно с 30.05.2025 для всех операторов. Штраф за неподачу: 100-300k ₽.
- F-03 (P1) Разработка политики обработки ПДн для M-OS (шаблон адаптировать под профиль холдинга).
- F-05 (P1) Допсоглашение в трудовых договорах о мониторинге действий сотрудников в M-OS (ТК ст.86.3).
- F-07 (P2) Приказ руководителя о простой электронной подписи для согласования Payment (63-ФЗ ст.9).

**Доработки модели данных (M-OS-1 Foundation, делаем сами):**
- F-01 (P0) Добавить `file_id` в Contract — хранение скана/электронного экземпляра договора. Без этого нет доказательной базы (ГК ст.434, 702).
- F-04 (P1) Добавить `start_date` / `end_date` в Contract — сроки работ как существенное условие (ГК ст.708).

**Бизнес-решение Владельца (зафиксировано 2026-04-16 msg 861):**
- F-06: коттеджи в «Координата 56» продаются **по двум моделям** параллельно: через ДДУ (214-ФЗ) + как готовые дома (ГК ст.549). CRM-блок в M-OS должен поддерживать обе модели.

**Доработка M-OS-2:**
- F-08 (P2) Информационный флаг при Payment ≥ 600 000 ₽ (115-ФЗ ст.6 — порог обязательного контроля). Флаг = предупреждение бухгалтеру, не блокировка.

### Production gate — чек-лист перед включением реальных данных

Все 7 позиций выше должны быть зелёными.

### Согласование Владельца

✅ 2026-04-16 msg 861 — Владелец согласовал закрытие Фазы 3 как инженерной вехи, с явным условием что organizational P0/P1 закрываются через живого юриста до production.

---

## DoD Фазы 3 — проверка 10 пунктов (`docs/agents/phase-checklist.md`)

| # | Пункт | Статус | Примечание |
|---|---|---|---|
| 1 | Код и реализация | ⏳ частично | 351 test passed; ruff чист на Батче C; coverage-branch замер не производился явно для Фазы 3 (замер есть у Батчей A/B) — рекомендую зафиксировать на C.5 +1. |
| 2 | Архитектура и ADR | ✅ | ADR 0004–0007 соблюдены. Amendment к ADR 0004 (action-endpoints) применён на `/approve`, `/reject`, `/bulk`, `/stage`. |
| 3 | Безопасность | ⏳ pending | OWASP-чек-лист Батча C: A01 (IDOR) — тест добавлен Round 2 C.1+C.4, A03 — `assert` в валидаторе заменён в Round 2 C.1. Полный OWASP-прогон от `security` — задача Координатора после reviewer-approve. |
| 4 | Ревью | ⏳ pending | Per-step approve есть на всех 4 шагах. Consolidated review Батча C — задача Координатора, бриф ниже. |
| 5 | Тесты (классы эквивалентности, границы) | ✅ | 351 test, +88 в Батче C. Action-endpoints покрыты матрицей статусов (approve/reject × draft/pending/approved/rejected). |
| 6 | Документация | ⏳ частично | Swagger актуален (проверено). `docs/knowledge/glossary.md` — backend-director рекомендует добавить термины Contractor/Contract/Payment/MaterialPurchase после consolidated approve (tech-writer). `docs/ONBOARDING.md` не менялся — бэкенд-процесс запуска не изменён. |
| 7 | Юридика | ⏳ для `legal` | 152-ФЗ: Contractor содержит `inn`, `kpp`, `short_name` — это не PII физлица, но требует подтверждения `legal`. 214-ФЗ: Payment — на этапе MVP не интегрирован с ДДУ, но в Фазе 5+ станет критичным. Рекомендую эскалировать `legal` после reviewer-approve. |
| 8 | Память Координатора | ⏳ | Обновление `project_cottage_mvp_status.md` — задача Координатора после согласования Владельца. |
| 9 | Git | ✅ | Коммиты Батча C атомарны, сообщения осмысленные (why, not what). Нет битых коммитов. |
| 10 | Согласование с Владельцем | ⏳ | Отчёт через Telegram — задача Координатора. |

**Вердикт backend-director:** Фаза 3 по техническому скоупу готова к закрытию. Блокеров в коде и тестах нет. Осталось: (1) consolidated reviewer-approve Батча C, (2) OWASP-прогон от `security`, (3) `legal` проверка Contractor/Payment, (4) отчёт и согласование Владельца.

---

## Бриф для consolidated review Батча C (передать reviewer-у)

**Скоуп ревью:** `git diff 9bf2d95..HEAD` — 4 коммита Батча C (`e08b9b8`, `3e279ea`, `bb1310f`, `6cd337e`). Per-step ревью уже проведены и approved; consolidated review — **проверка консистентности Батча как целого**, не повторение per-step.

**Что проверить:**

1. **Единообразие паттерна между 4 сущностями.** Структура файлов (`schemas/`, `repositories/`, `services/`, `api/`, `tests/`), имена методов сервиса (`list`, `get`, `create`, `update`, `delete` + action-методы), `_make_service` helper — все 4 сущности следуют одному шаблону. Отклонения должны быть заявленными (MaterialPurchase — hard-delete, Payment — action-endpoints).

2. **Drift паттерна от эталонов Батча A и B.** `BaseRepository.extra_conditions`, `BaseService.get_or_404`, `AuditService.log()`, `ListEnvelope`, error handlers — не модифицировались в Батче C (ожидается). Кросс-срезовые компоненты заморожены.

3. **Partial UNIQUE constraint-ы.** `contractors.inn` и `contracts.(contractor_id, number)` — оба с `WHERE deleted_at IS NULL`. Проверить: (a) `unique=True` в модели убран (чтобы не было расхождения), (b) миграции round-trip чистые, (c) сервис перед insert делает свою проверку (soft UX, до IntegrityError).

4. **Action-endpoints (`/payments/{id}/approve`, `/reject`).** Соответствие ADR 0004 Amendment. `PaymentUpdate` не содержит `status` в writeable-виде (через `Literal["draft","pending"]`). Переход статуса возможен ТОЛЬКО через `/approve` или `/reject`, не через generic PATCH. Тест на попытку PATCH status через Update — желательно чтобы был и assertion что 422.

5. **Audit meta — каноническая структура.** Для approve/reject: `{"transition": "<new>", "from_status": "<old>"[, "reason": "..."]}`. Для create/update/delete — diff before/after через Read-схему (без секретных полей — у Payment их нет, у Contractor нет). Проверить: нет `old_status`/`new_status` в meta (был P2-2 в C.3 Round 1, исправлен в Round 2 — проверить, что регрессия не вернулась).

6. **RBAC-матрица.** Полная по всем 4 сущностям × 4 роли × 5 операций:
   - Contractor: write (create/update/delete) — `owner`, `accountant`; read — все 4 роли.
   - Contract: write — `owner`, `accountant`; read — `owner`, `accountant`, `construction_manager` (read_only ЗАБЛОКИРОВАН — тест).
   - Payment: write — `owner`, `accountant`; read — все 4 роли; `/approve` и `/reject` — ТОЛЬКО `owner`.
   - MaterialPurchase: write — `construction_manager`, `accountant`, `owner`; read — все 4 роли.

7. **IDOR-защита.** Везде где есть FK с cross-check:
   - Contract: `house.project_id == project_id`, `stage` существует → тесты.
   - MaterialPurchase: `house.project_id == project_id` → тест `test_create_mp_house_project_mismatch_409` добавлен Round 2 C.1+C.4.
   - Payment: `contract.status in (active, completed)` — это бизнес-правило, не IDOR, но также требует теста.

8. **Бизнес-правила жёсткие:**
   - Contract status transitions: `draft→active→completed` | `draft→cancelled` | `active→cancelled`. Обратные → 409. Тест.
   - Payment immutability: `approved` / `rejected` — PATCH ЛЮБОГО поля → 409. DELETE → 409. Параметризованный тест.
   - Payment overrun limit: `PAYMENT_OVERRUN_LIMIT_PCT=20` — лимит 120% суммы договора на approve. Граничный тест.
   - MaterialPurchase: `total_price_cents = round(quantity * unit_price_cents)` — auto-compute или validate. Тест на mismatch 422.

9. **Pre-existing tech-debt после Батча C:**
   - `seeds.py` — 3 ruff ошибки (pre-existing Фаза 1). Не блокер, но зафиксировать в retro как `P3-NEW-1`.
   - `amount_cents` Payment без upper limit (`P3-NEW-3`).
   - `conftest.py` без автоматического `alembic upgrade head` (усиление `P3-6` в `P3-NEW-2`).

10. **Регрессии Батчей A и B:**
    - Все 263 теста A+B всё ещё зелёные (входят в 351 total).
    - Никаких изменений в `backend/app/models/` кроме правок от db-engineer (`payments` — 5 approval полей).
    - Никаких изменений в `BaseRepository` / `BaseService` / `AuditService` / `ListEnvelope`.

**Ожидаемый вердикт:** `approve` с возможным minor-замечанием по pre-existing tech-debt. Если reviewer найдёт P0/P1 на consolidated — backend-director разберёт и эскалирует.

**Not-goals consolidated review:**
- Не повторять per-step проверку линий кода (это уже сделано).
- Не проверять performance / load (это tech-debt, не MVP).
- Не проверять i18n Swagger summaries (русский — сознательное решение для MVP).

---

## Переход к Фазе 4

**Зелёный билет для перехода:**
- [ ] Consolidated reviewer approve на Батч C
- [ ] OWASP-прогон от `security` без P0/P1
- [ ] `legal` подтверждение Contractor/Payment
- [ ] Tech-writer обновление glossary/ONBOARDING/README
- [ ] Отчёт Владельцу через Telegram
- [ ] Владелец: явное «согласовано, переходим к Фазе 4»

**Ожидаемая Фаза 4:** фронтенд MVP (Vite+React+Mantine), маршруты для 14 сущностей Фазы 3 + auth. Либо M-OS-0 Reframing — решение Координатора + Владельца по результатам текущих обсуждений.

---

*Автор статуса: backend-director. Обновляется Директорами соответствующих направлений и Координатором при смене статуса.*
