# P0-2: Ежедневный pg_dump + retention 14 дней

**Источник:** `docs/pods/cottage-platform/infrastructure/quick-wins-plan.md` §3, P0-2
**Автор брифа:** infra-director
**Дата:** 2026-04-18
**Адресаты:**
- `devops-head` → `devops` (cron, скрипт, systemd)
- `db-head` → `db-engineer` (формат дампа, restore-верификация)
**Статус:** approved, готов к исполнению
**Приоритет:** P0
**Оценка:** 3 ч devops + 1 ч db-engineer + 1 ч ревью = 5 ч суммарно (параллельно)

---

## 1. Цель

Не терять данные Postgres при падении диска, повреждении volume или ошибке миграции.
Ежедневный дамп на хостовой диск + 14-дневная ротация + подтверждённая процедура восстановления.

**Важно:** это **dev-бэкап**, не production-бэкап. Off-site storage (S3 / Selectel Object Storage)
— отдельная задача перед Фазой 9 (см. `quick-wins-plan.md` §6, Риск 1).

## 2. Контекст

- Volume `coordinata56_postgres_data` весит 123 MB (по `docker system df -v` на 2026-04-18).
- Postgres слушает `127.0.0.1:5433` на хосте (см. `docker-compose.yml:21`).
- Креды лежат в `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` переменных
  (см. `.env.dev.example` и `docker-compose.yml:15-17`).
- Хост — Ubuntu 24.04 (Linux 6.8), есть cron и systemd.
- Пользователь Владельца — `root` (dev-окружение). В production будет отдельный юзер.

## 3. Разделение ответственности

| Вертикаль | Ответственность | Worker |
|-----------|-----------------|--------|
| DevOps | скрипт `pg_dump_daily.sh`, cron/timer, retention, маркер успеха | `devops` |
| Database | формат дампа (`-Fc` custom), список исключений, restore-верификация | `db-engineer` |

Параллелизация: db-engineer согласует формат **до** старта devops (блокер для скрипта).
Иначе devops напишет под plain SQL, потом переделывать.

---

## 4. Часть A — `db-engineer` (делает первым, ~1 ч)

### A.1. Формат дампа

Использовать **custom format** `pg_dump -Fc`:
- Сжатие встроено (уровень 6 по умолчанию — разумный баланс CPU/размер).
- Позволяет частичное восстановление через `pg_restore --table=...`.
- Быстрее, чем plain SQL для восстановления.

Альтернатива `-Fp` (plain SQL) **отклоняется**: больше по размеру, медленнее restore,
частичное восстановление только через ручной grep.

### A.2. Список исключений

На 2026-04-18 исключать **нечего** — таблиц мало, все нужны.
Задокументировать в самом скрипте комментарием:
```bash
# Исключений нет. Если в будущем появятся audit_log_raw / temp_* / cache_* —
# добавить --exclude-table=audit_log_raw и т.п., согласовав с db-engineer.
```

### A.3. Команда дампа (эталонная)

```bash
pg_dump \
  --host=127.0.0.1 \
  --port=5433 \
  --username="${POSTGRES_USER}" \
  --dbname="${POSTGRES_DB}" \
  --format=custom \
  --compress=6 \
  --no-owner \
  --no-privileges \
  --file="${BACKUP_FILE}"
```

`--no-owner` и `--no-privileges` — чтобы restore работал на любую БД/роль
(dev имеет только одного юзера, но закладываем под будущее).

Пароль — через `PGPASSWORD` env в скрипте (не через `-W`, не как аргумент).

### A.4. Верификация restore (обязательно, один раз при сдаче)

```bash
# Создать временную пустую БД для проверки
docker exec coordinata56_postgres psql -U "${POSTGRES_USER}" -d postgres \
  -c "CREATE DATABASE coordinata56_restore_test;"

# Скормить дамп
gunzip -c /var/backups/coordinata56/pg_YYYYMMDD_HHMMSS.dump | \
  docker exec -i coordinata56_postgres pg_restore \
  -U "${POSTGRES_USER}" -d coordinata56_restore_test \
  --no-owner --no-privileges

# Sanity check — количество таблиц
docker exec coordinata56_postgres psql -U "${POSTGRES_USER}" \
  -d coordinata56_restore_test \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# Сравнить с боевой БД — должно совпадать
docker exec coordinata56_postgres psql -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# Убрать за собой
docker exec coordinata56_postgres psql -U "${POSTGRES_USER}" -d postgres \
  -c "DROP DATABASE coordinata56_restore_test;"
```

**DoD части A:** числа таблиц совпадают, `db-engineer` пишет в отчёте
«restore верифицирован, X таблиц совпало».

---

## 5. Часть B — `devops` (после согласования с db-engineer, ~3 ч)

### B.1. Структура файлов

```
infra/
  backups/
    pg_dump_daily.sh          # главный скрипт
    README.md                 # runbook для ручного запуска и восстановления
/var/backups/coordinata56/
  pg_20260418_030000.dump     # формат custom, уже сжатый
  pg_20260419_030000.dump
  ...
  .last_success               # timestamp последнего успеха (ISO 8601)
  .last_error                 # последняя ошибка (если была)
```

