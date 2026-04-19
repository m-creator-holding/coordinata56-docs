# PITR Runbook — восстановление PostgreSQL на точку во времени

**Версия:** 1.0  
**Дата:** 2026-04-19  
**Автор:** devops-head  
**Применимость:** coordinata56, PostgreSQL 16, Яндекс Object Storage (wal-g или awscli)

---

## Обзор

Point-in-Time Recovery (PITR) позволяет восстановить базу данных на произвольный момент T,
который находится между последним базовым бэкапом (pg_basebackup) и любым более поздним
моментом, за который есть непрерывный WAL-архив.

**Когда применять:** потеря данных (ошибочный DELETE/DROP), повреждение файлов данных,
необходимость «откатиться» на час-два назад.

**Когда применять pg_dump restore вместо PITR:** базовый бэкап отсутствует или WAL-цепочка
прервана. В этом случае — обратиться к `docs/pods/cottage-platform/infrastructure/backup-policy.md`
раздел «Процедура восстановления».

---

## Предусловия

Перед началом убедитесь в следующем:

```bash
# Экспортируем рабочие переменные — вставить реальные значения
export S3_BUCKET="coordinata56-wal"
export S3_ENDPOINT="https://storage.yandexcloud.net"
export AWS_ACCESS_KEY_ID="<из .env.dev>"
export AWS_SECRET_ACCESS_KEY="<из .env.dev>"
export RECOVERY_TARGET_TIME="2026-04-19 11:30:00+00"  # момент T, до которого восстанавливаем
export RESTORE_PGDATA="/var/lib/postgresql/restore_pgdata"
export RESTORE_PORT="5435"  # порт для restore-контейнера, не занятый основным (5433)
export PGPASSWORD="<POSTGRES_PASSWORD из .env.dev>"
export POSTGRES_USER="coordinata"
export POSTGRES_DB="coordinata56"
```

**Проверка доступности S3:**

```bash
aws s3 ls "s3://${S3_BUCKET}/wal/" --endpoint-url="${S3_ENDPOINT}" | tail -5
# Ожидаемый вывод: список WAL-файлов с датами
```

**Проверка наличия базового бэкапа:**

```bash
aws s3 ls "s3://${S3_BUCKET}/basebackup/" --endpoint-url="${S3_ENDPOINT}"
# Ожидаемый вывод: директории вида YYYY-WW/
```

**Проверка свободного места (нужно >= 2× размер БД):**

```bash
df -h /var/lib/postgresql/
# Размер restore_pgdata будет примерно равен размеру основной БД
```

**Наличие wal-g или awscli:**

```bash
command -v wal-g && echo "wal-g найден" || echo "wal-g отсутствует — используем awscli"
command -v aws && echo "awscli найден"
```

---

## Шаг 1 — Остановить backend

```bash
# Останавливаем backend, чтобы он не писал в БД во время восстановления
docker compose -f /root/coordinata56/docker-compose.yml stop backend

# Убедиться что остановился
docker compose -f /root/coordinata56/docker-compose.yml ps backend
# Ожидаемый статус: "exited" или "stopped"
```

**Postgres НЕ останавливаем** — он продолжает работать, восстановление идёт в отдельный контейнер.

---

## Шаг 2 — Создать директорию для восстановления

```bash
mkdir -p "${RESTORE_PGDATA}"
chown 999:999 "${RESTORE_PGDATA}"   # UID postgres-пользователя внутри alpine-образа
chmod 700 "${RESTORE_PGDATA}"
```

---

## Шаг 3 — Скачать базовый бэкап

### Вариант А — wal-g (рекомендуемый)

```bash
# Найти последний бэкап перед моментом T
wal-g backup-list \
    --config /root/coordinata56/infra/wal-g.yaml \
    | head -10

# Скачать последний бэкап (LATEST) или конкретный по имени
wal-g backup-fetch "${RESTORE_PGDATA}" LATEST \
    --config /root/coordinata56/infra/wal-g.yaml
# Ожидаемый вывод: прогресс распаковки, в конце — "Backup fetch complete"
```

### Вариант Б — awscli (fallback)

