# Внешние справочники R&I

Внешние источники, внедрённые как reference (без установки в наш стек).

## Каталоги субагентов

- **awesome-claude-code-subagents** (MIT, 130+ субагентов) — клонирован в `docs/research/external/awesome-claude-code-subagents/`. Использовать при активации новых направлений и дообогащении существующих должностных. https://github.com/VoltAgent/awesome-claude-code-subagents

## Справочники паттернов

- **Encyclopedia of Agentic Coding Patterns** — 190+ паттернов разработки AI-агентов. https://aipatternbook.com — читает ri-analyst раз в 2 недели, релевантное выписывает в `departments/research.md` §«Паттерны».

## Наблюдаемость (к рассмотрению для пилота)

- **ccxray** — `ccxray@1.5.0` на npm, MIT. HTTP-прокси между Claude Code и Anthropic API с дашбордом (Timeline, cost, system-prompt tracking). https://github.com/lis186/ccxray — пилот в следующей большой сессии через `npx ccxray claude`.

## Отклонённые

- **hermes-agent** (NousResearch) — самостоятельная платформа, конкурент Claude Code. Не внедряем при выбранном стеке. https://github.com/NousResearch/hermes-agent

## Под вопросом (deferred)

- **claude-mem** (AGPL-3.0) — внешняя сжатая память для Claude Code. Дублирует нашу memory-систему; AGPL требует юридической проверки при серверном развёртывании. https://github.com/thedotmack/claude-mem

---

**Владеет:** ri-director
**Обновление:** по решению ri-director по итогам weekly digest.
