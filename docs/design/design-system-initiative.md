# Design System Initiative M-OS

- **Версия:** 0.1 (черновик)
- **Дата:** 2026-04-18
- **Автор:** design-director
- **Статус:** черновик — ожидает RFC-006 (20–21 апреля) и UI/UX axis (22 апреля) для консолидации в v1.0
- **Финал:** 25 апреля 2026

---

## Executive Summary

Design-система M-OS — единая точка истины для всех визуальных и UX-решений внутреннего ПО холдинга. Это не коллекция картинок, а **живое соглашение команды**: компоненты, токены, паттерны поведения, стандарты доступности, правила производительности и документирования.

**Ключевые выводы из 4 полученных inputs:**

- Стек зафиксирован: React 18 + TypeScript + Vite + Tailwind v3.4 + shadcn/ui + Radix primitives. Менять нельзя до M-OS-2.
- shadcn/ui покрывает ~80% компонентов из коробки. Три сценария требуют кастомных решений: BPMN-canvas, DnD Form Builder, Permissions Matrix.
- Стандарт доступности: WCAG 2.2 AA — обязателен в CI, не ручной процесс.
- Performance budget зафиксирован: Admin UI initial bundle ≤200 KB gzip, Telegram WebApp ≤150 KB gzip.
- Storybook отложить до Фазы 7. Документация — Markdown в репозитории под version control.
- Вся инфраструктура self-hosted: ни CDN, ни внешних SaaS для observability.

**Что не решено до RFC-006 и UI/UX axis:**
- Dark mode в M-OS-1 или M-OS-2
- Разделение дизайн-языка Admin UI и Telegram WebApp (один или раздельные)
- Количество токенов brand-цвета на компанию
- BPM-canvas: shadcn снаружи + bpmn.io внутри, или перетемизировать bpmn-js
- SVG vs canvas для BPM-конструктора (влияет на WCAG AA)

---

## Принципы и философия

### Принцип 1. UX важнее визуального полиша
На MVP фокус на удобной архитектуре и user flows. Визуальный полиш — отдельной фазой позже (правило Владельца, `feedback_ux_over_visual_design.md`).

### Принцип 2. Компонент = соглашение, не картинка
Каждый компонент описывает не только внешний вид, но: состояния (loading/empty/error), aria-атрибуты, data-testid конвенцию, микрокопи, ограничения по контексту использования.

### Принцип 3. Без цвета как единственного носителя смысла
8% мужчин — дальтоники. Любой статус (ошибка, предупреждение, успех) = цвет + иконка + текст. Обязательно для финансовых данных.

### Принцип 4. Документация рядом с кодом
Все файлы design-системы в `docs/design-system/`, под version control, рядом с ADR. Документ вне репозитория неизбежно устаревает.

### Принцип 5. Сначала shadcn/ui, кастом — только с обоснованием
Уход с Radix primitives = +30% времени разработки + +2 дня QA. Кастомные компоненты только для сценариев, которые shadcn физически не закрывает.

### Принцип 6. Производительность как функциональное требование
Performance budget — не рекомендация, а CI-гейт. Превышение = red build.

---

## Design Tokens — трёхуровневая архитектура

Набросок. Финальные значения — после RFC-006.

### Уровень 1 — Primitive Tokens (сырые значения)

Значения без семантики. Являются источником для Уровня 2.

```
color-slate-50 ... color-slate-950     (нейтральная шкала)
color-blue-500 ... color-blue-700      (акцент)
color-red-500 ... color-red-700        (критичное)
color-yellow-400 ... color-yellow-600  (предупреждение)
color-green-500 ... color-green-700    (успех)

space-1: 4px   space-2: 8px   space-3: 12px   space-4: 16px
space-6: 24px  space-8: 32px  space-12: 48px  space-16: 64px

font-size-xs: 12px   font-size-sm: 14px   font-size-base: 16px
font-size-lg: 18px   font-size-xl: 20px   font-size-2xl: 24px

radius-sm: 4px  radius-md: 6px  radius-lg: 8px  radius-xl: 12px
```

### Уровень 2 — Semantic Tokens (смысловые роли)

Реализованы через CSS custom properties. В коде — **только semantic tokens**, никогда primitive напрямую (никогда `bg-blue-500` в коде — только `bg-[--color-primary]`).