```bash
# Определить нужную неделю (ищем бэкап, который ПРЕДШЕСТВУЕТ RECOVERY_TARGET_TIME)
aws s3 ls "s3://${S3_BUCKET}/basebackup/" --endpoint-url="${S3_ENDPOINT}"
# Пример: 2026-18/ (18-я неделя)

BACKUP_WEEK="2026-18"  # скорректировать по фактическому списку

# Скачать и распаковать
aws s3 cp \
    "s3://${S3_BUCKET}/basebackup/${BACKUP_WEEK}/base.tar.gz" \
    /tmp/base_restore.tar.gz \
    --endpoint-url="${S3_ENDPOINT}"

tar xzf /tmp/base_restore.tar.gz -C "${RESTORE_PGDATA}"
rm /tmp/base_restore.tar.gz
```

**Проверка:**

```bash
ls "${RESTORE_PGDATA}/"
# Ожидаемый вывод: PG_VERSION, global/, base/, pg_wal/ и другие стандартные директории PG
cat "${RESTORE_PGDATA}/PG_VERSION"
# Ожидаемый вывод: 16
```

---

## Шаг 4 — Настроить recovery

Создаём сигнальный файл и параметры восстановления:

```bash
# Сигнал для Postgres: войти в режим recovery
touch "${RESTORE_PGDATA}/recovery.signal"

# Параметры recovery — дописываем в auto.conf
cat >> "${RESTORE_PGDATA}/postgresql.auto.conf" <<EOF

# PITR restore — сгенерировано $(date -u +%Y-%m-%dT%H:%M:%SZ)
restore_command = 'aws s3 cp s3://${S3_BUCKET}/wal/%f %p --endpoint-url=${S3_ENDPOINT} --quiet'
recovery_target_time = '${RECOVERY_TARGET_TIME}'
recovery_target_action = 'promote'
EOF

# Если используется wal-g — заменить restore_command на:
# restore_command = 'wal-g wal-fetch %f %p --config /root/coordinata56/infra/wal-g.yaml'
```

**Проверка:**

```bash
grep -E "restore_command|recovery_target" "${RESTORE_PGDATA}/postgresql.auto.conf"
```

---

## Шаг 5 — Запустить restore-контейнер

```bash
# Запускаем отдельный контейнер (не трогаем основной coordinata56_postgres)
docker run -d \
    --name coordinata56_postgres_restore \
    --network coordinata56_internal \
    -p "127.0.0.1:${RESTORE_PORT}:5432" \
    -v "${RESTORE_PGDATA}:/var/lib/postgresql/data" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${PGPASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    mirror.gcr.io/library/postgres:16-alpine
```

**Следить за прогрессом recovery:**

```bash
docker logs -f coordinata56_postgres_restore 2>&1 | grep -E "recovery|started|LOG|HINT"
# Ожидаемые сообщения:
#   "starting point-in-time recovery"
#   "restored log file ... from archive"
#   "recovery stopping before commit of transaction..."
#   "pausing at the end of recovery"
# После promote:
#   "database system is ready to accept connections"
```

**Дождаться выхода из recovery (примерно 5–30 мин в зависимости от объёма WAL):**

```bash
# Проверяем раз в 30 секунд
until docker exec coordinata56_postgres_restore \
        psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -c "SELECT pg_is_in_recovery();" \
        -t --no-align 2>/dev/null | grep -q "^f$"; do
    echo "$(date -u +%H:%M:%SZ) — ещё в recovery..."
    sleep 30
done
echo "Recovery завершён: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

---

## Шаг 6 — Sanity-check

Сравниваем row-count по 7 ключевым таблицам с ожидаемыми значениями на момент T:

```bash
docker exec coordinata56_postgres_restore \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" <<'SQL'
SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS row_count
FROM pg_stat_user_tables
WHERE relname IN (
    'users',
    'companies',
    'projects',
    'houses',
    'house_types',
    'contracts',
    'payments'
)
ORDER BY relname;
SQL
```

**Ожидаемый результат:** количество строк соответствует состоянию на `RECOVERY_TARGET_TIME`.
Если числа подозрительно малы или таблицы пустые — см. раздел Troubleshooting.

---

## Шаг 7 — Переключить backend на restore-БД

**Вариант А (быстрый для аварии):** изменить DATABASE_URL в `.env.dev`:

```bash
# Сохранить старый URL
cp /root/coordinata56/.env.dev /root/coordinata56/.env.dev.bak_$(date +%Y%m%d_%H%M%S)

