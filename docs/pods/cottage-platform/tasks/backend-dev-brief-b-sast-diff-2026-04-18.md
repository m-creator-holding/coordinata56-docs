# Дев-бриф: B-SAST-DIFF — скрипт `tools/diff-bandit-baseline.py`

- **Дата:** 2026-04-18
- **Автор:** backend-director (через backend-head)
- **Получатель:** backend-dev (один из 1/2/3 по загрузке — выбирает backend-head)
- **Приоритет:** P1 — блокер CI-job `security-scan` из `devops-brief-q1-sast-ci-v2-2026-04-18.md` §4
- **Оценка:** ≤ 2 часа (простая stdlib-утилита, ≤ 100 строк)
- **Параллельность:** может идти параллельно с `backend-dev-brief-pyjwt-bump-2026-04-18.md` — файлы не пересекаются
- **Scope-vs-ADR:** verified (ADR 0004/0005/0006/0007/0011/0013 не затрагиваются — это CI-утилита вне `backend/app`, не бизнес-код, не миграция, не API); gaps: none
- **Источник формулировки:** infra-director, `docs/pods/cottage-platform/tasks/devops-brief-q1-sast-ci-v2-2026-04-18.md` §4

---

## Контекст

qa-head зафиксировал Bandit baseline (`docs/reviews/bandit-baseline-2026-04-18.md`) — 2 LOW findings (B106 в `api/auth.py:167`, B110 в `repositories/stage.py:65`), оба ACCEPT, HIGH = 0.

devops добавляет в CI job `security-scan` (Q-1), который запускает bandit и должен падать только на **новых HIGH** — тех, которых нет в baseline. Стандартный bandit такого API не имеет (он падает на любом finding). Нужен мост — скрипт, который читает свежий bandit JSON, читает baseline markdown, сравнивает и решает про exit-code.

**Без этого скрипта CI-job зелёным не станет** — infra-director явно указал зависимость. Задача B-SAST-DIFF в main должна зайти **до** Q-1 YAML.

---

## Что конкретно сделать

### 1. Создать файл `/root/coordinata56/tools/diff-bandit-baseline.py`

Размещение — **корень репозитория**, `tools/`, **не** `backend/tools/`. Обоснование: это CI-утилита (читает файлы из `docs/` и `/tmp/`), а не backend-приложение. `backend/tools/` зарезервирован под код, импортируемый в приложение (lint_migrations и т.п.).

Если каталога `tools/` в корне нет — создать.

### 2. CLI-контракт

```
python tools/diff-bandit-baseline.py \
    --bandit-json /tmp/bandit.json \
    --baseline docs/reviews/bandit-baseline-2026-04-18.md
```

**Флаги через `argparse`:**

| Флаг | Тип | Обязательный | Описание |
|---|---|---|---|
| `--bandit-json` | `pathlib.Path` | да | путь к свежему bandit JSON (output `bandit -f json -o`) |
| `--baseline` | `pathlib.Path` | да | путь к baseline markdown |

Позиционных аргументов не вводить — в CI YAML уже заложены флаги (см. `devops-brief-q1-sast-ci-v2` §3, шаг `Diff Bandit against baseline`). **Важно:** infra-брифинг-v2 использовал **позиционные** аргументы (`python tools/diff-bandit-baseline.py /tmp/bandit.json docs/...`). Координатор согласовал флаговый вариант — он явнее и покрывается `argparse --help`. devops-head при стыковке CI обновит YAML на флаги. Это уже отмечено в постановке Координатора.

### 3. Формат входного bandit JSON

Структура, на которую опираться (факт, проверено по `bandit 1.9.4 -f json`):

```json
{
  "results": [
    {
      "filename": "backend/app/api/auth.py",
      "line_number": 167,
      "test_id": "B106",
      "issue_severity": "LOW",      // "LOW" | "MEDIUM" | "HIGH"
      "issue_confidence": "MEDIUM",
      "issue_text": "Possible hardcoded password: 'bearer'",
      "code": "..."
    }
  ],
  "metrics": { ... },
  "errors": []
}
```

Нужные поля: `filename`, `line_number`, `test_id`, `issue_severity`, `issue_text`. Остальное — игнорировать.

**Нормализация `filename`:** bandit может вернуть путь как абсолютный (`/home/runner/work/coordinata56/coordinata56/backend/app/api/auth.py`) или относительный (`backend/app/api/auth.py`). Baseline записан в относительной форме (`backend/app/api/auth.py`). Перед сравнением — приводить filename из JSON к хвосту, начинающемуся с `backend/` (`re.search(r"(backend/.+)$", filename)`) или просто брать последние компоненты через `pathlib.PurePosixPath.parts`. Если матч не нашёлся — оставить как есть и логировать warning в stderr (не падать).

### 4. Формат baseline markdown