Путь `/var/backups/coordinata56/` — стандарт FHS, требует `mkdir -p` и владельца `root:root`
с правами `750` (только root читает дампы).

**Важно про расширение:** `-Fc` уже сжат внутри, дополнительный `gzip` избыточен.
Имя файла — `pg_YYYYMMDD_HHMMSS.dump`, **не `.sql.gz`** (согласовано с db-engineer в §A.1).
В брифе Координатора упомянут `.sql.gz` — это устаревший вариант из черновика, для `-Fc`
дампов правильно `.dump`.

### B.2. Скрипт `infra/backups/pg_dump_daily.sh`

Требования:
- `set -euo pipefail` в начале.
- Переменные окружения читает из `/root/coordinata56/.env.dev` (production-путь меняется позже).
- Timestamp: `$(date -u +%Y%m%d_%H%M%S)` — UTC, без локалей.
- Лог идёт в `/var/log/coordinata56-backup.log` (через `logger` или append).
- После успешного дампа пишет ISO-timestamp в `/var/backups/coordinata56/.last_success`.
- При ошибке пишет в `.last_error` и возвращает ненулевой exit-code (чтобы cron прислал email
  при наличии MTA; без MTA — хотя бы виден в `/var/log/syslog`).
- Retention: `find /var/backups/coordinata56 -name 'pg_*.dump' -mtime +14 -delete`.
- **Перед `find -delete`** проверять наличие хотя бы одного файла моложе 1 дня (защита от
  удаления всего при багованном скрипте): если последний успех старше 48 часов — НЕ удалять
  ничего, писать в `.last_error`.

Эталонный скелет (адаптирует `devops`):

```bash
#!/usr/bin/env bash
# pg_dump_daily.sh — ежедневный дамп coordinata56 с retention 14 дней
# Запускается из cron. Логи: /var/log/coordinata56-backup.log
# Маркер успеха: /var/backups/coordinata56/.last_success
set -euo pipefail

BACKUP_DIR="/var/backups/coordinata56"
ENV_FILE="/root/coordinata56/.env.dev"
LOG_FILE="/var/log/coordinata56-backup.log"
RETENTION_DAYS=14

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG_FILE"; }
fail() { echo "$(date -u +%FT%TZ) $*" > "$BACKUP_DIR/.last_error"; log "FAIL: $*"; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 750 "$BACKUP_DIR"

[[ -f "$ENV_FILE" ]] || fail ".env.dev not found at $ENV_FILE"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

STAMP=$(date -u +%Y%m%d_%H%M%S)
OUT="$BACKUP_DIR/pg_${STAMP}.dump"

log "starting pg_dump -> $OUT"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  --host=127.0.0.1 --port=5433 \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --format=custom --compress=6 \
  --no-owner --no-privileges \
  --file="$OUT" || fail "pg_dump returned non-zero"

# Базовая sanity-проверка: файл > 1 KB
[[ $(stat -c%s "$OUT") -gt 1024 ]] || fail "dump too small: $(stat -c%s "$OUT") bytes"

date -u +%FT%TZ > "$BACKUP_DIR/.last_success"
rm -f "$BACKUP_DIR/.last_error"
log "dump ok, size=$(du -h "$OUT" | cut -f1)"

# Retention — удаляем старше 14 дней, но только если за последние 48 ч был успех
LAST_OK_EPOCH=$(date -d "$(cat "$BACKUP_DIR/.last_success")" +%s)
NOW_EPOCH=$(date +%s)
if (( NOW_EPOCH - LAST_OK_EPOCH < 172800 )); then
  find "$BACKUP_DIR" -maxdepth 1 -name 'pg_*.dump' -mtime +"$RETENTION_DAYS" -delete -print | \
    while read -r f; do log "retention: removed $f"; done
else
  log "retention skipped: last success too old"
fi
```

`pg_dump` нужен на **хосте**. Варианты установки:
- `apt install postgresql-client-16` — даёт `pg_dump` нужной версии.
- **Или** вызов через `docker exec coordinata56_postgres pg_dump ...` — тогда дамп идёт
  на stdout, пишется в файл через `>`. **Выбор:** `docker exec`, чтобы не тянуть на хост
  отдельный postgresql-client (меньше точек дрейфа версий).

В этом случае команда превращается в:
```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" coordinata56_postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --format=custom --compress=6 --no-owner --no-privileges > "$OUT"
```

`devops` финализирует выбор (host-client vs docker exec) и фиксирует обоснование в README.

### B.3. Cron-запись

```cron
# /etc/cron.d/coordinata56-backup (owner root, mode 0644)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Ежедневный дамп Postgres в 03:00 UTC (06:00 MSK)
0 3 * * * root /root/coordinata56/infra/backups/pg_dump_daily.sh
```