```
--color-primary           (основной акцент)
--color-primary-hover
--color-surface           (фон карточек, панелей)
--color-surface-raised    (фон поверхностей выше surface)
--color-background        (фон страницы)
--color-text-primary      (основной текст)
--color-text-secondary    (вспомогательный текст)
--color-text-disabled
--color-text-on-primary   (текст на primary-фоне)
--color-border            (стандартная граница)
--color-border-focused    (фокус-состояние)

-- Semantic states (каждый = цвет + иконка, не только цвет)
--color-critical          (ошибка/outage)
--color-warning           (предупреждение/degraded)
--color-success           (успех)
--color-info              (информация/maintenance)

-- System observability states (из infra-director input)
--color-state-healthy     (нет маркеров)
--color-state-degraded    (жёлтый баннер)
--color-state-partial     (жёлто-оранжевый баннер)
--color-state-outage      (красный fullscreen)
--color-state-maintenance (синий баннер)
--color-state-mismatch    (красный модал)

--space-component-gap     (отступ внутри компонента)
--space-section-gap       (отступ между секциями)
--space-page-padding      (отступ страницы)
```

### Уровень 3 — Component Tokens (переопределения на уровне компонента)

Задаются в файле компонента, переопределяют semantic токены локально. Нужны для brand-per-company подмены и тёмной темы.

```
-- brand per-company (runtime замена, минимум 3 токена — вопрос открыт)
--brand-primary
--brand-accent
--brand-logo-url

-- PWA-специфика
--safe-area-inset-top     (iPhone notch)
--safe-area-inset-bottom
--touch-target-min: 44px
```

---

## Компонентная библиотека

### shadcn/ui — использовать свободно (16 компонентов)

`Dialog`, `DropdownMenu`, `Command`, `Tooltip`, `ScrollArea`, `Separator`, `Label`, `Form`, `Tabs`, `Sheet`, `Toast`, `Button`, `Input`, `Textarea`, `Select`, `Checkbox`, `RadioGroup`, `Switch`, `Card`

### shadcn/ui — проблемные (требуют обёртки или договорённостей)

| Компонент | Проблема | Решение |
|---|---|---|
| `DataTable` | Собирается вручную из примитивов | Единый wrapper `MOSTable` в `shared/ui/` |
| `DatePicker` | Нет готового — собирается из Calendar + Popover | Фиксируем сборку как паттерн |
| `Combobox` | Без виртуализации, >1000 элементов лагает | Ограничить источники до 1000 эл. или виртуализировать |
| `Toast` | Только top-level-роут | Только в корне приложения |

### Кастомные компоненты (сверх shadcn)

Три сценария, которые shadcn не покрывает:

| Компонент | Библиотека | Причина кастома |
|---|---|---|
| BPMN-canvas | `bpmn-js` (Camunda) | shadcn не даёт canvas для BPM. Визуал свой, не Tailwind. Вопрос открыт: перетемизировать bpmn-js или принять «два визуальных языка» |
| DnD Form Builder | `@dnd-kit` | shadcn не даёт drag-and-drop |
| Permissions Matrix | `@tanstack/react-table` + ручная виртуализация | shadcn `<Table>` без sticky-колонок и виртуализации |

### Ограничения по компонентам

- Dialog в Dialog — UX-антипаттерн. Использовать wizard или slide-over.
- Popover + Tooltip на одном триггере — конфликт.
- Select в Dialog — iOS Safari баг при первом открытии.
- Максимум колонок на desktop: 10–12. Больше — sticky-левые + горизонтальный скролл.
- Вложенные React Portals: максимум 2 уровня (Playwright теряет корень при >2).

### Таблицы — hard limits

- shadcn `<Table>` без виртуализации: комфортно до ~200 строк.
- Свыше 500 строк: обязательна виртуализация через `@tanstack/react-virtual`.
- Мобильный вид (Telegram WebApp, прораб): обязательно card-view как альтернатива таблице.

### Иконки

Только `lucide-react`, размеры 16/20/24px. Любая иконка-кнопка без текстовой подписи — обязателен `aria-label`.

### Анимации — 5 разрешённых типов

`fade-in/out`, `slide-in-from-side`, `zoom-in/out`, `pulse`, `spin`. Параллакс / scroll-triggered / 3D — запрещены на MVP. CSS-анимации >300ms на критическом пути — запрещены (Playwright ждёт → flaky тесты; `prefers-reduced-motion` обязателен).

---

## Accessibility — WCAG 2.2 AA

### Уровень соответствия

WCAG 2.2 Level AA — минимум, обязательный в CI. AAA не применяется: M-OS внутреннее ПО холдинга, не публичный сервис. Если появится партнёрский или покупательский кабинет — AA становится юридически обязательным по ФЗ-419 (вопрос открыт, quality-director требует ответа).

### Три специфических требования сверх AA

