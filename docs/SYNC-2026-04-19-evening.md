# Снимок состояния: синхронизация зеркала docs 2026-04-19 (вечер)

**Дата:** 2026-04-19  
**Предыдущий снимок:** 2026-04-16  
**Версия:** v0.5.1  
**Репозиторий-источник:** `/root/coordinata56/`  
**Назначение:** публичное зеркало `github.com/m-creator-holding/coordinata56-docs`

---

## Что добавлено с 2026-04-16

### ADR (архитектурные решения)

| Файл | Содержание |
|---|---|
| `docs/adr/0019-pluggability-contract.md` | Контракт подключаемых модулей |
| `docs/adr/0020-form-report-json-descriptors.md` | JSON-дескрипторы форм и отчётов |
| `docs/adr/0021-pod-isolation-patterns.md` | Паттерны изоляции pod'ов |
| `docs/adr/0022-analytics-reporting-data-model.md` | Модель данных аналитики |
| `docs/adr/0023-rule-snapshots-pattern.md` | Паттерн снимков бизнес-правил |
| `docs/adr/0024-verification-gate-live-activations.md` | Трёхшаговый DoD для live-активаций |
| `docs/adr/drafts/ADR-0025-1c-integration-draft.md` | Черновик интеграции с 1С через ACL |

### Sprint 2 Volna A — Event Bus и интеграционный слой (US-04–07)

- **US-04 BusinessEventBus** — шина деловых событий между модулями
- **US-05 AgentControlBus** — шина управления ИИ-субагентами
- **US-06 ACL IntegrationAdapter** — Anti-Corruption Layer для внешних форматов
- **US-07 Pluggability container** — реестр подключаемых модулей

### Sprint 2 Volna B (запланировано)

- **US-08 OutboxPoller** — надёжная доставка событий через Outbox-паттерн
- **US-09 1С refactor** — рефакторинг адаптера 1С
- **US-10 Retention + anonymize** — политика хранения и анонимизации ПД

### Wave 11 — закрытие регрессии (Round 3 + Round 4)

- Исправлено 4 критических бага: авторизация RBAC v2, фильтрация SQL, миграция US-01, IDOR-уязвимость
- WAL-архив включён в Yandex Object Storage (`archive_mode=on`)
- SQL-дамп расширен с 14 до 30 дней хранения
- Пароли в тестах заменены на `secrets.token_urlsafe(16)`

### Operations UI — вайрфреймы

3 экрана операционного раздела + 3 экрана Sprint 3:
- Дашборд сводных показателей
- Реестр домов с фильтрацией
- Экран план/факт отчётности

### M-OS-2 планирование

- Voice brief: концепция голосового журнала прораба
- Innovation digest: приоритеты M-OS-2
- Benchmarks: сравнение подходов к голосовому вводу

### Безопасность

- Утилита `mask_email` — маскирование email в логах и аудите
- OWASP-отчёт по Wave 11
- Frontend security review

### Прочее

- `CHANGELOG.md` обновлён до v0.5.1
- `README.md` обновлён до v0.5.1
- `status.md` актуализирован
- Governance: ретро Wave 11, legal-отчёт, migration audit
- `RETENTION_POLICY_TBD.md` — заглушка политики хранения данных

---

## Папки, синхронизированные в это зеркало

```
docs/adr/
docs/governance/
docs/integrations/
docs/knowledge/
docs/legal/
docs/pods/
docs/qa/
docs/reviews/
docs/security/
docs/research/
CHANGELOG.md
README.md
```

**Не включено (по политике зеркала):**
- `docs/agents/` — внутренние инструкции субагентов
- `backend/`, `frontend/` — исходный код
- `.env*`, секреты, конфигурация среды

---

*Подготовлено: технический писатель coordinata56, 2026-04-19*
