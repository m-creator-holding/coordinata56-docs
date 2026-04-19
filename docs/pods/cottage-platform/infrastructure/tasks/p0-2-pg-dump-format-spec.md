# Spec: P0-2 Часть A — Формат pg_dump и процедура restore-верификации

**Составлен:** db-engineer  
**Дата:** 2026-04-18  
**Статус:** утверждён (restore-верификация пройдена)  
**Используется:** devops (Часть B — скрипт + cron + retention)

---

## 1. Обоснование формата: `-Fc` vs plain + gzip

### Сравнительная таблица

| Критерий                       | `-Fp` (plain SQL)        | `-Fp` + внешний gzip          | `-Fc` (custom, выбран)           |
|--------------------------------|--------------------------|-------------------------------|----------------------------------|
| Формат файла                   | текстовый SQL            | сжатый текстовый SQL          | бинарный, сжатый zlib            |
| Расширение                     | `.sql`                   | `.sql.gz`                     | `.dump`                          |
| Сжатие                         | нет                      | внешнее (gzip/zstd)           | встроенное (zlib, уровень 1–9)   |
| Восстановление                 | `psql -f file.sql`       | `zcat file.sql.gz \| psql`    | `pg_restore -d db file.dump`     |
| Частичное восстановление       | невозможно               | невозможно                    | да: `-t table`, `-n schema`      |
| Параллельный restore (`-j N`)  | нет                      | нет                           | да                               |
| Pipe-безопасность              | не применимо             | да (stdin/stdout)             | да (через stdin с флагом `-i`)   |
| Зависимость от внешних утилит  | нет                      | gzip/zstd на хосте            | нет (встроено в pg_restore)      |
| Относительный размер файла     | 100%                     | ~15–30% от plain              | ~15–30% от plain                 |
| Сложность команды restore      | низкая                   | средняя                       | низкая                           |

### Почему `-Fp` отклонён

1. Нет встроенного сжатия — файл в 5–10 раз крупнее, что критично для ежедневного retention.
2. Нет частичного восстановления — при точечном инциденте (потеря одной таблицы) придётся накатывать весь дамп.
3. Нет параллельного restore — время восстановления линейно растёт с размером БД.
4. С `gzip` требует двух инструментов в pipeline, усложняет скрипты и мониторинг exit-кода.

### Вывод

Формат `-Fc` (`--format=custom`) — стандарт PostgreSQL для production-backup. Сжатие, частичный restore, параллелизм — при нулевой зависимости от внешних утилит.

---

## 2. Эталонная команда pg_dump

```bash
# Исключений нет. Если появятся audit_log_raw / temp_* / cache_* —
# добавить --exclude-table=audit_log_raw, согласовав с db-head.

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --format=custom \
  --compress=6 \
  --no-owner \
  --no-privileges \
> /var/backups/coordinata56/pg_$(date -u +%Y%m%d_%H%M%S).dump
```

### Пояснение флагов

| Флаг                  | Назначение                                                                                  |
|-----------------------|---------------------------------------------------------------------------------------------|
| `--format=custom`     | Бинарный формат pg_dump (-Fc); обязателен для pg_restore                                    |
| `--compress=6`        | Встроенное zlib-сжатие, уровень 6 (баланс скорость/размер); внешний gzip не нужен           |
| `--no-owner`          | Не записывает SET ROLE / ALTER TABLE OWNER — restore работает на любой роли                 |
| `--no-privileges`     | Не записывает GRANT/REVOKE — права выдаются заново в целевой среде                          |
| `-e PGPASSWORD`       | Пароль через env-переменную (не аргумент процесса — не виден в ps aux и системных логах)    |

### Имя файла

Шаблон: `pg_YYYYMMDD_HHMMSS.dump`  
Пример: `pg_20260418_030000.dump`  
Время — UTC (`date -u`), чтобы избежать путаницы при переходе DST.

---

## 3. Процедура restore-верификации

**Когда применяется:**
- При каждой сдаче задачи, затрагивающей схему бэкапа (обязательно).
- При подозрении на повреждение дамп-файла (опционально, по запросу devops или db-head).
- При смене мажорной версии PostgreSQL.

### Шаг 0 — Загрузить переменные окружения

```bash
source /root/coordinata56/.env.dev
# Или задать явно:
# POSTGRES_USER=coordinata
# POSTGRES_PASSWORD=dev_password_change_me
# POSTGRES_DB=coordinata56
```

### Шаг 1 — Создать дамп (если нет готового тестового)

```bash
DUMP_FILE="/var/backups/coordinata56/test_$(date +%Y%m%d_%H%M%S).dump"

docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --format=custom \
  --compress=6 \
  --no-owner \
  --no-privileges \
> "$DUMP_FILE"

echo "pg_dump exit: $?"
ls -lh "$DUMP_FILE"
```