Фрагмент «Таблица findings» (воспроизведён из `docs/reviews/bandit-baseline-2026-04-18.md`):

```markdown
## Таблица findings

| # | Файл:строка | Правило | Severity | Confidence | Статус | Обоснование |
|---|---|---|---|---|---|---|
| 1 | `backend/app/api/auth.py:167` | B106 `hardcoded_password_funcarg` | LOW | MEDIUM | ACCEPT | `token_type="bearer"` ... |
| 2 | `backend/app/repositories/stage.py:65` | B110 `try_except_pass` | LOW | HIGH | ACCEPT | Явный `# noqa: BLE001` ... |
```

**Алгоритм парсинга:**

1. Найти в файле заголовок `## Таблица findings` (любая markdown-таблица с этим заголовком — это наша).
2. После разделителя `|---|---|...` читать строки таблицы до первой пустой строки или нового `##`.
3. Для каждой строки таблицы:
   - Извлечь колонку **«Файл:строка»** → из неё распарсить `(filename, line_number)` (regex: `` `(.+?):(\d+)` ``).
   - Извлечь колонку **«Правило»** → из неё взять `test_id` (regex: `\bB\d{3}\b` — первая группа цифрой).
   - Извлечь колонку **«Статус»** → значение (`ACCEPT` / `FIX-LATER` / `BLOCKED-UPSTREAM`). Для текущего сравнения **статус не меняет логику** (любой finding в baseline, независимо от статуса, считается «известным») — но поле прочитать и сложить в структуру, пригодится в warning-выводе.
4. Собрать `baseline: set[tuple[str, int, str]]` — ключ `(filename, line_number, test_id)`.

**Если таблица не найдена** (нет заголовка или нет ни одной строки) — `sys.exit(2)` с сообщением в stderr «baseline table not found in <path>». Exit-code 2 (не 1) чтобы CI отличил ошибку самого скрипта от бизнес-провала diff.

### 5. Логика сравнения

```
new_findings = results из bandit JSON
known = set(baseline keys)

new_high = [r for r in new_findings
            if r.issue_severity == "HIGH"
               and (r.filename_normalized, r.line_number, r.test_id) not in known]

new_low_med = [r for r in new_findings
               if r.issue_severity in ("LOW", "MEDIUM")
                  and (r.filename_normalized, r.line_number, r.test_id) not in known]

# Печать
for r in new_low_med:
    print(f"WARN {r.test_id}: {r.filename}:{r.line_number}: {r.issue_text}", file=sys.stdout)

for r in new_high:
    print(f"NEW HIGH {r.test_id}: {r.filename}:{r.line_number}: {r.issue_text}", file=sys.stderr)

if new_high:
    sys.exit(1)
print(f"ok: {len(results)} findings total, {len(new_low_med)} new low/med (warning-only), 0 new high", file=sys.stdout)
sys.exit(0)
```

**Exit-codes:**
- `0` — нет новых HIGH. LOW/MEDIUM могут быть — они не блокируют, только WARNING в stdout.
- `1` — ≥ 1 новый HIGH. Каждый — отдельной строкой в stderr, формат `{test_id}: {file}:{line}: {issue_text}`.
- `2` — ошибка самого скрипта (не нашли таблицу, не удалось открыть файл, JSON невалидный).

### 6. Структура файла

```python
"""diff-bandit-baseline.py — сравнивает bandit JSON со списком findings в baseline markdown.

Exit-codes:
  0 — нет новых HIGH; LOW/MEDIUM могут быть (warning-only в stdout).
  1 — найден ≥1 новый HIGH (в stderr — по строке на finding).
  2 — ошибка самого скрипта (таблица не найдена, JSON битый и т.п.).

Зависимости: только stdlib (json, argparse, pathlib, re, sys).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def parse_baseline(path: Path) -> set[tuple[str, int, str]]: ...

def normalize_filename(raw: str) -> str: ...

def main() -> int: ...


if __name__ == "__main__":
    sys.exit(main())
```

Не вводить глобальные переменные, не вводить классы (dataclass допустим для читаемости, но не обязателен). Функция `main()` возвращает int → `sys.exit(main())`.

### 7. Самопроверка (перед сдачей backend-head)

Ручные прогоны — записать вывод в отчёт:

```bash
# Ok-кейс: JSON с одним LOW finding, совпадающим с baseline
python tools/diff-bandit-baseline.py \
    --bandit-json tests-tmp/bandit-ok.json \
    --baseline docs/reviews/bandit-baseline-2026-04-18.md
# ожидание: exit 0, stdout "ok: ..."

# Fail-кейс: JSON с одним HIGH (новый)
python tools/diff-bandit-baseline.py \
    --bandit-json tests-tmp/bandit-new-high.json \
    --baseline docs/reviews/bandit-baseline-2026-04-18.md
# ожидание: exit 1, stderr "NEW HIGH B602: ..."

# Warn-кейс: JSON с новым LOW
python tools/diff-bandit-baseline.py \
    --bandit-json tests-tmp/bandit-new-low.json \
    --baseline docs/reviews/bandit-baseline-2026-04-18.md
# ожидание: exit 0, stdout содержит "WARN ..."
```

