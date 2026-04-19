# Mine 3 — Reproduce (manual, в Claude-сессии)

H-3 — Claude Code PostToolUse hook, его нельзя вызвать из bash. Сценарий прогоняется внутри Claude CLI.

## Пошагово

1. **Изоляция глобального состояния (по §5.3 брифа):**
   ```bash
   export CLAUDE_HOOKS_DIR=/tmp/claude-hooks-pilot
   mkdir -p $CLAUDE_HOOKS_DIR
   cp /root/.claude/hooks/pre-send-message.py $CLAUDE_HOOKS_DIR/  # если backend-dev поддержал опцию
   cp /root/.claude/hooks/subagent-lifecycle.py $CLAUDE_HOOKS_DIR/  # или аналог
   ```
   Если `CLAUDE_HOOKS_DIR` не поддержан — сделать backup глобальных хуков:
   ```bash
   cp -r /root/.claude/hooks /root/.claude/hooks.backup-$(date +%Y%m%d-%H%M%S)
   ```

2. **Подготовить пустой реестр активных агентов:**
   ```bash
   cp /root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/mine-3-sendmessage-dormant/active-agents-empty.json \
      /root/.claude/teams/default/active-agents.json
   ```

3. **В Claude-сессии внутри worktree:**
   ```
   SendMessage(to="design-director", body="mine 3 test — expected warning H-3")
   ```

4. **Зафиксировать stderr / уведомление Claude:**
   - Скопировать вывод полностью.
   - Проверить наличие substring: `H-3`, `design-director`, `dormant` (или синоним «неактивен», «inbox»).

5. **Проверить inbox:**
   ```bash
   cat /root/.claude/teams/default/inboxes/design-director.json | tail -20
   ```
   Убедиться, что последнее сообщение содержит body = `mine 3 test — expected warning H-3`. Это подтверждает: хук warning-уровня, не блокирует, SendMessage доставляется в inbox.

6. **Откат глобальных хуков (обязательно по §5.3):**
   ```bash
   # если использовали CLAUDE_HOOKS_DIR — просто unset
   unset CLAUDE_HOOKS_DIR
   # иначе восстановить из backup
   rm -rf /root/.claude/hooks
   mv /root/.claude/hooks.backup-* /root/.claude/hooks
   ```

## Вердикт

| Результат | Substring H-3 | Упоминание design-director | Inbox обновился |
|-----------|----------------|----------------------------|-----------------|
| PASS      | да             | да                         | да              |
| PARTIAL   | да             | нет                        | да              |
| FAIL      | нет            | —                          | —               |

Записать в отчёт §3.2.
