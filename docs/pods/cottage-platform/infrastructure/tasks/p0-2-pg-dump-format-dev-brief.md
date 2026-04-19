# Dev-бриф: P0-2 Часть A — Формат pg_dump + Restore-верификация

**Кому:** db-engineer
**От кого:** db-head (coordinata56)
**Дата брифа:** 2026-04-18
**Источник:** `docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-backup.md` §4
**Статус:** ready-to-work
**Оценка трудозатрат:** ~1 ч

---

## 1. Контекст

Мы реализуем ежедневный бэкап Postgres для dev-окружения (`coordinata56_dev`).
Задача разбита на две части: ты делаешь часть A (формат + верификация),
devops делает часть B (скрипт + cron + retention) — и **блокируется на результат части A**.
Без твоего документа devops не знает, под какой формат писать скрипт.

Postgres слушает на `127.0.0.1:5433`. Контейнер называется `coordinata56_postgres`.
Переменные окружения — в `/root/coordinata56/.env.dev` (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB).

---

## 2. Что нужно сделать

### Задача A.1 — Эталонная команда pg_dump

Формат: **custom (-Fc)**, уровень сжатия 6. Никаких `.sql.gz`.
Расширение файла — `.dump`. Пример имени: `pg_20260418_030000.dump`.

Эталонная команда (используется через `docker exec`, чтобы не тянуть на хост отдельный postgresql-client):

```bash
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

Ключи:
- `--no-owner`, `--no-privileges` — restore будет работать на любой роли/среде.
- `--compress=6` — встроенное zlib-сжатие; внешний gzip не нужен и не применяется.
- Пароль через `PGPASSWORD` env, не через `-W` и не как аргумент процесса.

На момент 2026-04-18 исключений нет — все 23 таблицы дампятся целиком.
Задокументируй это явно в своём документе с комментарием:
```bash
# Исключений нет. Если появятся audit_log_raw / temp_* / cache_* —
# добавить --exclude-table=audit_log_raw, согласовав с db-head.
```

### Задача A.2 — Restore-верификация (обязательно, один прогон)

Цель: убедиться что дамп читается, все таблицы восстанавливаются, row-count совпадает.

**Шаг 1. Создать временную БД:**

```bash
source /root/coordinata56/.env.dev
docker exec coordinata56_postgres \
  psql -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE coordinata56_restore_test;"
```

**Шаг 2. Восстановить из дампа:**

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  pg_restore \
  -U "$POSTGRES_USER" \
  -d coordinata56_restore_test \
  --no-owner \
  --no-privileges \
  < /var/backups/coordinata56/<имя_дампа>.dump
```

**Шаг 3. Sanity-check — количество таблиц:**

```bash
# В restore-БД
docker exec coordinata56_postgres psql -U "$POSTGRES_USER" \
  -d coordinata56_restore_test \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# В боевой БД
docker exec coordinata56_postgres psql -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
```

Ожидаемый результат: оба запроса возвращают **23** (текущее количество таблиц public-схемы на 2026-04-18).

**Шаг 4. Row-count по ключевым таблицам:**

Выполни этот запрос в ОБЕИХ базах и убедись, что числа совпадают:

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

Базовые значения на 2026-04-18 (dev-база до заполнения):

| Таблица     | Строк |
|-------------|-------|
| companies   | 1     |
| contracts   | 0     |
| houses      | 0     |
| permissions | 23    |
| projects    | 0     |
| roles       | 6     |
| users       | 0     |

Если по какой-то таблице числа расходятся — это блокер, верификация не пройдена.

**Шаг 5. Убрать за собой:**

```bash
docker exec coordinata56_postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE coordinata56_restore_test;"
```

**Важно:** никогда не запускать pg_restore на боевую базу `$POSTGRES_DB`. Только на `coordinata56_restore_test`.

### Задача A.3 — Документ формата

Создать файл:
`docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-format-spec.md`

Структура документа:

1. **Обоснование формата -Fc vs plain + gzip**
   - Сравнительная таблица: размер, скорость restore, частичное восстановление, сложность
   - Почему -Fp отклонён

2. **Эталонная команда pg_dump** (из §A.1 выше, verbatim)

3. **Процедура pg_restore-верификации**
   - Все шаги из §A.2 как копипаст-команды с переменными
   - Пояснение: когда применяется (при сдаче задачи + опционально при подозрении на повреждение)

4. **Критерии корректности восстановления**
   - Количество таблиц в public-схеме совпадает с боевой БД
   - Row-count по 7 ключевым таблицам совпадает
   - pg_restore завершился с exit-code 0 (или только с WARNING, без ERROR)
   - Размер .dump-файла > 1 KB

5. **Список исключений** — пока пусто, с комментарием для будущего

---

## 3. Что НЕ надо делать

- Не писать скрипт cron — это делает devops (часть B)
- Не создавать retention-логику
- Не трогать `/etc/cron.d/`
- Не коммитить — коммит делает Координатор после финального вердикта infra-director
- Не применять restore на боевую базу `$POSTGRES_DB`
- Не шифровать дамп GPG — это отдельный трек перед production

---

## 4. Ограничения доступа к файлам

FILES_ALLOWED (создать / изменить):
- `docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-format-spec.md` — создать
- `/var/backups/coordinata56/` — директория для тестового дампа (mkdir -p при необходимости)

FILES_FORBIDDEN:
- `backend/` — никаких правок кода
- `.env.dev` — только читать для получения переменных, не изменять
- `infra/backups/` — это территория devops
- `/etc/cron.d/` — не трогать

---

## 5. Формат отчёта (вернуть db-head)

```
## Отчёт db-engineer: P0-2 Часть A

### Результат restore-верификации
- Количество таблиц в coordinata56_restore_test: XX
- Количество таблиц в coordinata56_dev: XX
- Совпадение: да / нет
- Row-count по ключевым таблицам: [таблица совпадения или расхождения]
- pg_restore exit-code: 0 / предупреждения: [если есть]
- Размер .dump-файла: XX KB

### Созданный документ
- Путь: docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-format-spec.md
- Статус: готов / требует доработки

### Наблюдения
[если были нестандартные ситуации]
```

---

## 6. Регламентные ссылки

- `CLAUDE.md` (корень проекта) — основные правила, разделы «Данные/БД», «Секреты и тесты»
- `docs/agents/departments/infrastructure.md` — правила отдела
- `docs/pods/cottage-platform/infrastructure/tasks/p0-2-pg-dump-backup.md` — исходный бриф infra-director (§4 целиком)
- `docs/agents/regulations/head.md` — регламент Начальника отдела
