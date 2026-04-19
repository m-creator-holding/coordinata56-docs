# Hooks Phase 0 — Test Fixtures

Назначение: воспроизводимый тестовый стенд для приёмки 5 хуков (H-1…H-5) по плану `rfc-004-hooks-phase-0-plan.md` и брифу `rfc-004-hooks-pilot-analyst-brief.md`.

## Содержимое

- `mine-1-env-secret/` — .env с литералом JWT secret (ожидание: H-1 block).
- `mine-2-git-add-all/` — симуляция `git add -A` с 15 файлами от разных mtime (ожидание: H-2 warn+confirm).
- `mine-3-sendmessage-dormant/` — SendMessage к dormant design-director (ожидание: H-3 warn).
- `mine-4-agent-no-ultrathink/` — Agent к Opus без ultrathink (ожидание: H-4 warn).
- `mine-5-ruff-unused-import/` — staged Python с unused import (ожидание: H-5 block).
- `clean-scenarios.md` — 20 легитимных сценариев (false-positive guard).
- `measure-overhead.sh` — скрипт замера оверхеда коммита.
- `run-all-mines.sh` — прогон всех 5 мин последовательно (подзадача Г).

## Правила безопасности фикстур

1. Все литералы секретов снабжены префиксом `FAKE_KEY_`, однако паттерны хука H-1 должны ловить их всё равно (проверяется в подзадаче Г по факту готовности regex backend-dev).
2. Для коммита самих фикстур в репозиторий (если когда-то потребуется) используем маркер `# hook-exception: H-1 test fixture` в комментарии рядом с литералом. Если H-1 не поддерживает маркер — это P0-замечание backend-dev.
3. Все Python-файлы мин — имя с префиксом `_mine_` (исключены из pytest collection через существующий `conftest.py`, не попадают в прод-тесты).
4. Стенд **не коммитится** в основную ветку до adopt. Работа в `/root/worktrees/coordinata56-hooks-pilot/`.

## Соответствие §4 плана и §2 брифа

| № мины | Хук | Тип реакции | Критерий «поймано» |
|--------|-----|-------------|---------------------|
| 1 | H-1 | block | exit code != 0 |
| 2 | H-2 | warn+confirm | substring "H-2" в stderr |
| 3 | H-3 | warn | substring "H-3" в stderr |
| 4 | H-4 | warn | substring "H-4" в stderr |
| 5 | H-5 | block | exit code != 0 |

Mandatory: **H-1 должна блокировать**. Осечка H-1 — P0 reject, независимо от остальных 4 мин.
