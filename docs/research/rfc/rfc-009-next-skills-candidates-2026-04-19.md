---
id: RFC-2026-009
title: Next skill candidates after 5 adopted — top-2 на proof-of-concept
status: draft
date: 2026-04-19
author: ri-director (draft, PoC brief for ri-analyst)
reviewers:
  - coordinator (approve PoC scope)
  - governance-director (скрининг на пересечение с CODE_OF_LAWS)
  - quality-director (после PoC — решение на включение в workflow)
related:
  - docs/research/briefs/claude-md-skill-candidates-2026-04-19.md (origin — top-3 анализ CLAUDE.md)
  - ~/.claude/skills/api-contract-checker/SKILL.md (adopted reference)
  - ~/.claude/skills/git-staging-safety/SKILL.md (adopted reference)
  - ~/.claude/skills/test-secrets-hardening/SKILL.md (adopted reference)
  - ~/.claude/skills/alembic-safe-migration-checker/SKILL.md (adopted reference)
  - ~/.claude/skills/fz152-pd-checker/SKILL.md (adopted reference)
  - docs/knowledge/bug_log.md
  - docs/reviews/adr-consistency-audit-2026-04-18.md
---

# RFC-2026-009: Next skill candidates — top-2 after 5 adopted

## 0. Расшифровка простым языком для Владельца (обязательный раздел)

### Что делаем
Представьте мастера на производстве, у которого на поясе висят 5 специальных инструментов — каждый для своего типа операции. Мы такие инструменты уже сделали для наших субагентов: 5 «skills» подсказывают правильный способ, когда субагент пишет миграцию БД, API-роут, тест, git-коммит или работает с персональными данными. Они загружаются автоматически — только когда задача подходит под ключевые слова. Остальные сессии идут «чисто», без раздувания контекста.

Этот документ — выбор **следующих двух инструментов** из трёх кандидатов. Первый — чтобы субагент не писал в commit-сообщении «добавил файл Х», а объяснял **почему** (правило, которое уже нарушалось). Второй — чтобы код не «разъезжался» с архитектурными решениями (ADR): у нас 22 ADR, и после одного аудита уже нашли расхождения.

### Зачем это нам
1. **commit-message-checker** — 3 раза за апрель мы ловили commit-сообщения в стиле «updated file». Reviewer тратит 2-5 минут на каждый, чтобы вернуть автора. Автопроверка на pre-commit hook (или skill с триггером `git commit`) закрывает это за 0.3 секунды.
2. **adr-drift-detector** — 22 ADR уже приняты, из них 12 активно влияют на код. Аудит 2026-04-18 нашёл drift в 3 местах. Ручной аудит раз в фазу — дорого; Claude Code сам должен ловить несоответствие при правке кода.

### Что предлагаем
Выбрать два из трёх и поручить ri-analyst (Opus, бюджет 4 часа каждый) собрать **proof-of-concept** — SKILL.md + 2-3 test-кейса, на которых видно, что skill действительно срабатывает. Третий кандидат (`bug-patterns-learner`) откладывается — материала в `bug_log.md` пока мало (3 записи, все закрыты как «не баг»).

---

## 1. Кандидаты (изначальный список от Координатора)

| Кандидат | Что делает | Триггер | Источник необходимости |
|---|---|---|---|
| **A. bug-patterns-learner** | Собирает повторяющиеся баги из `bug_log.md`, генерирует skill на их отлов | Manual; periodic по bug_log | Предположение, что bug_log копится |
| **B. commit-message-checker** | Проверяет правило CLAUDE.md §Git: «commit-message — почему, не что» | `git commit`, `git commit -m`, pre-commit hook | CLAUDE.md §Git, повторяющиеся нарушения в истории |
| **C. adr-drift-detector** | Сверяет код с adopted ADR, флаг «код разошёлся с решением» | При правке файлов, упомянутых в ADR (`backend/app/api/*`, migrations, схемы) | `docs/reviews/adr-consistency-audit-2026-04-18.md`, 22 ADR |

---

## 2. Анализ и вердикт

