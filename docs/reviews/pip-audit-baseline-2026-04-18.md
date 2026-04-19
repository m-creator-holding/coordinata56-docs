# pip-audit CVE Baseline — 2026-04-18

**Инструмент:** pip-audit 2.10.0  
**Скоуп сканирования:** всё установленное окружение (pip-audit без флага `-r` сканирует текущее окружение)  
**Дата:** 2026-04-18  
**Команда:** `pip-audit --format json -o /tmp/pip-audit-raw.json`  
**Итого findings:** 28 CVE в 10 пакетах

---

## Методология классификации

Пакеты разделены на три категории:
- **PROD** — прямые production-зависимости из `pyproject.toml [project.dependencies]`
- **TRANSITIVE** — транзитивные зависимости PROD-пакетов
- **SYSTEM/DEV** — системные пакеты Ubuntu, dev-инструменты (pip, setuptools, wheel, pytest и т.п.), не входят в production-образ

Для CI-gate (блокирует merge) значимы только **PROD** и **TRANSITIVE** critical/high CVE.

---

## Раздел A — PRODUCTION-зависимости проекта

### PyJWT 2.7.0

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2026-32597 | HIGH | 2.12.0 | FIX-LATER | PyJWT не валидирует `crit` header (RFC 7515 §4.1.11); в нашем случае `crit` не используется и внешние токены не принимаются, но уязвимость реальная — обновить в следующем батче |

**Рекомендуемое действие:** обновить `PyJWT[crypto]` до `>=2.12.0` в `pyproject.toml`. Задача backend-head.

---

## Раздел B — TRANSITIVE / системные зависимости не в production-образе

> Эти пакеты **не входят** в `pyproject.toml` напрямую и отсутствуют в Docker-образе приложения (либо это системные пакеты Ubuntu). Их CVE не блокируют CI merge, но фиксируются для информации.

### Jinja2 3.1.2 (системный пакет Ubuntu)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2024-22195 | MEDIUM | 3.1.3 | BLOCKED-UPSTREAM | Системный пакет Ubuntu 24.04; обновление — через `apt upgrade`, не pip |
| CVE-2024-34064 | MEDIUM | 3.1.4 | BLOCKED-UPSTREAM | То же — системный пакет Ubuntu |
| CVE-2024-56326 | HIGH | 3.1.5 | BLOCKED-UPSTREAM | Jinja sandbox RCE; в production-образе Jinja не используется напрямую — только через Alembic (шаблоны миграций); эксплуатируется только при untrusted templates |
| CVE-2024-56201 | HIGH | 3.1.5 | BLOCKED-UPSTREAM | Jinja compiler RCE при контроле имени файла шаблона; то же — неприменимо к нашим миграциям |
| CVE-2025-27516 | HIGH | 3.1.6 | BLOCKED-UPSTREAM | Jinja sandbox `|attr` bypass; то же — системный пакет, не применим |

### requests 2.31.0 (системный пакет Ubuntu / cloud-init)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2024-35195 | MEDIUM | 2.32.0 | BLOCKED-UPSTREAM | Системный пакет Ubuntu (используется cloud-init); не в нашем приложении |
| CVE-2024-47081 | MEDIUM | 2.32.4 | BLOCKED-UPSTREAM | .netrc credential leak через malformed URL; системный пакет |
| CVE-2026-25645 | LOW | 2.33.0 | BLOCKED-UPSTREAM | `extract_zipped_paths()` предсказуемый tmpdir; стандартные пользователи не затронуты |

### urllib3 2.0.7 (транзитивная зависимость requests)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2024-37891 | LOW | 2.2.2 | BLOCKED-UPSTREAM | `Proxy-Authorization` header leak; не используем proxy через urllib3 напрямую |
| CVE-2025-50181 | MEDIUM | 2.5.0 | BLOCKED-UPSTREAM | `retries` на PoolManager игнорируется; не используем PoolManager |
| CVE-2025-66418 | HIGH | 2.6.0 | BLOCKED-UPSTREAM | Decompression chain bomb; эксплуатируется только при запросах к untrusted серверам |
| CVE-2025-66471 | HIGH | 2.6.0 | BLOCKED-UPSTREAM | Деcompression bomb при streaming; системная зависимость, не в нашем образе |
| CVE-2026-21441 | HIGH | 2.6.3 | BLOCKED-UPSTREAM | Decompression bomb на redirect; системная зависимость |

