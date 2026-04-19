# Mine 3 — SendMessage к dormant design-director

**Тестируемый хук:** H-3 (Claude Code PostToolUse on SendMessage, warning-уровень)

**Что симулируем:** Координатор вызывает `SendMessage(to="design-director", body="...")`, когда design-director **не** присутствует в `/root/.claude/teams/default/active-agents.json` (dormant).

**Ожидаемая реакция:**
- SendMessage выполняется (не блокируется — по §H-3 плана это warning-уровень).
- В stderr Координатора появляется substring `HOOK H-3`, `dormant`, `inbox`.
- Упоминается subagent_type = `design-director`.

**Критические требования к фикстуре:**
1. H-3 — Claude Code hook (PostToolUse), а не git hook. Воспроизвести «вне Claude» нельзя.
2. Для isolation подзадачи Г: хук устанавливается через `CLAUDE_HOOKS_DIR=/tmp/claude-hooks-pilot` (см. §5.3 брифа). Если backend-dev не поддержал эту опцию — откат глобальных хуков обязателен после теста.
3. Реестр `active-agents.json` должен быть пустым (design-director dormant), либо явно не содержать design-director. Используем fixture-файл `active-agents-empty.json` и подставляем его в путь, который H-3 читает.

**Сценарий воспроизведения (reproduce.md — не shell, это нужно прогнать внутри Claude-сессии):**

1. Подготовка:
   - Убедиться, что `~/.claude/hooks/pre-send-message.py` (или его аналог PostToolUse) установлен.
   - Скопировать `active-agents-empty.json` → `/root/.claude/teams/default/active-agents.json`.
   - Убедиться, что ни один background-агент не запущен (в т.ч. `design-director`).
2. Прогон (в Claude-сессии, не в bash):
   - Вызвать `SendMessage(to="design-director", body="mine 3 test")`.
   - Наблюдать stderr / уведомления Claude.
3. Вердикт:
   - PASS: substring `H-3` найден, упоминается `design-director`, сообщение оставлено в inbox (файл `/root/.claude/teams/default/inboxes/design-director.json` обновился).
   - PARTIAL: substring найден, но текст неинформативен (нет упоминания dormant).
   - FAIL: хук не сработал вообще.

**Артефакты:**
- `active-agents-empty.json` — пустой реестр (design-director отсутствует).
- `reproduce.md` — пошаговая инструкция для прогона в Claude-сессии (подзадача Г).

**Примечание для подзадачи Г:**
- Так как H-3 — событийный Claude Code hook, его тестирование **вне Claude-сессии невозможно**. Аналитик при прогоне должен быть внутри Claude CLI, делать вызов руками, фиксировать stderr.