Почему cron, а не systemd timer: меньше новых абстракций, Владелец видит одну строку
в `/etc/cron.d/`. При миграции на K8s (после Фазы 9) перейдём на `CronJob`.

**Альтернатива — отдельный контейнер в docker-compose** (из quick-wins-plan.md §3):
отклонена на этой итерации ради простоты. Причина: требует образ с `pg_dump` той же мажорной
версии что и сервер (16), отдельный entrypoint с cron внутри, volume-маунт `/var/backups`.
Это +2 часа работы без ощутимой выгоды на dev. Вернёмся перед Фазой 9.

### B.4. Мониторинг через `.last_success`

Файл `/var/backups/coordinata56/.last_success` содержит ISO-timestamp последнего успеха.
Простейший check (будущий P1 — превратить в Prometheus-exporter):

```bash
# Проверка свежести: не старше 26 часов
LAST=$(stat -c%Y /var/backups/coordinata56/.last_success 2>/dev/null || echo 0)
AGE=$(( $(date +%s) - LAST ))
[[ $AGE -lt 93600 ]] || echo "ALARM: backup stale, age=$AGE seconds"
```

26 часов = 24 + 2 часа запас. Логика — если cron пропустил один запуск (сервер выключили),
алерт сработает после следующего нормального запуска + запас.

### B.5. Runbook `infra/backups/README.md`

Минимум:
1. Как запустить вручную: `sudo /root/coordinata56/infra/backups/pg_dump_daily.sh`.
2. Как восстановить из дампа (копипаст-команды из §A.4 с переменными).
3. Где логи (`/var/log/coordinata56-backup.log`).
4. Где маркеры (`.last_success`, `.last_error`).
5. Как проверить cron: `sudo run-parts --test /etc/cron.d/` (или `systemctl status cron`).
6. **Красным:** восстановление в production — запрещено без разрешения Владельца.

---

## 6. Definition of Done (общий)

- [ ] `infra/backups/pg_dump_daily.sh` создан, `chmod +x`, прошёл `shellcheck`.
- [ ] `/etc/cron.d/coordinata56-backup` установлен, cron перечитал (`systemctl reload cron`).
- [ ] Скрипт отработал вручную один раз: `.last_success` обновился, файл `.dump` создан и > 1 KB.
- [ ] `db-engineer` верифицировал restore на временной БД, числа таблиц совпали.
- [ ] `infra/backups/README.md` написан.
- [ ] `.gitignore` исключает `/var/backups/` и `*.dump` (защита от случайного коммита дампов).
- [ ] Документация путей и retention в `docs/pods/cottage-platform/infrastructure/backups.md`
  (новый файл, пишет db-engineer вместе с Makefile-таргетами в P1-5).
- [ ] Git-коммит включает только: `infra/backups/pg_dump_daily.sh`, `infra/backups/README.md`,
  `.gitignore` (минимальный diff), возможно `/etc/cron.d/coordinata56-backup` **как текстовый
  пример** в `infra/backups/cron.example` (сам файл в `/etc/` не коммитится).

## 7. Что явно НЕ делать

- **Не** заливать дампы на S3 / внешние хранилища — это отдельная задача перед Фазой 9.
- **Не** шифровать дампы GPG в этой итерации — dev-окружение, добавит сложности без ценности.
  (В production — обязательно, но это отдельный тикет с управлением ключами.)
- **Не** удалять `.last_error` из кода — он сигнал для будущего мониторинга.
- **Не** коммитить `.env.dev` ни при каких условиях — см. CLAUDE.md «Секреты».
- **Не** запускать restore на боевую БД — только на `coordinata56_restore_test`.
- **Не** коммитить самому — коммит делает Координатор после вердикта infra-director.

## 8. Цепочка round-trip

1. `db-engineer` делает §A, отчёт в `db-head`.
2. `db-head` ревьюит → даёт зелёный свет `devops` через `infra-director` (кросс-Head
   коммуникация идёт через Директора — см. CLAUDE.md «Паттерн Координатор-транспорт»).
3. `devops` делает §B, опираясь на согласованный формат.
4. `devops-head` ревьюит.
5. `infra-director` утверждает весь комплект.
6. Координатор коммитит.

## 9. Риски

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| pg_dump на хосте запустился с `postgresql-client-15`, сервер — 16 | низкая | средний (warning, но дамп нормальный) | используем `docker exec` — версия совпадёт автоматически |
| `find -delete` удалит всё при зависшем cron на неделю | низкая | высокий (потеря истории) | защита в скрипте: retention только при свежем success <48ч |
| `.env.dev` отсутствует / дрейфует → скрипт падает молча | средняя | средний | скрипт явно проверяет наличие и пишет в `.last_error` |
| Дамп растёт до сотен GB | низкая на dev | низкий | retention 14 дней держит ≤14×текущий_размер; пересмотр при росте БД >10 GB |
| Владелец случайно запустит restore на prod через runbook | низкая | критический | в README красным: «prod — только с разрешения Владельца»; `make restore` (P1-5) требует интерактивное подтверждение |