### Шаг 2 — Создать временную БД

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  psql -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE coordinata56_restore_test;"
```

### Шаг 3 — Восстановить из дампа

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i coordinata56_postgres \
  pg_restore \
  -U "$POSTGRES_USER" \
  -d coordinata56_restore_test \
  --no-owner \
  --no-privileges \
  < "$DUMP_FILE"

echo "pg_restore exit: $?"
```

> WARNING на `--no-owner` допустимы. Любая строка `ERROR:` — блокер, верификация не пройдена.

### Шаг 4 — Sanity-check: количество таблиц

```bash
# В restore-БД
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  psql -U "$POSTGRES_USER" -d coordinata56_restore_test \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# В боевой БД
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
```

Ожидаемый результат: оба запроса возвращают одинаковое число.  
Базовое значение на 2026-04-18: **23 таблицы**.

### Шаг 5 — Row-count по 7 ключевым таблицам

Выполнить в обеих БД, убедиться в совпадении:

```sql
SELECT 'companies'  AS tbl, count(*) FROM companies   UNION ALL
SELECT 'users',              count(*) FROM users        UNION ALL
SELECT 'houses',             count(*) FROM houses       UNION ALL
SELECT 'contracts',          count(*) FROM contracts    UNION ALL
SELECT 'projects',           count(*) FROM projects     UNION ALL
SELECT 'roles',              count(*) FROM roles        UNION ALL
SELECT 'permissions',        count(*) FROM permissions
ORDER BY tbl;
```

### Шаг 6 — Убрать за собой

```bash
# Удалить тестовую БД
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  psql -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE coordinata56_restore_test;"

# Удалить тестовый дамп
rm "$DUMP_FILE"
```

---

## 4. Критерии корректности восстановления

Все четыре критерия должны быть выполнены одновременно. Несоответствие хотя бы одному — блокер.

| №  | Критерий                                                                 | Ожидаемый результат                               |
|----|--------------------------------------------------------------------------|---------------------------------------------------|
| 1  | `pg_dump` exit-code                                                       | 0                                                 |
| 2  | `pg_restore` exit-code                                                    | 0 (WARNING допустимы, ERROR недопустимы)          |
| 3  | Размер `.dump`-файла                                                      | > 1 KB                                            |
| 4  | Количество таблиц в `public`-схеме restore-БД                             | Совпадает с боевой БД                             |
| 5  | Row-count по 7 ключевым таблицам (companies, users, houses, contracts, projects, roles, permissions) | Совпадает с боевой БД построчно |

---

## 5. Список таблиц public-схемы (baseline 2026-04-18)

### Полный список (23 таблицы)

| № | Таблица                   |
|---|---------------------------|
| 1 | alembic_version           |
| 2 | audit_log                 |
| 3 | budget_categories         |
| 4 | budget_plan               |
| 5 | companies                 |
| 6 | contractors               |
| 7 | contracts                 |
| 8 | house_configurations      |
| 9 | house_stage_history       |
| 10 | house_type_option_compat |
| 11 | house_types              |
| 12 | houses                   |
| 13 | material_purchases       |
| 14 | option_catalog           |
| 15 | payments                 |
| 16 | pd_policies              |
| 17 | permissions              |
| 18 | projects                 |
| 19 | role_permissions         |
| 20 | roles                    |
| 21 | stages                   |
| 22 | user_company_roles       |
| 23 | users                    |

### Row-count baseline по 7 ключевым таблицам (до заполнения dev-данными)

| Таблица     | Строк |
|-------------|------:|
| companies   | 1     |
| contracts   | 0     |
| houses      | 0     |
| permissions | 23    |
| projects    | 0     |
| roles       | 6     |
| users       | 0     |

> **Внимание:** эти значения — baseline пустой dev-БД на 2026-04-18. После заполнения тестовыми данными числа изменятся. Критерий верификации — совпадение restore с боевой БД на момент создания дампа, а не совпадение с этой таблицей.

---

## 6. Исключения из дампа

На момент 2026-04-18 исключений нет. Все 23 таблицы дампятся целиком.

```bash
# Исключений нет. Если появятся audit_log_raw / temp_* / cache_* —
# добавить --exclude-table=audit_log_raw, согласовав с db-head.
```

При добавлении исключений:
1. Согласовать с db-head.
2. Добавить в эталонную команду флаг `--exclude-table=<имя>`.
3. Обновить этот документ — раздел 2 и 5.

---

## 7. Ссылки

- Бриф задачи: `docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-format-dev-brief.md`
- Исходный бриф infra-director: `docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-backup.md`
- PostgreSQL 16 pg_dump: https://www.postgresql.org/docs/16/app-pgdump.html
- PostgreSQL 16 pg_restore: https://www.postgresql.org/docs/16/app-pgrestore.html
