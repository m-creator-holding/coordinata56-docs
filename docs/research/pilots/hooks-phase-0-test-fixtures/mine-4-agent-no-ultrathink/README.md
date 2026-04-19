# Mine 4 — Agent к Opus-субагенту без ultrathink

**Тестируемый хук:** H-4 (Claude Code PreToolUse on Agent, warning-уровень)

**Что симулируем:** Координатор вызывает `Agent(subagent_type="backend-director", prompt="...")` где prompt **не содержит** ключевых слов `ultrathink`, `think harder`, `think hard`. backend-director — Opus-агент (присутствует в справочнике `docs/agents/opus-agents.yaml`).

**Ожидаемая реакция:**
- Agent-вызов выполняется (H-4 — warning-уровень, не block).
- В stderr substring `HOOK H-4` или `WARNING H-4`, упоминание `ultrathink`.
- Упоминание subagent_type (`backend-director`).

**Критические требования к фикстуре:**
1. Справочник `docs/agents/opus-agents.yaml` готовит backend-dev. Без справочника H-4 не работает. Если фикстура запускается до появления справочника — это P0 к backend-dev, не к фикстуре.
2. Opus-агенты по CLAUDE.md 2026-04-18: backend-director, frontend-director, governance-director, governance-auditor, infra-director, innovation-analyst, innovation-director, quality-director, review-head, ri-analyst, ri-director.
3. Для проверки «Sonnet → no warn» (clean scenario) использовать: ri-scout, quality-worker, любой worker/head — они Sonnet.

**Сценарий (reproduce.md — manual):**

1. Изоляция глобальных хуков (`CLAUDE_HOOKS_DIR` или backup) — по §5.3 брифа.
2. В Claude-сессии:
   ```
   Agent(subagent_type="backend-director",
         prompt="review PR#42 — simple question about naming",
         description="mine 4 test")
   ```
   Prompt заведомо без `ultrathink` / `think harder` / `think hard`.
3. Зафиксировать stderr, проверить substring.

**Вторичные кейсы (для покрытия):**
- `Agent(subagent_type="governance-director", prompt="…")` без thinking — H-4 должен сработать.
- `Agent(subagent_type="ri-analyst", prompt="…")` без thinking — H-4 должен сработать (это я сам, симулировать через вложенный вызов не нужно, только описать в отчёте).

**Артефакты:**
- `sample-prompts.md` — 3 варианта промптов без ultrathink для ручного прогона.

**Успех = substring H-4 в stderr + упоминание subagent_type. Warning, не block.**