1. Keyboard-first навигация по всем BPM-конструкторам. Мышь без клавиатурного аналога — недопустима.
2. Русская локаль в `aria-label` всегда. NVDA/Jaws на английских лейблах работает некорректно.
3. Цвет — не единственный носитель смысла. Всегда: цвет + иконка + текст.

### 5 обязательных элементов в wireframes (блокер приёмки)

1. `data-testid` на каждом интерактивном элементе. Конвенция: `<domain>-<component>-<action>`, например `houses-table-row-edit`. Lowercase-kebab.
2. `aria-label` на иконках без текста.
3. `role` атрибуты на non-semantic контейнерах.
4. Tab-order пронумерован в макете (стрелки 1→2→3).
5. Loading / empty / error состояния — отдельные фреймы, не «пририсуем потом».

### 6 запрещённых паттернов (из quality-director)

1. Вложенные React Portals > 2 уровней.
2. Canvas-based конструкторы без SVG-рендера (bpmn-js canvas блокирует keyboard nav + WCAG AA).
3. Drag-and-drop без клавиатурной альтернативы.
4. CSS-анимации >300ms на критическом пути без `prefers-reduced-motion`.
5. Infinite scroll без `aria-live`.
6. Кастомные `<select>` вместо Radix Combobox.

### Инструментарий

- `eslint-plugin-jsx-a11y` — добавить в frontend lint немедленно (1 час работы).
- `@axe-core/playwright` — WCAG-проверки в CI, автоматически. Не ручной процесс.
- Storybook + Chromatic — отложить до Фазы 7.

---

## Performance Budget

Источник: infra-director input. Значения — CI-гейт, не рекомендации.

### Метрики

| Метрика | Admin UI | Telegram WebApp | Потолок |
|---|---|---|---|
| LCP | ≤ 2.0 с | ≤ 2.5 с | 4.0 с |
| TTI | ≤ 3.0 с | ≤ 3.5 с | 5.0 с |
| FCP | ≤ 1.2 с | ≤ 1.5 с | 2.5 с |
| INP | ≤ 200 мс | ≤ 300 мс | 500 мс |
| CLS | ≤ 0.1 | ≤ 0.1 | 0.25 |
| JS bundle initial gzip | ≤ 200 KB | ≤ 150 KB | 300 KB |
| CSS initial gzip | ≤ 30 KB | ≤ 20 KB | 50 KB |
| Шрифты суммарно | ≤ 100 KB | ≤ 60 KB | 150 KB |
| Одна картинка | ≤ 200 KB | ≤ 100 KB | 400 KB |

### Шрифты

- Self-hosted only. Google Fonts / Yandex Fonts запрещены (egress whitelist VPS).
- Максимум 2 семейства × 3 веса (regular/medium/bold).
- Только woff2, `font-display: swap`, unicode-range для кириллицы.

### Изображения

- SVG для иконок/логотипов/схем. Инлайн только <2 KB.
- Растр: WebP основной, AVIF желателен.
- Hero-картинки на 1–2 MB — запрещены.
- Telegram WebApp: `loading="lazy"` ниже fold, только WebP/AVIF.

### Enforcement в CI

- `size-limit` или `bundlesize`: CI падает при превышении порогов.
- Lighthouse CI на preview-сборке: падает при LCP > 3 с или CLS > 0.15.

### UI-состояния системы (6 состояний инфры)

| Состояние | Триггер | UI-индикатор |
|---|---|---|
| Healthy | Всё работает | Нет маркеров |
| Degraded (slow) | p95 API > 2 с | Жёлтый баннер + «Подробнее» |
| Partial outage | Health-check модуля fail | Жёлто-оранжевый баннер + список работает/нет |
| Full outage | >3 подряд 5xx/timeout | Красный fullscreen + кэшированные данные с меткой |
| Maintenance | Флаг в `/api/health` | Синий баннер «Плановые работы до HH:MM» |
| Version mismatch | Frontend N+1, backend N-1 | Красный модал «Обновите страницу (Ctrl+Shift+R)» |

Все индикаторы: различаются не только цветом (иконки + текст). Dismissible для некритичных (degraded, maintenance), non-dismissible для критичных (outage, version mismatch).

### Offline-режим (Telegram WebApp)

- Оптимистичный UI + retry с экспоненциальной задержкой.
- Баннер: «Нет связи. Изменения отправятся при восстановлении».
- Иконка часов/облака у кнопок «Сохранить» до синхронизации.
- Offline в MVP или M-OS-2 — вопрос открыт (infra-director ожидает ответа).

---

## Документирование Design System

Источник: tech-writer input.

### Структура docs/design-system/

