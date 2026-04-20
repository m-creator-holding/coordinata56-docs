# Production Deployment Runbook — coordinata56

Версия: 1.0 | Дата: 2026-04-19 | Автор: DevOps (US-24-DEVOPS)

Полный пошаговый план для DevOps-инженера, выполняющего первое или повторное развёртывание
системы coordinata56 на продуктивном сервере.

---

## 1. Предварительные требования

### Сервер

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| ОС | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Диск (ОС + данные) | 40 GB SSD | 80 GB SSD |
| Диск (WAL-архив, если local) | 20 GB | не нужен при S3 |
| Сеть | 100 Мбит/с | 1 Гбит/с |

### Программное обеспечение

```bash
# Docker Engine 26+
curl -fsSL https://get.docker.com | sh

# Docker Compose Plugin (входит в Docker Engine 26+)
docker compose version

# Git
apt-get install -y git

# Certbot (Let's Encrypt — если HTTPS через certbot, не Traefik)
apt-get install -y certbot
```

### Сетевые порты (открыть в firewall)

| Порт | Протокол | Назначение |
|---|---|---|
| 80 | TCP | HTTP → редирект на HTTPS |
| 443 | TCP | HTTPS |
| 22 | TCP | SSH (только с IP DevOps) |

Все остальные порты (5432, 8000, 5173, 9187) — закрыты, только внутренняя Docker-сеть.

---

## 2. Подготовка секретов

### 2.1 JWT Secret Key

```bash
# Генерация 64-символьного hex-ключа
openssl rand -hex 32
# Пример вывода: a3f8c1d2e...  (скопировать в JWT_SECRET_KEY)
```

### 2.2 Пароль PostgreSQL

```bash
# Надёжный пароль без спецсимволов ($ и пробелы требуют экранирования в DSN)
openssl rand -base64 24 | tr -d '/+=' | head -c 32
```

### 2.3 Проверка .gitignore

Убедиться, что `.env.prod` присутствует в `.gitignore`:

```bash
grep ".env.prod" /root/coordinata56/.gitignore
# Должно найти строку: .env.prod
```

---

## 3. Yandex Cloud — настройка хранилища WAL

Выполнять в консоли Яндекс Cloud или через `yc` CLI.

### 3.1 Создание бакета

```bash
# Через yc CLI
yc storage bucket create --name coordinata56-wal

# Через консоль: Object Storage → Создать бакет
# Имя: coordinata56-wal
# Доступ: закрытый
# Хранилище: стандартное
```

### 3.2 Создание сервисного аккаунта

```bash
yc iam service-account create --name coordinata56-wal-sa

# Выдать роль загрузки объектов на бакет
yc resource-manager folder add-access-binding \
  --role storage.uploader \
  --subject serviceAccount:<SA_ID>
```

### 3.3 Создание ключа доступа (S3-совместимый)

```bash
yc iam access-key create --service-account-name coordinata56-wal-sa
# Сохранить: key_id → AWS_ACCESS_KEY_ID
#            secret   → AWS_SECRET_ACCESS_KEY
```

### 3.4 Создание JSON-ключа (для YC CLI в контейнере)

```bash
yc iam key create \
  --service-account-name coordinata56-wal-sa \
  --output /etc/coordinata56/yc-sa-key.json

# Создать директорию и ограничить права
mkdir -p /etc/coordinata56
chmod 700 /etc/coordinata56
chmod 600 /etc/coordinata56/yc-sa-key.json
```

---

## 4. Sentry — регистрация и получение DSN

