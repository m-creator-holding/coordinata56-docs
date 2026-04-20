# onec-mock — stub-сервер 1С REST API

Stub-сервер симулирует подмножество 1С:Предприятие REST API для интеграционного тестирования. Работает локально внутри docker-сети; боевое подключение к 1С не требуется.

## Расположение файлов

```
infra/onec-mock/
├── Dockerfile          # Python 3.12-slim, uvicorn, порт 8080
├── requirements.txt    # fastapi + uvicorn (без dev-зависимостей)
├── app.py              # FastAPI-приложение, все эндпоинты
└── stubs/
    ├── contractors.json  # 5 фикстурных контрагентов
    └── payments.json     # 3 фикстурных платежа
```

## Запуск

```bash
# Запустить только onec-mock (из корня репозитория)
docker compose up -d onec-mock

# Проверить статус
docker compose ps onec-mock

# Посмотреть логи
docker compose logs -f onec-mock
```

## Проверка работоспособности

```bash
# Healthcheck
curl http://127.0.0.1:8081/health
# → {"status":"ok"}

# Список контрагентов (5 записей)
curl http://127.0.0.1:8081/api/contractors

# Список платежей (3 записи)
curl http://127.0.0.1:8081/api/payments

# Создать платёж (echo-back с generated id)
curl -X POST http://127.0.0.1:8081/api/payments \
  -H "Content-Type: application/json" \
  -d '{"contractor_id":"cnt-001","amount":50000,"purpose":"Тестовый платёж"}'
```

## Swagger UI (интерактивная документация)

После запуска доступна по адресу: http://127.0.0.1:8081/docs

## Эндпоинты

| Метод | Путь               | Описание                              |
|-------|--------------------|---------------------------------------|
| GET   | `/health`          | Healthcheck → `{status: "ok"}`        |
| GET   | `/api/contractors` | Список контрагентов из fixtures       |
| GET   | `/api/payments`    | Список платежей из fixtures           |
| POST  | `/api/payments`    | Создать платёж → echo-back с id       |

## Подмена fixtures для тестирования edge cases

Fixtures (`stubs/*.json`) монтируются из файловой системы хоста. Можно редактировать без пересборки образа.

**Шаг 1.** Отредактировать нужный файл:

```bash
# Добавить контрагента с невалидным ИНН (edge case)
vim infra/onec-mock/stubs/contractors.json
```

**Шаг 2.** Перезапустить контейнер, чтобы изменения подхватились:

```bash
docker compose restart onec-mock
```

> Примечание: файлы `stubs/` скопированы в образ через `COPY` в Dockerfile.
> При правке fixtures — нужна пересборка: `docker compose build onec-mock && docker compose up -d onec-mock`.
> Если нужна горячая подмена (без пересборки) — добавьте volume-mount в `docker-compose.yml`:
> ```yaml
> volumes:
>   - ./infra/onec-mock/stubs:/app/stubs:ro
> ```

## Hostname для backend-сервиса

Внутри docker-сети `coordinata56_internal` сервис доступен по адресу:

```
http://onec-mock:8080
```

Пример переменной окружения в `backend`:

```env
ONEC_BASE_URL=http://onec-mock:8080
```

## Остановка

```bash
docker compose stop onec-mock
# или полностью удалить контейнер
docker compose rm -f onec-mock
```