# Изменить порт в DATABASE_URL
sed -i "s|@postgres:5432/|@coordinata56_postgres_restore:5432/|g" \
    /root/coordinata56/.env.dev
# Или вручную отредактировать DATABASE_URL, указав порт ${RESTORE_PORT} на localhost
```

**Вариант Б (чистый):** переименовать базы данных:

```bash
# 1. Переименовать текущую БД в _incident
docker exec coordinata56_postgres \
    psql -U "${POSTGRES_USER}" -d postgres \
    -c "ALTER DATABASE ${POSTGRES_DB} RENAME TO ${POSTGRES_DB}_incident;"

# 2. Переименовать restore-БД в основное имя
docker exec coordinata56_postgres_restore \
    psql -U "${POSTGRES_USER}" -d postgres \
    -c "ALTER DATABASE ${POSTGRES_DB} RENAME TO ${POSTGRES_DB};"

# 3. Подключить restore-БД к основной сети/порту (через docker network connect или иначе)
```

---

## Шаг 8 — Запустить backend и проверить health

```bash
docker compose -f /root/coordinata56/docker-compose.yml start backend

# Дождаться старта (health check)
sleep 10
curl -s http://127.0.0.1:8000/api/v1/health | python3 -m json.tool
# Ожидаемый вывод: {"status": "ok", ...}
```

---

## Rollback — если PITR не удался

Если recovery завершился с ошибкой или данные некорректны — переходим к pg_dump restore:

```bash
# 1. Остановить restore-контейнер
docker stop coordinata56_postgres_restore
docker rm coordinata56_postgres_restore

# 2. Найти последний pg_dump
ls -lt /var/backups/coordinata56/pg_*.dump | head -5

# 3. Восстановить из дампа — см. backup-policy.md раздел «Процедура восстановления»
# RPO при этом = 24 часа (от последнего pg_dump), RTO = ~4 часа
```

---

## Очистка после успешного PITR

```bash
# Убрать restore-контейнер (БД уже переключена)
docker stop coordinata56_postgres_restore
docker rm coordinata56_postgres_restore

# Удалить временную директорию (только после подтверждения корректной работы backend)
rm -rf "${RESTORE_PGDATA}"

# Зафиксировать RTO
echo "PITR завершён: $(date -u +%Y-%m-%dT%H:%M:%SZ), recovery_target_time=${RECOVERY_TARGET_TIME}" \
    >> /var/backups/coordinata56/.pitr_history
```

---

## Troubleshooting

| Симптом | Причина | Решение |
|---------|---------|---------|
| `FATAL: could not find WAL file` | WAL-файл не загружен в S3 или restore_command неверный | Проверить `aws s3 ls s3://.../wal/` и формат restore_command |
| `FATAL: requested timeline 1 is not a parent of this server's history` | Попытка применить WAL с другой timeline | Убедиться что basebackup и WAL из одного непрерывного ряда |
| `recovery stopping before commit` | Нормально — Postgres достиг target_time | Дождаться promote, проверить pg_is_in_recovery() |
| row-count = 0 в таблицах | Basebackup взят после инцидента | Взять более ранний basebackup |
| `connection refused` на RESTORE_PORT | Контейнер ещё стартует или recovery не завершён | Подождать, следить за `docker logs` |
| Ошибка `could not open file...` для pg_wal | Неверные права на RESTORE_PGDATA | `chown -R 999:999 ${RESTORE_PGDATA}` |

---

---

## Drill-план (тестирование PITR на dev-данных)

Drill проводится на dev-среде с тестовыми данными. **Никогда не на production.**

### Предусловия drill

- WAL-архивация активна (`WAL_ARCHIVE_MODE=s3` или `local`)
- Последний pg_basebackup выполнен (`cat /var/backups/coordinata56/.last_basebackup_success`)
- В таблице `users` есть минимум 1 строка (dev-данные)

---

### Сценарий 1 (Recent) — восстановление на «час назад»

