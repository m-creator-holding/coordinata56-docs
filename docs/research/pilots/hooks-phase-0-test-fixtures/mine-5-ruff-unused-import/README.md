# Mine 5 — unused import в staged Python-файле

**Тестируемый хук:** H-5 (pre-commit ruff + pytest)

**Что симулируем:** разработчик делает правку в `backend/app/services/project.py` (реальный файл с существующим test mapping — см. §5.6 брифа), добавляет `import os` который не используется, стейджит и коммитит.

**Ожидаемая реакция:**
- `git commit` падает с exit code 1.
- stderr содержит substring `ruff` и код правила `F401` (unused import).
- Упоминается файл `backend/app/services/project.py`.
- (Опционально) после блокировки ruff — H-5 **не должен** запускать pytest, так как ruff уже провалил.

**Критические требования к фикстуре (из §5.6 брифа):**
1. Файл для правки — **существующий** `backend/app/services/project.py`. Mapping на `backend/tests/test_projects.py` существует — значит H-5 НЕ запустит полный pytest по всем `backend/tests/` (ограничен mapping-правилом).
2. Патч — минимальный: одна лишняя строка `import os` в начале файла.
3. После прогона — patch отменяется (git checkout).

**Артефакты:**
- `unused-import.patch` — diff для применения к `backend/app/services/project.py`.
- `reproduce.sh` — применяет patch, стейджит, пытается коммит, восстанавливает исходный файл.

**Успех:**
- exit code != 0
- substring `ruff` или `F401` в stderr
- путь файла упомянут

**Важно для оверхеда:** H-5 с pytest на изменённом `project.py` должен запустить только `test_projects.py` (и, возможно, API-тесты `test_projects_api`, если есть mapping). Это укладывается в бюджет ≤2с? — проверяется в measure-overhead.sh; если не укладывается — fallback «только ruff», как предусмотрено §4.3 плана.
