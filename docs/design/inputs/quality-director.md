# Input от quality-director — Design System Initiative

**Дата:** 2026-04-18
**От:** quality-director

## Ответы на 4 вопроса

### 1. Уровень WCAG для M-OS

**WCAG 2.2 Level AA — минимум, обязательный в CI.** Не AAA.

Обоснование:
- M-OS — внутреннее ПО холдинга, не публичный сервис. ФЗ-419 не применяется.
- AAA стоит x3-x5 по времени дизайна/разработки, ломает плотную BI-графику.
- AA покрывает 90% реальных случаев.

**Специфические требования сверх AA (3):**
1. **Keyboard-first навигация по всем BPM-конструкторам** — работа мышью по вложенным узлам BPMN недопустима без клавиатурного аналога.
2. **Русская локаль в aria-label всегда** — NVDA/Jaws на английском читает «бу-бу-бу».
3. **Цвет не единственный носитель смысла** — финансы красят отклонения красным/зелёным, нужны иконки/знаки в пару (8% мужчин — дальтоники).

### 2. Visual regression testing

**Для MVP — Playwright screenshots + axe-core, не Chromatic/Percy.**

Обоснование отказа:
- Chromatic/Percy $149/мес, завязка на SaaS (против `feedback_no_live_external_integrations.md`).
- Окупается при 5+ фронтах, 10+ изменений/нед. У нас 1 frontend-worker.

**Используем:**
- `@playwright/test` + `toHaveScreenshot()` — встроенный pixel-diff, хранение в git-LFS.
- `@axe-core/playwright` — WCAG проверки в том же прогоне.
- Пересмотреть для Фазы 7+ (Admin UI как продукт) — Storybook + Chromatic.

**Интеграция в CI:**
- Новый job `frontend-test` параллельно `test` и `lint`.
- Шаги: `pnpm build → playwright install --with-deps → playwright test`.

### 3. Что design обязан класть в wireframes

**5 пунктов — блокер приёмки wireframe:**

1. **`data-testid` на каждом интерактивном элементе.** Конвенция: `<domain>-<component>-<action>`, напр. `houses-table-row-edit`. Без пробелов, lowercase-kebab.
2. **`aria-label` на иконках без текста.** Любая кнопка с Lucide-иконкой без подписи — `aria-label="Сохранить"`.
3. **`role` атрибуты на non-semantic контейнерах.** `<div>`-таблица → `role="table"`. Radix закрывает для своих, для самописных — явная пометка.
4. **Tab-order в макете пронумерован.** Стрелки 1→2→3.
5. **Loading / empty / error состояния** — отдельные фреймы, не «пририсуем потом».

### 4. Паттерны, которые сложно тестировать

**Чёрный список из 6 пунктов:**

1. **Вложенные React Portals > 2 уровней** — Playwright теряет корень.
2. **bpmn-js / canvas-based конструкторы** — canvas pixel-noise для Playwright, скрин-ридер не читает. Требовать SVG-рендер или React Flow, не bpmn-js.
3. **Drag-and-drop без клавиатурной альтернативы** — не тестируется стабильно, не проходит AA.
4. **CSS-анимации >300ms на критическом пути** — Playwright ждёт анимации → flaky тесты. `prefers-reduced-motion` обязателен.
5. **Infinite scroll без `aria-live`** — QA не дождётся «загрузка завершилась».
6. **Кастомные `<select>` вместо Radix Combobox** — нативный скрин-ридер читает, самописный div-select — нет.

## Критичные ограничения

- Axe-core в CI **обязателен**, не ручной процесс.
- Baseline для visual diff — командой, не автоматом.
- AA-чеклист на CI-уровне до code-review.
- **OWASP AI Testing Guide 2026 (RFC-005 Q-2)** применима частично. Для design — 1 требование: UI-поле, текст из которого уходит в LLM-промпт субагента, помечать в макете `[UNSAFE_INPUT]`, QA вешает prompt-injection тест.

## Возможности / рекомендации

- **Tailwind tokens + CSS custom properties для AA-контраста** — `--color-text-on-surface`, `--color-critical-high-contrast` с заранее проверенными парами.
- **Storybook отложить до Фазы 7**. Сейчас 9 страниц — overkill. При 30+ компонентов — включить.
- **shadcn/ui + Radix уже выбран** — 80% a11y «из коробки». Не сходить с этого рельса: custom = +2 дня QA.
- **`eslint-plugin-jsx-a11y`** — добавить в frontend lint прямо сейчас, 1 час работы.
- **CI pipeline:**
  ```
  frontend-test:
    - pnpm lint (jsx-a11y)
    - pnpm typecheck
    - pnpm playwright test --project=chromium (func + visual + axe)
    - artifact: playwright-report/ (14 дней)
  ```

## Вопросы к design-director

1. **Публичный доступ к любому UI M-OS?** (партнёрский кабинет, кабинет покупателя). Если да — AA становится юридически обязательным (ФЗ-419).
2. **Кто утверждает дизайн-токены контраста?** Предложение: design предлагает, quality валидирует AA автоматически, Координатор разрешает конфликт.
3. **BPM-конструктор Admin UI: SVG или canvas?** Архитектурное решение до Фазы 7. Canvas блокирует keyboard nav + WCAG AA.
4. **Брендовые цвета холдинга есть?** Проверить на AA-контраст до заведения в Tailwind.
5. **Формат макетов — Figma?** От этого зависит как design отдаёт `data-testid` и tab-order.

---

*Источники: `departments/quality.md`, `.github/workflows/ci.yml`, RFC-005 §5 шаг 5 (Q-2 OWASP AI Testing), `frontend/package.json`, feedback_no_live_external_integrations.*