### Кандидат A — `bug-patterns-learner` — **reject (на этой итерации)**

**Почему reject:**
- `docs/knowledge/bug_log.md` сейчас содержит 3 записи, все закрыты как «не баг». Обучать skill не на чем.
- Это **meta-skill** (skill, который генерирует skill). Для проекта с 5 adopted skills — overkill; usefulness появится при 15+ закрытых P0/P1 дефектов с паттернами.
- Более простое решение: при каждом закрытом P0/P1 reviewer вручную эскалирует ri-director «не пора ли skill?». Пороговое накопление — 3 однотипных дефекта.

**Возвращать к пересмотру:** когда `bug_log.md` накопит >10 записей с тегами типа регрессий.

---

### Кандидат B — `commit-message-checker` — **ACCEPT (PoC #1, быстрый win)**

**Обоснование:**
1. Правило уже есть в `CLAUDE.md` §Git (строка 70): «commit-message — почему, не что».
2. Триггер чёткий: `git commit`, `git commit -m`, work in pre-commit hook scope — тот же слой, что и H-2/H-3 из RFC-004 Phase 0 Hooks.
3. Малый скоуп PoC: regex + LLM-проверка на 2-3 примерах + отчёт.
4. Быстро интегрируется с уже adopted `git-staging-safety` skill (оба на `git commit` уровне).
5. **Возможная миграция:** после PoC — это не обязательно skill, может уехать в pre-commit hook (H-6 в RFC-004 Phase 0+). Skill остаётся как подсказчик «переформулируй» при написании commit-сообщения в интерактивной сессии; hook — жёсткий gate перед `git commit`.

**PoC скоуп для ri-analyst** (бюджет 4 часа):
- SKILL.md draft (60-100 строк): description (keyword triggers), инструкции по рефрейму «что→почему», 3-5 примеров плохих/хороших сообщений из реальной истории coordinata56.
- 3 test-кейса: (a) коммит «add user_profile.py» → skill должен предложить рефрейм; (b) коммит «Fix NULL crash in /houses because missing parent_id check» → skill пропускает; (c) коммит «WIP» → skill предлагает добавить контекст или отложить.
- Рекомендация по миграции в hook или оставлении как skill.
- Сравнение с existing `git-staging-safety` — убедиться, что нет дублирования.

---

### Кандидат C — `adr-drift-detector` — **ACCEPT (PoC #2, высокая ценность)**

**Обоснование:**
1. У нас 22 ADR, из них ~12 активно влияют на код (0004-0007, 0011, 0013, 0016-0021).
2. `docs/reviews/adr-consistency-audit-2026-04-18.md` — ручной аудит, нашёл drift. Stale к следующей фазе M-OS-1, понадобится ещё аудит.
3. Паттерн уже есть в коммьюнити: `adr-compliance-checker` в `~/.claude/skills/` (готовый референс, можно изучить).
4. Работает асимметрично skills выше: не при редактировании одного файла, а при изменении файлов, упомянутых в ADR. Требует mapping «ADR → paths» — это **часть PoC**.

**PoC скоуп для ri-analyst** (бюджет 4 часа):
- Изучить existing `~/.claude/skills/adr-compliance-checker/` (если есть реализация — использовать как базу; если только идея — PoC пишется с нуля).
- Построить mapping ADR → paths для 5 наиболее «горячих» ADR (0005 API format, 0006 pagination, 0007 audit, 0011 foundation multi-company, 0013 migrations).
- SKILL.md draft: триггер — правка `backend/app/api/*.py`, `backend/alembic/versions/*.py`, `backend/app/services/*.py`.
- 3 test-кейса из `adr-consistency-audit-2026-04-18.md` — skill должен поймать те же drift'ы.
- Сценарий out-of-scope: skill **не** запускает sync (не автоправит), только флагует.

**Риск PoC:**
- ADR меняются (amendments), mapping может устареть. Контрмера: поле `last_reviewed_at` в SKILL.md + правило ручного ревью mapping раз в фазу.

---

## 3. Top-2 — `commit-message-checker` + `adr-drift-detector`