**Цель:** проверить штатный PITR на свежих данных. Наиболее вероятный prod-сценарий.

```
T+0:00  Зафиксировать row-count таблицы users → значение N1
T+0:15  INSERT тестового пользователя (email: pitr-drill-recent@test.local)
        Записать точное время T_add (UTC, с секундами)
        Проверить row-count → N1+1
T+0:30  DELETE FROM users WHERE email = 'pitr-drill-recent@test.local'
        Симуляция «случайного удаления»
T+0:35  Запустить PITR с RECOVERY_TARGET_TIME = T_add + 10s
        Пройти все шаги 1–8 runbook
```

**Ожидаемый результат:**
- После recovery row-count users = N1+1
- Пользователь pitr-drill-recent@test.local присутствует
- RPO = время от T_add до момента обнаружения = ~15 мин
- RTO = время от старта drill (T+0:35) до ответа /healthz = фиксировать фактически

**Критерий успеха:** row-count совпадает, /healthz = ok.

---

### Сценарий 2 (Mid-age) — восстановление на «день назад»

**Цель:** проверить работу с более старым basebackup и длинной WAL-цепочкой.

```
День D-1, 10:00 UTC:
  Зафиксировать row-count: companies → C1, projects → P1, houses → H1
  Записать RECOVERY_TARGET_TIME = "D-1 10:05:00+00"

День D (сегодня, drill):
  1. Взять basebackup недельной давности (если есть) или последний pg_basebackup
  2. Установить RECOVERY_TARGET_TIME = "D-1 10:05:00+00"
  3. Пройти шаги 1–8 runbook
```

**Ожидаемый результат:**
- row-count по companies, projects, houses совпадает с зафиксированным значением D-1 10:05
- Все данные, добавленные позже, отсутствуют (ожидаемо и корректно)

**Дополнительная проверка:** убедиться что WAL-цепочка между basebackup D-2 и моментом D-1 10:05 непрерывна.
При разрыве — фиксируем в drill-отчёте, это операционный риск.

---

### Сценарий 3 (Edge case) — WAL-файл отсутствует / прерванная цепочка

**Цель:** проверить поведение системы при ошибке restore_command.

```
1. Временно переименовать один WAL-файл в S3/local:
   aws s3 mv s3://.../wal/000000010000000000000003 \
             s3://.../wal/000000010000000000000003.bak \
             --endpoint-url=...

2. Запустить PITR с RECOVERY_TARGET_TIME за этим файлом

3. Зафиксировать поведение:
   - Postgres пишет в лог ошибку "could not open file..."
   - Recovery останавливается на последнем доступном WAL
   - Проверить что система не «зависает молча», а явно сигнализирует об ошибке

4. Вернуть файл:
   aws s3 mv s3://.../wal/000000010000000000000003.bak \
             s3://.../wal/000000010000000000000003 \
             --endpoint-url=...
```

**Ожидаемый результат:**
- Postgres явно пишет ошибку в лог (не молчит)
- Восстановление останавливается на максимально возможной точке (не падает без данных)
- Оператор получает понятное сообщение об ошибке и может перейти к rollback-плану

**Критерий успеха:** система явно сообщает о разрыве цепочки, не теряет уже восстановленные данные.

---

### Форма фиксации результатов drill

После каждого drill создать файл:

```
docs/pods/cottage-platform/infrastructure/pitr-drill-YYYY-MM-DD.md
```

Содержимое:

```markdown
# PITR Drill — YYYY-MM-DD

**Сценарий:** Recent / Mid-age / Edge case
**Исполнитель:** devops
**Ревьюер:** devops-head (повторный прогон)
**Среда:** dev

## Хронология
- HH:MM UTC — [шаг]
- ...

## Результаты
- RPO факт: X мин
- RTO факт: Y мин
- row-count ожидаемый / фактический: N / N

## Отклонения от runbook
- [список или «Отклонений нет»]

## Предложения по правкам runbook
- [список или «Нет»]
```

---

## Связанные документы

- `infra/backups/README.md` — настройка WAL-архивации
- `infra/backups/wal_archive.sh` — скрипт архивации WAL
- `docs/pods/cottage-platform/infrastructure/backup-policy.md` — политика, RTO/RPO
