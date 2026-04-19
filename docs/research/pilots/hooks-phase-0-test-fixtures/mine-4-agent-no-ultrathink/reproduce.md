# Mine 4 — Reproduce (manual, в Claude-сессии)

H-4 — Claude Code PreToolUse hook на Agent. Воспроизводится только из Claude CLI.

## Пошагово

1. **Изоляция глобальных хуков (§5.3 брифа):**
   ```bash
   export CLAUDE_HOOKS_DIR=/tmp/claude-hooks-pilot
   # либо backup глобальных, см. mine-3/reproduce.md
   ```

2. **Убедиться, что справочник `docs/agents/opus-agents.yaml` установлен в worktree:**
   ```bash
   test -f /root/worktrees/coordinata56-hooks-pilot/docs/agents/opus-agents.yaml || echo "MISSING — backend-dev deliverable"
   ```
   Если отсутствует — остановиться, эскалация к backend-dev через Координатора.

3. **В Claude-сессии внутри worktree — вариант A (см. sample-prompts.md):**
   ```
   Agent(subagent_type="backend-director",
         description="mine-4-a",
         prompt="Проверь, нужно ли переименовать файл backend/app/api/projects.py в projects_router.py.")
   ```

4. **Зафиксировать stderr до/после вызова:**
   - substring `H-4` присутствует? (PASS если да)
   - упоминание `backend-director`? (confirms identification)
   - упоминание `ultrathink`? (confirms rule message)

5. **Повторить для варианта B (governance-director).** 1 вызова достаточно (§5.8 брифа — бинарный результат).

6. **Откат глобальных хуков** (см. mine-3/reproduce.md §6).

## Вердикт

| Результат | H-4 substring | subagent_type в тексте | ultrathink в тексте |
|-----------|---------------|-------------------------|----------------------|
| PASS      | да            | да                      | да                   |
| PARTIAL   | да            | да/нет                  | нет                  |
| FAIL      | нет           | —                       | —                    |

Записать в отчёт §3.2.
