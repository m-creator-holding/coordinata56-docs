# Input от frontend-director — Design System Initiative

**Дата:** 2026-04-18
**От:** frontend-director

## Критичные ограничения (то, что design обязан учесть)

### 1. Стек фиксирован ADR 0002 — менять нельзя
React 18 + TypeScript + Vite + Tailwind CSS **v3.4** + shadcn/ui + Radix primitives. **Tailwind v4 ещё не в стеке** — не закладывайте v4-only возможности (CSS `@theme`, oklch-палитры как дефолт, нативные container queries v4-формата). Переход v3→v4 — задача M-OS-2.

### 2. shadcn/ui не покрывает 3 критичных для M-OS сценария
- **BPMN-canvas** — shadcn ничего не даёт. Берём `bpmn-js` (Camunda). Визуал свой, не Tailwind.
- **Drag-and-drop Form Builder** — shadcn не даёт DnD. Пишем поверх `@dnd-kit`.
- **Матрица прав** — shadcn `<Table>` без виртуализации, без sticky-колонок. Нужно `@tanstack/react-table` + ручная виртуализация.

### 3. Большие таблицы — hard limits
- shadcn `<Table>` без виртуализации комфортно держит ~200 строк.
- >500 строк — обязательна виртуализация (`@tanstack/react-virtual`).
- **Максимум колонок на desktop: 10-12**. Больше — sticky-левые + горизонтальный скролл.
- Мобильный вид (PWA прораба) — обязательно card-view как альтернатива таблице.

### 4. Bundle size — целевые пороги
- **Admin UI chunk: ≤500KB gzip** (initial). Сейчас ~180KB без bpmn-js; с bpmn-js ~450KB.
- **PWA прораба chunk: ≤250KB gzip** (offline, 3G).
- Одна тяжёлая библиотека = -100-400KB. Требует обсуждения заранее.

### 5. Глубина вложенности компонентов
- Dialog в Dialog работает, но UX-антипаттерн — используйте wizard или slide-over.
- Popover + Tooltip на одном триггере конфликтуют.
- Select в Dialog — iOS Safari баг при первом открытии.

### 6. shadcn-компоненты без оговорок
`Dialog`, `DropdownMenu`, `Command`, `Tooltip`, `ScrollArea`, `Separator`, `Label`, `Form`, `Tabs`, `Sheet`, `Toast`, `Button`, `Input`, `Textarea`, `Select`, `Checkbox`, `RadioGroup`, `Switch`, `Card` — используйте свободно.

### 7. shadcn-компоненты проблемные
- `DataTable` — собирается вручную из примитивов, нужен единый wrapper `MOSTable` в `shared/ui/`.
- `DatePicker` — собирается из Calendar + Popover.
- `Combobox` — без виртуализации, >1000 элементов лагает.
- `Toast` — только top-level-роут.

## Возможности / рекомендации

### Темизация — CSS variables
- Все цвета только через CSS-переменные, никогда `bg-blue-500` в коде.
- Dark mode в M-OS-1: технически бесплатно, рекомендую заложить токены `dark` сразу, переключатель в M-OS-2.
- Brand colors per-company: runtime-подмена 3-5 токенов (primary, accent, logo-URL). Контрастность — проверять по WCAG-AA.

### Tailwind v3 — стандарты
- `cn()` (tailwind-merge + clsx) везде.
- `class-variance-authority` для вариантов компонентов.
- `tailwindcss-animate` — fast=100ms, default=150ms, slow=300ms.
- Брейкпоинты default (sm:640 md:768 lg:1024 xl:1280 2xl:1536) — менять только с обоснованием.

### Анимации — 5 типов, больше не придумывать
`fade-in/out`, `slide-in-from-side`, `zoom-in/out`, `pulse`, `spin`. Parallax/scroll-triggered/3D — запрещено на MVP.

### Иконки
Только `lucide-react`, размеры 16/20/24px.

### Accessibility
Radix primitives дают focus-trap/keyboard-nav/aria из коробки. Кастом не на Radix = +30% времени разработки.

### PWA-специфика
- Touch-target ≥44×44px
- Safe-area insets (iPhone notch) — токен в design-системе
- Landscape orientation — lock portrait или design рисует оба варианта

## Вопросы к design-director

1. **Два визуальных языка в BPM-canvas**: принимаем «shadcn снаружи, bpmn.io внутри», или переопределяем тему bpmn-js (~1 неделя работы)?
2. **Brand colors per-company**: сколько токенов подлежит подмене? Моё предложение — 3 (primary, accent, logo-URL).
3. **Dark mode — M-OS-1 или M-OS-2?**
4. **Data-density**: Compact (56px) / Regular (72px) / Comfortable (96px) — сколько режимов?
5. **Empty/error/loading states** — стандартный pattern обязателен.
6. **PWA-лейаут vs admin-лейаут** — один design-language или раздельные?
7. **Кастомные иконки сверх Lucide** — процесс какой?

---

*Источники: `frontend/package.json`, `m-os-1-frontend-plan.md`, ADR 0002.*