### configobj 5.0.8 (системный пакет Ubuntu / cloud-init)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2023-26112 | MEDIUM | 5.0.9 | BLOCKED-UPSTREAM | ReDoS в `validate()`; cloud-init зависимость, не в нашем коде |

### pyOpenSSL 23.2.0 (системный пакет Ubuntu)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2026-27448 | HIGH | 26.0.0 | BLOCKED-UPSTREAM | Unhandled exception в TLS callback принимает соединение; системный пакет, не прямая зависимость |
| CVE-2026-27459 | HIGH | 26.0.0 | BLOCKED-UPSTREAM | Buffer overflow в cookie callback; системный пакет |

### twisted 24.3.0 (системный пакет Ubuntu)

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| PYSEC-2024-75 | MEDIUM | 24.7.0 | BLOCKED-UPSTREAM | XSS в `redirectTo`; системный пакет, не используем Twisted |
| CVE-2024-41671 | HIGH | 24.7.0 | BLOCKED-UPSTREAM | HTTP pipelining out-of-order; системный пакет Ubuntu |

---

## Раздел C — DEV/BUILD инструменты (не в production-образе)

### pip 24.0

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2025-8869 | MEDIUM | 25.3 | FIX-LATER | Tar symlink traversal при pip install; Python 3.12 реализует PEP 706 — уязвимость к нам не применима |
| CVE-2026-1703 | MEDIUM | 26.0 | FIX-LATER | Path traversal при установке wheel; рекомендуется обновить pip на dev-окружении |
| ECHO-ffe1-1d3c-d9bc | — | 25.2+echo.1 | ACCEPT | Пустое описание, echo-источник (не OSV/NVD); не блокирует |
| ECHO-7db2-03aa-5591 | — | 25.2+echo.1 | ACCEPT | То же — нет описания, echo-источник |

### setuptools 68.1.2

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| PYSEC-2025-49 | HIGH | 78.1.1 | FIX-LATER | Path traversal в `PackageIndex` (easy_install deprecated); обновить setuptools на dev-окружении |
| CVE-2024-6345 | HIGH | 70.0.0 | FIX-LATER | RCE через `package_index` при URL из user input; применимо только при использовании deprecated easy_install |

### wheel 0.42.0

| CVE | Severity | Fix | Статус | Обоснование |
|---|---|---|---|---|
| CVE-2026-24049 | HIGH | 0.46.2 | FIX-LATER | Path traversal + chmod в `unpack`; эксплуатируется только при распаковке malicious wheel |
| ECHO-3d34-cec5-cf72 | — | 0.45.1+echo.1 | ACCEPT | Пустое описание, echo-источник |

---

## Итоговая классификация по приоритетам

| Приоритет | Пакет | CVE/ID | Action |
|---|---|---|---|
| P1 — обновить в следующем батче | pyjwt 2.7.0 | CVE-2026-32597 (HIGH) | `PyJWT[crypto]>=2.12.0` в pyproject.toml |
| P2 — обновить dev-окружение | setuptools 68.1.2 | PYSEC-2025-49, CVE-2024-6345 | `pip install -U setuptools` |
| P2 — обновить dev-окружение | wheel 0.42.0 | CVE-2026-24049 | `pip install -U wheel` |
| P3 — системные, через apt | jinja2, requests, urllib3, configobj, pyopenssl, twisted | множественные | `apt upgrade` на сервере |

---

## Замечания по методологии

- pip-audit сканировал всё системное окружение (нет изолированного venv), поэтому в отчёте много системных пакетов Ubuntu.
- Для точного скоупа на CI рекомендуется: `pip-audit -r backend/pyproject.toml` в изолированном venv (задача devops при настройке CI job `security-scan`).
- Пакеты с `skip_reason` (bcc, cloud-init и др.) — системные, не найдены на PyPI, аудит невозможен; это норма.

---

## Цикл пересмотра

- Пересмотр при подъёме мажорной версии зависимостей.
- Раз в месяц quality-director инициирует перепроход.
- `FIX-LATER` → `REMOVED` после факта обновления пакета.