```
docs/design-system/
  README.md              — навигатор: что здесь и как пользоваться
  tokens/
    colors.md            — цветовые токены (имя → значение → когда использовать)
    typography.md        — шрифты, размеры, отступы
    spacing.md           — сетка отступов
  components/
    button.md            — описание: варианты, состояния, микрокопи
    dialog.md
    sheet.md
    ...
  patterns/
    empty-states.md      — паттерн «пустой экран»
    error-states.md      — паттерн «ошибка»
    confirmations.md     — паттерн «подтверждение действия»
  glossary.md            — UX-термины на русском
  microcopy.md           — справочник формулировок
```

Следует Diátaxis: `tokens/` и `components/` — Reference; `patterns/` — How-to. Mermaid-диаграммы для иллюстрации состояний.

### Storybook

Отложить до Фазы 7. Обоснование: нет выделенной роли для поддержки. Устаревший Storybook хуже отсутствия документации.

### Микрокопи — стандарты (обязательный раздел в docs/design-system/microcopy.md)

- **Ошибки:** «Что пошло не так» + «Что сделать». Без технических кодов. Пример: вместо «Error 422» → «Заполните обязательные поля: Название, Сумма».
- **Кнопки действий:** глагол + объект. «Сохранить черновик», «Удалить договор», «Согласовать платёж».
- **Подтверждения необратимых действий:** называть конкретно, что удаляется. «Удалить договор №КП-2026-014? Это действие необратимо. Платежи по договору сохранятся.»
- **Пустые состояния:** объяснение + причина + действие. «Договоров пока нет. Добавьте первый договор. [Добавить договор]».
- Все формулировки — в мужском роде: «Договор сохранён», «Платёж отклонён».

### Глоссарий UX-терминов (обязателен)

| Термин (EN) | Русское название | Когда использовать |
|---|---|---|
| Dialog | Диалог | Блокирующий запрос подтверждения |
| Modal | Модальное окно | Форма или контент поверх страницы с тёмным фоном |
| Sheet | Шторка | Панель, выезжающая снизу/сбоку. Не блокирует контент |
| Drawer | Боковая панель | Постоянная или временная панель сбоку. Шире Sheet |
| Toast | Уведомление | Временное сообщение в углу |
| Tooltip | Подсказка | Появляется при наведении |
| Banner | Баннер | Постоянная плашка («Система на техобслуживании») |
| Empty state | Пустой экран | Состояние страницы когда данных нет |
| Loading state | Состояние загрузки | Компонент ожидает ответа сервера |
| Skeleton | Скелетон | Анимированные заглушки при загрузке |

Владелец глоссария: tech-writer создаёт и ведёт, design-director утверждает термины.

### Wireframes — именование и хранение

Wireframes в `docs/design-system/wireframes/` с именованием по User Story: `US-042-house-list.md`.

Перекрёстные ссылки:
- В каждом файле компонента — раздел «Контекст использования» со ссылками на User Stories.
- В каждой User Story — раздел «Дизайн-артефакты» с именем wireframe и компонента.
- В ADR — раздел «Затронутые компоненты UI» при визуальном решении.

---

## Inputs от департаментов

| Директор | Файл | Статус | Критичные требования |
|---|---|---|---|
| frontend-director | `docs/design/inputs/frontend-director.md` | Получен | Стек ADR 0002, 3 кастомных компонента, bundle limits, 7 вопросов |
| quality-director | `docs/design/inputs/quality-director.md` | Получен | WCAG 2.2 AA в CI, Playwright + axe-core, 5 блоков в wireframes, 5 вопросов |
| infra-director | `docs/design/inputs/infra-director.md` | Получен | Performance budget, self-hosted observability (GlitchTip), 6 UI-состояний, 7 вопросов |
| tech-writer | `docs/design/inputs/tech-writer.md` | Получен | Структура docs/design-system/, Storybook отложить, микрокопи, глоссарий, 4 вопроса |
| backend-director | — | Не получен (занят ADR-0017/0018) | Ожидается: UI-паттерны для backend-состояний, optimistic update, типы ошибок API |
| governance-director | — | API Error — недоступен | Ожидается: ADR для дизайн-решений, процесс пересмотра токенов, уровень review |

---

## Open Questions

Консолидированный список открытых вопросов от всех 4 директоров. Ответы design-director даёт до или после RFC-006.

### От frontend-director