1. Зарегистрироваться на [sentry.io](https://sentry.io) (или использовать существующую организацию).
2. Создать два проекта: **Python/FastAPI** (backend) и **JavaScript/React** (frontend).
3. Скопировать DSN каждого проекта:
   - Sentry → Project → Settings → Client Keys (DSN)
   - Формат: `https://<key>@o<org_id>.ingest.sentry.io/<project_id>`
4. Вставить DSN в `.env.prod`:
   - `SENTRY_DSN_BACKEND=https://...`
   - `SENTRY_DSN_FRONTEND=https://...`

При пустом DSN Sentry SDK работает в no-op режиме — приложение запускается нормально.

---

## 5. Заполнение .env.prod

```bash
# Клонировать репозиторий (если ещё не клонирован)
git clone https://github.com/<org>/coordinata56.git /opt/coordinata56
cd /opt/coordinata56

# Создать .env.prod из шаблона
cp infra/env.prod.template .env.prod

# Открыть редактор и заполнить ВСЕ переменные
nano .env.prod
```

Переменные, требующие обязательного заполнения перед первым запуском:

- `POSTGRES_PASSWORD` — сгенерированный пароль (шаг 2.2)
- `DATABASE_URL` — с реальным паролем вместо `${POSTGRES_PASSWORD}`
- `JWT_SECRET_KEY` — сгенерированный ключ (шаг 2.1)
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — из шага 3.3
- `GIT_COMMIT_SHA` — текущий коммит: `git rev-parse --short HEAD`

Переменные, которые можно оставить по умолчанию на старте:
- `SENTRY_DSN_BACKEND` / `SENTRY_DSN_FRONTEND` — пустые (no-op режим)
- `INTEGRATIONS_ONEC_STATE=enabled_mock` — mock до production-gate

---

## 6. Первый запуск

```bash
cd /opt/coordinata56

# Установить GIT_COMMIT_SHA в окружение
export GIT_COMMIT_SHA=$(git rev-parse --short HEAD)

# Сборка образов
docker compose -f docker-compose.yml -f docker-compose.prod.yml build

# Запуск всех сервисов в фоне
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Проверить статус запуска (все должны быть healthy или running)
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

Ожидаемый вывод через 60-90 секунд:

```
NAME                        STATUS          PORTS
coordinata56_postgres       healthy
coordinata56_backend        healthy
coordinata56_frontend       running
coordinata56_nginx          running         0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
coordinata56_postgres_exporter  running     127.0.0.1:9187->9187/tcp
```

---

## 7. Инициализация базы данных

```bash
# Применить все миграции Alembic (создать таблицы)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic upgrade head

# Проверить текущую версию миграции
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic current

# Создать первого администратора системы
# (заменить email и пароль на реальные)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend python -m app.scripts.seed_admin \
  --email admin@coordinata56.ru \
  --password "<strong password>"
```

---

## 8. Проверки после запуска

### 8.1 Health endpoints

```bash
# Liveness — приложение живо
curl -sf http://localhost/api/v1/health/live
# Ожидаемый ответ: {"status": "ok"}

# Readiness — готово принимать трафик (БД подключена)
curl -sf http://localhost/api/v1/health/ready
# Ожидаемый ответ: {"status": "ok", "db": "ok"}

# Startup — первичная инициализация завершена
curl -sf http://localhost/api/v1/health/startup
# Ожидаемый ответ: {"status": "ok"}
```

### 8.2 Проверка аутентификации

```bash
# Получить JWT-токен
curl -sf -X POST http://localhost/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@coordinata56.ru","password":"<password>"}' \
  | python3 -m json.tool
# Должен вернуть {"access_token": "...", "token_type": "bearer"}
```

### 8.3 Проверка WAL-архивации PostgreSQL

```bash
# Убедиться, что archive_mode активен в runtime
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec postgres psql -U coordinata -c "SHOW archive_mode;"
# Ожидаемый ответ: on

# Проверить статус архивации (archived_count должен расти)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec postgres psql -U coordinata -c \
  "SELECT archived_count, last_archived_wal, last_failed_wal FROM pg_stat_archiver;"
```

ВАЖНО: ручная загрузка файла в бакет НЕ является доказательством работы архивации.
Убедиться, что `archived_count` увеличивается автоматически через 1-2 минуты работы.

### 8.4 Проверка метрик

```bash
# Postgres-exporter отдаёт метрики (только с хоста сервера)
curl -sf http://127.0.0.1:9187/metrics | grep pg_up
# Ожидаемый ответ: pg_up 1
```

---

## 9. Процедура резервного копирования

### 9.1 WAL-архивация (непрерывная, автоматически)

WAL-сегменты архивируются в Яндекс Object Storage автоматически при `archive_mode=on`.
Интервал: каждые 60 секунд (`archive_timeout=60`).

Мониторинг: `pg_stat_archiver.last_failed_wal` должен быть пустым.

### 9.2 Еженедельный базовый бэкап (pg_basebackup)

```bash
# Запускать по cron каждое воскресенье в 02:00
# crontab -e → добавить строку:
# 0 2 * * 0 /opt/coordinata56/scripts/pg_basebackup_weekly.sh

# Ручной запуск:
/opt/coordinata56/scripts/pg_basebackup_weekly.sh

# Проверить результат:
ls -lh /var/backups/coordinata56/
# Ожидаемые файлы: base_YYYYMMDD_HHmm.tar.gz + state-файл
```

### 9.3 Проверка восстанавливаемости (раз в неделю)

```bash
# На тестовом сервере:
# 1. Скопировать base backup
# 2. Восстановить: tar xzf base_YYYYMMDD.tar.gz -C /tmp/pg_restore
# 3. Запустить postgres с этим data-dir
# 4. Убедиться, что данные читаются

# Цель: RTO ≤ 4 часа, RPO ≤ 24 часа
```

---

## 10. Процедура отката (при сломанной миграции)

### 10.1 Откат миграции Alembic

```bash
# Посмотреть историю миграций
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic history --verbose

# Откатиться на одну версию назад
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic downgrade -1

# Откатиться к конкретной версии (revision id из history)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic downgrade <revision_id>
```

### 10.2 Откат Docker-образа

```bash
# Остановить текущий backend
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  stop backend

# Запустить предыдущий образ (тег предыдущего коммита)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --no-deps backend

# Если образ не сохранён — восстановить из git:
git checkout <предыдущий коммит>
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  build backend
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --no-deps backend
```

### 10.3 Восстановление из pg_basebackup (крайний случай)

```bash
# Остановить все сервисы
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# Удалить текущий том данных
docker volume rm coordinata56_postgres_data

# Восстановить данные из бэкапа
docker run --rm \
  -v coordinata56_postgres_data:/var/lib/postgresql/data \
  -v /var/backups/coordinata56:/backup:ro \
  postgres:16-alpine \
  bash -c "tar xzf /backup/base_YYYYMMDD.tar.gz -C /var/lib/postgresql/data"

# Запустить сервисы заново
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## 11. Обновление (rolling deploy)

```bash
cd /opt/coordinata56

# 1. Получить последние изменения
git pull origin main

# 2. Установить SHA нового коммита
export GIT_COMMIT_SHA=$(git rev-parse --short HEAD)

# 3. Пересобрать образы
docker compose -f docker-compose.yml -f docker-compose.prod.yml build

# 4. Применить новые миграции БД (до перезапуска backend)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  exec backend alembic upgrade head

# 5. Перезапустить backend без простоя
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --no-deps backend

# 6. Перезапустить frontend (статика)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --no-deps frontend

# 7. Проверить health после деплоя
curl -sf http://localhost/api/v1/health/ready
```

### Если что-то пошло не так

```bash
# Проверить логи
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=50 backend

# Откатиться на предыдущую версию (см. раздел 10)
```
