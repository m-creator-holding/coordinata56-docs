# Mine 4 — Sample prompts (без ultrathink)

Используются в ручном прогоне (reproduce в Claude-сессии).

## Вариант A — backend-director (Opus)

```
Agent(
  subagent_type="backend-director",
  description="mine-4-a",
  prompt="Проверь, нужно ли переименовать файл backend/app/api/projects.py в projects_router.py."
)
```

**Ожидание H-4:** warning, substring "backend-director", substring "ultrathink".

## Вариант B — governance-director (Opus)

```
Agent(
  subagent_type="governance-director",
  description="mine-4-b",
  prompt="Какой статус у ADR 0012?"
)
```

**Ожидание H-4:** warning.

## Вариант C — ri-analyst (Opus, self-call симулируется в отчёте)

```
Agent(
  subagent_type="ri-analyst",
  description="mine-4-c",
  prompt="Оцени RFC-008."
)
```

**Ожидание H-4:** warning. Note: в прогоне пилота не вызываем себя рекурсивно — проверяем через лог hook'а или аналогично вариантам A-B.

## Контрольный (Sonnet — clean-сценарий, для clean-scenarios.md)

```
Agent(
  subagent_type="ri-scout",
  description="clean-check-sonnet",
  prompt="Short task without thinking needed."
)
```

**Ожидание H-4:** молчит (Sonnet не требует ultrathink по CLAUDE.md).

## Контрольный (Opus с ultrathink — clean-сценарий)

```
Agent(
  subagent_type="backend-director",
  description="clean-check-opus-with-thinking",
  prompt="ultrathink — review PR#42."
)
```

**Ожидание H-4:** молчит (ключевое слово найдено).