| Критерий | B. commit-message-checker | C. adr-drift-detector | A. bug-patterns-learner |
|---|---|---|---|
| Проблема уже болит | 3 нарушения в апреле | 3 drift в аудите | 0 паттернов в bug_log |
| PoC-сложность | Низкая (regex + 3 примера) | Средняя (ADR mapping) | Высокая (meta-level) |
| Трудоёмкость ri-analyst | ~3 часа | ~4 часа | ~6+ часов |
| Ожидаемая дельта | -2-5 мин на commit review | -30 мин ADR-аудита в фазу | нет сигнала |
| Конкуренция с existing tooling | pre-commit hook (координируется с RFC-004) | existing skill в `~/.claude/skills/adr-compliance-checker/` — референс | нет |
| **Вердикт** | **Adopt в PoC** | **Adopt в PoC** | **Reject на этой итерации** |

---

## 4. Бриф для ri-analyst (обязательный — см. регламент R&I §Kanban Phase 2)

### Задача ri-analyst (параллельно, два независимых PoC)

**PoC #1 — `commit-message-checker`**

- **Цель:** оценить, закроет ли skill правило CLAUDE.md §Git «commit-message — почему, не что».
- **Входы:** CLAUDE.md §Git (строка 70), история коммитов за 2 недели (`git log --oneline -50`), существующий skill `git-staging-safety` (reference).
- **Выход:** draft `~/.claude/skills/commit-message-checker/SKILL.md` (не commit, только draft в temp); 3 test-кейса; рекомендация по миграции в hook (возможно, H-6 в RFC-004 Phase 0+).
- **Вопрос, на который отвечает:** `adopt` / `iterate` / `reject` + обоснование.
- **Бюджет:** 4 часа; при превышении — эскалация ri-director.

**PoC #2 — `adr-drift-detector`**

- **Цель:** оценить, можно ли автоматически ловить drift между кодом и adopted ADR на этапе написания кода (не постфактум).
- **Входы:** `docs/reviews/adr-consistency-audit-2026-04-18.md` (golden-set drift'ов), 12 active ADR, existing `~/.claude/skills/adr-compliance-checker/SKILL.md` (если есть — использовать как базу).
- **Выход:** draft SKILL.md (extended или новый); mapping ADR → paths для 5 горячих ADR; 3 test-кейса воспроизводящих drift'ы из аудита; оценка поддерживаемости mapping.
- **Вопрос, на который отвечает:** `adopt` / `iterate` / `reject` + обоснование.
- **Бюджет:** 4 часа; при превышении — эскалация ri-director.

### Формат сдачи PoC (для обоих)

- SKILL.md draft лежит в `docs/research/pocs/skill-<name>-poc-2026-04-XX/SKILL.md` (временно, не в `~/.claude/skills/`; перенос — решение ri-director после PoC).
- Test-кейсы — в том же каталоге: `test-cases.md`.
- Отчёт PoC: `docs/research/pocs/skill-<name>-poc-2026-04-XX/report.md` (≤300 слов: дельта, риски, вердикт).

Два PoC могут выполняться параллельно (ri-analyst может совмещаться с ri-scout по малому потоку, см. регламент R&I §«Совмещение ролей») либо последовательно — бюджет суммарно ≤8 часов на обе PoC.

---

## 5. Что дальше (roadmap после PoC)

- **Оба adopt:** skills переезжают в `~/.claude/skills/`, CLAUDE.md §Git сокращается на ~1 строку (ссылка на skill), ADR governance получает автоматизацию. governance-director вносит правило в CODE_OF_LAWS v2.0 «Skill покрывает правило → CLAUDE.md содержит ссылку, не инструкцию».
- **Один adopt / один iterate:** iterate идёт на второй круг PoC (бюджет ещё 2 часа) или откладывается.
- **Оба reject:** записываем в `_skipped.md` с причинами, возвращаемся к этому после 3-х повторных инцидентов каждого типа.

---

*Документ — draft. PoC стартует только после решения Координатора на выделение ri-analyst.*