JSON-фикстуры собрать руками (≤ 20 строк каждая) во временной папке `tests-tmp/` в корне; **эту папку не коммитить** — добавить в `.gitignore`, если не добавлена, либо просто не делать `git add`. Фикстуры нужны только для ручной проверки; полноценные pytest-тесты — следующим раундом через qa.

---

## Критерии приёмки (DoD)

- [ ] Файл `tools/diff-bandit-baseline.py` создан, ≤ 100 строк (включая docstring и пустые).
- [ ] Stdlib only: в файле нет `import` ничего, кроме `json`, `argparse`, `pathlib`, `re`, `sys` (и `from __future__ import annotations`).
- [ ] CLI: `--bandit-json PATH` и `--baseline PATH`, оба обязательные, парсятся через `argparse`.
- [ ] `python tools/diff-bandit-baseline.py --help` — человекочитаемый help.
- [ ] Три ручных прогона из §7 — exit-codes и вывод соответствуют ожиданиям; вывод приложить в отчёт.
- [ ] `ruff check tools/diff-bandit-baseline.py` — 0 ошибок.
- [ ] Нет `# type: ignore` / `# noqa` без обоснования (CLAUDE.md «Код»).
- [ ] Не коммитить — коммитит Координатор.

---

## FILES_ALLOWED

- `tools/diff-bandit-baseline.py` — **создать**
- *(опционально, если его ещё нет в репозитории)* `tools/.gitkeep` — чтобы каталог трекался

## FILES_FORBIDDEN

- любые файлы в `backend/` — это **не backend-код** и никак не должно туда влезать
- `.github/workflows/**` — YAML правит devops-dev отдельной задачей
- `docs/**` — baseline не меняется; если нашли в нём неточность — стоп, эскалация backend-head → backend-director → qa-director, не править
- `frontend/**`, `scripts/**`, `alembic/**`
- `tests-tmp/**` — локальные фикстуры не коммитить

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `/root/coordinata56/CLAUDE.md` (секции «Код», «Секреты и тесты») и `/root/coordinata56/docs/agents/departments/backend.md` (чек-лист ADR-gate A.1–A.5 — применимы частично; A.2–A.5 к CI-утилите не применимы, но A.1 «литералы секретов» — да: никаких токенов/паролей в тестовых фикстурах).
- Если обнаружено, что baseline markdown имеет формат, отличный от §4 (например, переименована колонка, или таблица разбита на две) — **стоп, эскалация backend-head**. Не пытаться «угадать» парсер.
- Если bandit JSON не содержит ожидаемых полей (`results[].filename` и т.п.) — логировать в stderr и `sys.exit(2)`, **не падать с traceback**.
- Никаких сторонних зависимостей (нет `pip install`, нет `requirements.txt`). Если возникла потребность в стороннем парсере — стоп, эскалация: это меняет CI-контракт.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Код», «Секреты и тесты»
2. `/root/coordinata56/docs/agents/departments/backend.md` — общие правила и чек-лист
3. `/root/coordinata56/docs/reviews/bandit-baseline-2026-04-18.md` — **полностью** (формат таблицы, обоснование findings)
4. `/root/coordinata56/docs/pods/cottage-platform/tasks/devops-brief-q1-sast-ci-v2-2026-04-18.md` — §3 (YAML) и §4 (формулировка B-SAST-DIFF) — чтобы понимать, как скрипт будет вызываться из CI
5. Один пример bandit JSON — собрать локально командой `cd backend && bandit -r app tools alembic -f json -o /tmp/bandit-sample.json` (prompt: пакет bandit должен быть установлен; если нет — `pip install "bandit[toml]>=1.7.9"`)

---

## Блокеры — эскалировать backend-head

- Формат baseline markdown оказался сложнее ожидаемого (многострочные ячейки, HTML, вложенные списки) → стоп.
- bandit JSON 1.9.4 содержит поля с другими именами/типами, чем в §3 → стоп, возможно нужен bump версии bandit (но это CI-контракт).
- Возникла нужда в стороннем пакете (`tomli`, `pyyaml`, `tabulate`) → стоп.
- Размер скрипта превысил 150 строк → стоп: либо упрощение логики, либо эскалация о пересмотре требований.

---

## Отчёт (≤ 200 слов)

Структура:
1. **Файл** — путь, число строк, основные функции.
2. **CLI** — вывод `python tools/diff-bandit-baseline.py --help`.
3. **Ручные прогоны** — три кейса из §7 с exit-codes и ключевыми строками вывода.
4. **ruff** — статус.
5. **Отклонения от scope** — если были (не должно).