1. **Два визуальных языка в BPM-canvas**: принимаем «shadcn снаружи, bpmn.io внутри», или переопределяем тему bpmn-js (~1 неделя работы)?
2. **Brand colors per-company**: сколько токенов подлежит подмене? Предложение frontend: 3 (primary, accent, logo-URL).
3. **Dark mode — M-OS-1 или M-OS-2?**
4. **Data-density**: Compact (56px) / Regular (72px) / Comfortable (96px) — сколько режимов на MVP?
5. **Empty/error/loading states** — стандартный паттерн обязателен. Кто разрабатывает спецификацию?
6. **PWA-лейаут vs admin-лейаут** — один design-language или раздельные?
7. **Кастомные иконки сверх Lucide** — процесс согласования какой?

### От quality-director

8. **Публичный доступ к любому UI M-OS?** Партнёрский кабинет, кабинет покупателя — если да, AA становится юридически обязательным (ФЗ-419).
9. **Кто утверждает дизайн-токены контраста?** Предложение quality: design предлагает, quality валидирует AA автоматически, Координатор разрешает конфликт.
10. **BPM-конструктор Admin UI: SVG или canvas?** Canvas блокирует keyboard nav + WCAG AA.
11. **Брендовые цвета холдинга есть?** Проверить на AA-контраст до заведения в Tailwind.
12. **Формат макетов — Figma?** Влияет на то, как design отдаёт `data-testid` и tab-order.

### От infra-director

13. **Разделение budget Admin UI / Telegram WebApp** — design согласен с предложенными порогами?
14. **Тяжёлые компоненты в scope design** (Gantt, чертежи, видео, rich-text) — заранее договориться, что идёт в lazy-чанки.
15. **Палитра semantic states** (healthy/degraded/outage/maintenance) — 4 цвета + 4 иконки в токенах сразу или позже?
16. **Offline-режим в MVP или M-OS-2?** Если MVP — Service Worker проектируется сразу.
17. **Шрифты — максимум 2 × 3 + кириллический сабсет**: какие конкретно семейства?
18. **Статус-страница `/status`** — дизайн чей? Design или infra?
19. **Telemetry consent** — нужен ли баннер «собираем web-vitals»? Для внутреннего ПО, вероятно нет — legal подтвердит.

### От tech-writer

20. **Figma vs code-first**: wireframes живут в Figma или сразу в коде? Влияет на формат хранения.
21. **Кто владеет глоссарием?** Предложение tech-writer: tech-writer создаёт, design-director утверждает.
22. **Язык компонентов в задачах команды**: в коде — английские (Button, Sheet). В задачах — русские («шторка») или английские? Нужна однозначность.
23. **Приоритет компонентов для документирования**: начать с используемых в M-OS-1. Список от design-director.

### Блокирующие вопросы (tech-writer не приступает без ответов)

- Вопрос 20 (Figma vs code-first) — блокирует структуру хранения.
- Вопрос 22 (язык компонентов в задачах) — блокирует именование.

---

## Roadmap внедрения (набросок)

Финальный roadmap — после RFC-006 и UI/UX axis 22 апреля.

### Сейчас — до 25 апреля

- RFC-006: пройти 20–21 апреля. Цель: согласовать вопросы 1, 3, 6, 10, 13, 16 из Open Questions.
- UI/UX axis: 22 апреля. Цель: решить вопросы дизайн-языка и философии.
- Консолидация → design-system-initiative.md v1.0: 25 апреля.
- Ответы backend-director и governance-director: интегрировать при получении.

### M-OS-1 (текущая фаза)

- Развернуть структуру `docs/design-system/` согласно рекомендации tech-writer.
- Добавить `eslint-plugin-jsx-a11y` в frontend lint (1 час, можно немедленно).
- Ввести `size-limit` / `bundlesize` в CI (infra-director, 1–2 недели).
- Добавить `@axe-core/playwright` в CI (quality-director).
- Зафиксировать первичный глоссарий UX-терминов (tech-writer, после ответа на вопросы 20 и 22).
- Определить токены semantic states (4 цвета + 4 иконки) — infra + design.

### M-OS-2

- Переключатель dark mode (если принято решение в RFC-006).
- Перенос Combobox на виртуализацию при источниках > 1000 элементов.
- Оценить Storybook (при достижении 30+ компонентов).
- Tailwind v3 → v4 миграция.

### Фаза 7+

- Storybook + Chromatic (если Admin UI становится продуктом).
- Visual regression testing полного масштаба.

---

*Документ подготовлен design-director, 2026-04-18.*
*v0.1 — черновик на основе 4 из 6 запрошенных inputs.*
*Финал v1.0 — 25 апреля 2026 после RFC-006 (20–21 апр) и UI/UX axis (22 апр).*
*Недостающие inputs: backend-director (занят ADR-0017/0018), governance-director (API Error).*
