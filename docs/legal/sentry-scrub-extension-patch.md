# Sentry Scrub Extension — Patch Description

**Дата:** 2026-04-19  
**Статус:** Patch description — НЕ применён. Передать backend-dev в отдельной волне  
**Автор:** Legal adviser (субагент)  
**Файл для правки:** `backend/app/core/sentry_scrub.py`

---

## Контекст

GAP G-3 из предыдущего audit (2026-04-19): текущий `make_sentry_before_send()` очищает:
- `event["request"]["data"]` — тело запроса
- `event["extra"]` — debug-дампы
- `event["contexts"]` — user, runtime

Не покрыто:
- `event["exception"]["values"][*]["stacktrace"]["frames"][*]["vars"]` — локальные переменные в стектрейсе
- `event["exception"]["values"][*]["stacktrace"]["frames"][*]["pre_context"]` / `["context_line"]` / `["post_context"]` — строки кода с переменными
- `event["breadcrumbs"]["values"][*]["data"]` — данные хлебных крошек (HTTP-запросы, SQL-запросы)

**Риск по 152-ФЗ:** при исключении (Exception) в обработчике ПДн стектрейс может зафиксировать значения переменных с ФИО, телефонами, email — и отправить в Sentry Cloud. Это передача ПДн третьему лицу без основания (ст. 6 152-ФЗ).

---

## Описание patch

### Что добавить в `before_send()`

```python
def before_send(event: dict[str, Any], hint: dict[str, Any]) -> dict[str, Any]:
    # === СУЩЕСТВУЮЩИЕ блоки (не трогать) ===
    if "request" in event and "data" in event.get("request", {}):
        event["request"]["data"] = _scrub_dict(event["request"]["data"])
    if "extra" in event:
        event["extra"] = _scrub_dict(event["extra"])
    if "contexts" in event:
        event["contexts"] = _scrub_dict(event["contexts"])

    # === НОВЫЙ блок 1: stacktrace local vars ===
    # Локальные переменные в каждом фрейме стектрейса могут содержать
    # объекты моделей с ПДн (User, Contractor, ContactPerson).
    # Очищаем vars в каждом фрейме каждого исключения.
    for exception in event.get("exception", {}).get("values", []):
        stacktrace = exception.get("stacktrace", {})
        for frame in stacktrace.get("frames", []):
            if "vars" in frame:
                frame["vars"] = _scrub_dict(frame["vars"])
            # Строки кода (pre_context, context_line, post_context) —
            # содержат исходный код, не данные; не очищаем, оставляем для отладки.

    # === НОВЫЙ блок 2: breadcrumbs ===
    # Хлебные крошки фиксируют HTTP-запросы и SQL.
    # В data может быть тело запроса или параметры SQL с ПДн.
    for breadcrumb in event.get("breadcrumbs", {}).get("values", []):
        if "data" in breadcrumb:
            breadcrumb["data"] = _scrub_dict(breadcrumb["data"])

    return event
```

### Дополнить `_SENSITIVE_KEYS_RE`

Добавить ключи для полей Notification и Contractor-схемы:

```python
_SENSITIVE_KEYS_RE = re.compile(
    r"passport|snils|inn|phone|birth.?date|address|secret|password|token"
    r"|email|name|contact|title|body|payload|contacts_json",  # НОВЫЕ КЛЮЧИ
    re.IGNORECASE,
)
```

**Внимание:** добавление `payload` в scrub сделает все payload-поля слепыми в Sentry. Альтернатива — не добавлять `payload` в regex, но реализовать отдельный `_scrub_payload()` с белым списком безопасных ключей (bpm_step, action_url, amount). Решение — на backend-dev.

---

## Тест-кейсы для QA

```python
def test_sentry_scrub_stacktrace_vars():
    """Проверяет, что ФИО в vars стектрейса scrub'ится."""
    scrubber = make_sentry_before_send()
    event = {
        "exception": {
            "values": [{
                "stacktrace": {
                    "frames": [{
                        "vars": {
                            "user": {"name": "Иванов Иван", "email": "i@i.ru"},
                            "amount": 50000,
                        }
                    }]
                }
            }]
        }
    }
    result = scrubber(event, {})
    frame_vars = result["exception"]["values"][0]["stacktrace"]["frames"][0]["vars"]
    assert frame_vars["user"]["name"] == "[SCRUBBED]"
    assert frame_vars["user"]["email"] == "[SCRUBBED]"
    assert frame_vars["amount"] == 50000  # не ПДн — не трогаем


def test_sentry_scrub_breadcrumbs():
    """Проверяет очистку ПДн в breadcrumbs."""
    scrubber = make_sentry_before_send()
    event = {
        "breadcrumbs": {
            "values": [{
                "type": "http",
                "data": {
                    "url": "/api/contractors/1",
                    "body": {"contacts_json": {"name": "Петров П.П."}},
                }
            }]
        }
    }
    result = scrubber(event, {})
    breadcrumb_data = result["breadcrumbs"]["values"][0]["data"]
    assert breadcrumb_data["body"]["contacts_json"]["name"] == "[SCRUBBED]"
```

---

## Приоритет внедрения

**Severity GAP G-3 после расширения:** Medium → High.

Причина переоценки: Sprint 3 добавил Notification с ФИО в body и Contractor с contacts_json. Вероятность попадания ПДн в стектрейс при ошибке обработки возросла. При наличии Sentry Cloud (решение одобрено Владельцем) — это реальный канал утечки ПДн за границу РФ (Sentry = США).

**Рекомендация:** включить в ближайшую security-волну вместе с hardening от backend-director.

---

## Применимые нормы

| Норма | Применение |
|---|---|
| 152-ФЗ ст. 6 ч. 1 | Передача ПДн Sentry (иностранная организация) требует основания |
| 152-ФЗ ст. 12 | Трансграничная передача ПДн — Sentry USA = нарушение без должной защиты |
| ПП РФ 1119 п. 15 | Технические меры защиты при обработке ПДн |
| 152-ФЗ ст. 19 | Обеспечение безопасности ПДн при обработке |
