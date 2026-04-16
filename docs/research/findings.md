# R&I Findings (журнал находок)

Ведёт `ri-scout`. Append-only: новые строки снизу. Дубли за последние 30 дней не добавлять.

| Дата | Источник | Ссылка | Одной строкой что это | Теги | Кому адресовать | Статус |
|---|---|---|---|---|---|---|
| 2026-04-14 | Anthropic release | https://platform.claude.com/docs/en/release-notes/claude-code | Claude Code Routines — автономный запуск Claude Code в облаке по cron / API / GitHub-webhook, 15 запусков/день | claude-code, automation, ci | coordinator, quality-director | Analysis |
| 2026-04-13 | GitHub Trending | https://github.com/thedotmack/claude-mem | claude-mem — внешняя память для Claude Code со сжатием, обход лимита 200K контекста | claude-code, memory, context | governance-director | Discovered |
| 2026-04-12 | GitHub Trending | https://github.com/VoltAgent/awesome-claude-code-subagents | Коллекция 100+ готовых субагентов Claude Code под типовые dev-задачи | claude-code, subagents | ri-director | Discovered |
| 2026-04-10 | awesome-claude-code | https://github.com/lis186/ccxray | ccxray — прозрачный HTTP-прокси между Claude Code и Anthropic API с real-time дашбордом (аудит, метрики) | observability, audit | quality-director, security | Discovered |
| 2026-04-08 | awesome-claude-code | https://aipatternbook.com | Encyclopedia of Agentic Coding Patterns — справочник 190+ паттернов AI-разработки | reference, patterns | ri-analyst | Discovered |
| 2026-04-14 | GitHub Trending | https://github.com/NousResearch/hermes-agent | Hermes-agent — «растущий» персональный агент с долговременной памятью, +7454 звезды за неделю | ai-agents, memory | ri-director | Discovered |
| 2026-04-16 | GitHub Trending | https://github.com/obra/superpowers | Superpowers — skills-плагин Claude Code с готовым workflow (TDD, systematic debugging, worktree, code review), устанавливается через `/plugin install superpowers@claude-plugins-official`, 155k звёзд (+2055/день) | claude-code, skills, workflow, tdd | quality-director, backend-director | Discovered |
| 2026-04-16 | GitHub Trending | https://github.com/forrestchang/andrej-karpathy-skills | CLAUDE.md по Карпати — 4 принципа против типовых ошибок LLM-кодера: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution; 46k звёзд (+9646/день) | claude-code, prompting, guidelines | governance-director, ri-director | Discovered |
| 2026-04-14 | Simon Willison's Weblog | https://simonwillison.net/2026/Apr/14/datasette-csrf/ | Кейс: Claude Code в 10 коммитах заменил CSRF-токены datasette на header-based защиту (PR #2689) — живой референс security-refactor агентом в OSS | claude-code, security, case-study | architect, security | Discovered |

