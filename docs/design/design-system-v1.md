# Design System M-OS — v1.0

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **Автор:** design-director
- **Статус:** черновик — ожидает RFC-006 (20–21 апреля) и UI/UX axis (22 апреля)
- **Источники:** `design-system-initiative.md`, `wireframes-m-os-1-1-admin.md`
- **Назначение:** единый справочник токенов и спецификаций компонентов для frontend-director

---

## 1. Цветовая палитра

### Принцип применения

В коде используются **только semantic-токены** — никогда primitive-значения напрямую.
В Tailwind: `bg-[var(--color-primary)]`, не `bg-blue-500`.
Каждый статусный цвет всегда сопровождается иконкой и текстом (принцип «не только цвет»).

### 1.1 Primitive-цвета (исходная шкала)

Эти значения не используются в компонентах напрямую. Они являются источником для semantic-уровня.

| Токен | Hex | Назначение |
|---|---|---|
| `color-slate-50` | `#F8FAFC` | Самый светлый фон |
| `color-slate-100` | `#F1F5F9` | Фон страницы (light mode) |
| `color-slate-200` | `#E2E8F0` | Разделители, бордеры |
| `color-slate-400` | `#94A3B8` | Отключённый текст |
| `color-slate-500` | `#64748B` | Вспомогательный текст |
| `color-slate-700` | `#334155` | Основной текст (body) |
| `color-slate-900` | `#0F172A` | Заголовки |
| `color-slate-950` | `#020617` | Максимальный контраст |
| `color-blue-600` | `#2563EB` | Основной акцент (primary) |
| `color-blue-700` | `#1D4ED8` | Hover-состояние primary |
| `color-blue-50` | `#EFF6FF` | Фон info-баннера |
| `color-blue-200` | `#BFDBFE` | Бордер info-баннера |
| `color-green-600` | `#16A34A` | Успех |
| `color-green-700` | `#15803D` | Hover-состояние success |
| `color-green-50` | `#F0FDF4` | Фон success-баннера |
| `color-yellow-500` | `#EAB308` | Предупреждение |
| `color-yellow-600` | `#CA8A04` | Hover-состояние warning |
| `color-yellow-50` | `#FEFCE8` | Фон warning-баннера |
| `color-red-600` | `#DC2626` | Ошибка / критично |
| `color-red-700` | `#B91C1C` | Hover-состояние danger |
| `color-red-50` | `#FEF2F2` | Фон danger-баннера |
| `color-orange-500` | `#F97316` | Partial outage (инфра) |
| `color-white` | `#FFFFFF` | Белые поверхности |

### 1.2 Semantic-токены (используются в компонентах)

#### Основные роли

| CSS-переменная | Primitive-источник | Hex | Семантика |
|---|---|---|---|
| `--color-primary` | `color-blue-600` | `#2563EB` | Основной акцент: CTA-кнопки, ссылки, активные элементы |
| `--color-primary-hover` | `color-blue-700` | `#1D4ED8` | Hover/focus состояние primary |
| `--color-primary-foreground` | `color-white` | `#FFFFFF` | Текст на primary-фоне |
| `--color-background` | `color-slate-100` | `#F1F5F9` | Фон страницы |
| `--color-surface` | `color-white` | `#FFFFFF` | Фон карточек, панелей, таблиц |
| `--color-surface-raised` | `color-slate-50` | `#F8FAFC` | Фон поверхностей выше surface (попап, dropdown) |
| `--color-border` | `color-slate-200` | `#E2E8F0` | Стандартная граница |
| `--color-border-focused` | `color-blue-600` | `#2563EB` | Граница при фокусе на поле ввода |
| `--color-text-primary` | `color-slate-900` | `#0F172A` | Основной текст |
| `--color-text-secondary` | `color-slate-500` | `#64748B` | Вспомогательный текст, подписи |
| `--color-text-disabled` | `color-slate-400` | `#94A3B8` | Отключённые элементы |
| `--color-text-on-primary` | `color-white` | `#FFFFFF` | Текст на primary-фоне |

#### Semantic-состояния (success / warning / danger / info)

Каждое состояние имеет три варианта: `fg` (текст, иконка), `bg` (фон блока), `border` (рамка блока).

| CSS-переменная | Hex | Семантика |
|---|---|---|
| `--color-success` | `#16A34A` | Успешное действие: иконка, текст статуса |
| `--color-success-bg` | `#F0FDF4` | Фон success-баннера, toast-success |
| `--color-success-border` | `#BBF7D0` | Граница success-блока |
| `--color-warning` | `#CA8A04` | Предупреждение: иконка, текст статуса |
| `--color-warning-bg` | `#FEFCE8` | Фон warning-баннера |
| `--color-warning-border` | `#FDE047` | Граница warning-блока |
| `--color-danger` | `#DC2626` | Ошибка, деструктивное действие |
| `--color-danger-hover` | `#B91C1C` | Hover на danger-кнопке |
| `--color-danger-bg` | `#FEF2F2` | Фон error-баннера, toast-error |
| `--color-danger-border` | `#FECACA` | Граница error-блока |
| `--color-info` | `#2563EB` | Информационный статус |
| `--color-info-bg` | `#EFF6FF` | Фон info-баннера |
| `--color-info-border` | `#BFDBFE` | Граница info-блока |

#### Состояния инфраструктуры (для system-health-баннеров)

| CSS-переменная | Hex | UI-индикатор |
|---|---|---|
| `--color-state-healthy` | — | Нет маркеров |
| `--color-state-degraded` | `#EAB308` | Жёлтый баннер |
| `--color-state-partial` | `#F97316` | Жёлто-оранжевый баннер |
| `--color-state-outage` | `#DC2626` | Красный fullscreen-банер |
| `--color-state-maintenance` | `#2563EB` | Синий баннер |
| `--color-state-mismatch` | `#DC2626` | Красный модал «Обновите страницу» |

#### Brand per-company (runtime-замена)

| CSS-переменная | Дефолт | Описание |
|---|---|---|
| `--brand-primary` | `#2563EB` | Акцент конкретной компании |
| `--brand-accent` | `#1D4ED8` | Второй акцентный цвет |
| `--brand-logo-url` | — | URL логотипа компании |

Количество brand-токенов (3 или больше) — открытый вопрос до RFC-006.

---

## 2. Типографика

### Шрифт

- **Семейство:** Inter (основной), с системным fallback: `system-ui, -apple-system, sans-serif`
- **Вес:** Regular (400), Medium (500), SemiBold (600) — три веса × одно семейство, укладывается в лимит
- **Хранение:** self-hosted `/public/fonts/inter-*.woff2`; Google Fonts запрещены
- **Загрузка:** `font-display: swap`, unicode-range с кириллическим сабсетом
- **Общий объём:** ≤100 KB gzip (Admin UI), ≤60 KB (Telegram WebApp)

### Шкала размеров

| Уровень | CSS-переменная | px | rem | line-height | Применение |
|---|---|---|---|---|---|
| xs | `--text-xs` | 12 | 0.75 | 1.5 (18px) | Подписи, help-текст под полями, метки |
| sm | `--text-sm` | 14 | 0.875 | 1.5 (21px) | Вторичный текст, badge, caption |
| base | `--text-base` | 16 | 1.0 | 1.5 (24px) | Основной body-текст, input-значения |
| lg | `--text-lg` | 18 | 1.125 | 1.4 (25px) | Заголовки карточек, названия секций |
| xl | `--text-xl` | 20 | 1.25 | 1.3 (26px) | Заголовки страниц (H2), section-headers |
| 2xl | `--text-2xl` | 24 | 1.5 | 1.25 (30px) | Главный заголовок страницы (H1), hero |

### Дополнительные правила

- Основной текст страниц — `base` (16px), цвет `--color-text-primary`
- Вспомогательный текст — `sm` (14px), цвет `--color-text-secondary`
- Help-текст под полями формы — `xs` (12px), цвет `--color-text-secondary`
- Ошибки валидации под полями — `xs` (12px), цвет `--color-danger`
- Заголовок страницы — `xl` или `2xl`, weight SemiBold
- Заголовок Dialog — `lg`, weight SemiBold

---

## 3. Spacing Scale

Единица сетки: 4px. Все отступы кратны 4px.

| Токен | CSS-переменная | px | Tailwind | Применение |
|---|---|---|---|---|
| space-1 | `--space-1` | 4 | `p-1`, `gap-1` | Отступ внутри Badge, иконки рядом с текстом |
| space-2 | `--space-2` | 8 | `p-2`, `gap-2` | Отступ внутри маленьких кнопок, padding иконки-кнопки |
| space-3 | `--space-3` | 12 | `p-3`, `gap-3` | Padding input (vertical), gap в тулбаре |
| space-4 | `--space-4` | 16 | `p-4`, `gap-4` | Padding карточки (стандарт), gap между полями формы |
| space-6 | `--space-6` | 24 | `p-6`, `gap-6` | Padding секции внутри страницы, gap между секциями формы |
| space-8 | `--space-8` | 32 | `p-8`, `gap-8` | Padding страницы по вертикали |
| space-12 | `--space-12` | 48 | `p-12` | Отступ до/после крупных блоков |
| space-16 | `--space-16` | 64 | `p-16` | Горизонтальный padding основного контейнера (desktop) |

### Semantic spacing-токены

| CSS-переменная | Значение | Назначение |
|---|---|---|
| `--space-component-gap` | `var(--space-4)` | Отступ между элементами внутри компонента |
| `--space-section-gap` | `var(--space-6)` | Отступ между секциями |
| `--space-page-padding` | `var(--space-8)` | Внутренний padding страницы |

---

## 4. Shadow / Elevation

Три уровня подъёма поверхности. Используются CSS `box-shadow`.

| Уровень | CSS-переменная | Значение | Применение |
|---|---|---|---|
| sm (1) | `--shadow-sm` | `0 1px 2px 0 rgb(0 0 0 / 0.05)` | Базовые карточки (Card), поля ввода, Badge |
| md (2) | `--shadow-md` | `0 4px 6px -1px rgb(0 0 0 / 0.07), 0 2px 4px -2px rgb(0 0 0 / 0.05)` | Dropdowns, Popover, тулбар |
| lg (3) | `--shadow-lg` | `0 10px 15px -3px rgb(0 0 0 / 0.08), 0 4px 6px -4px rgb(0 0 0 / 0.05)` | Dialog, Sheet, модальные окна |

**Правило применения:** каждый последующий уровень используется только для поверхностей, визуально расположенных выше предыдущего. Dialog всегда `shadow-lg`. Вложенные Dialog запрещены.

---

## 5. Компоненты

Все компоненты основаны на shadcn/ui + Radix primitives. Отклонение от этой базы требует отдельного обоснования.

### 5.1 Button

**shadcn/ui:** `Button`

| Вариант | CSS-класс (semantic) | Когда использовать |
|---|---|---|
| primary | `bg-[var(--color-primary)] text-[var(--color-text-on-primary)]` | Основное CTA-действие на экране. Один на экран/секцию. |
| secondary | `bg-[var(--color-surface)] border border-[var(--color-border)]` | Второстепенное действие рядом с primary. |
| ghost | `bg-transparent hover:bg-[var(--color-surface-raised)]` | Третичное действие, действия в таблице (Изменить, Удалить). |
| danger | `bg-[var(--color-danger)] text-white` | Необратимые действия: удаление, деактивация. |
| disabled | `opacity-50 cursor-not-allowed` | Кнопка недоступна (файловое хранилище M-OS-2 и пр.). |
| icon | квадратный, padding `space-2` | Иконка без текста. Обязателен `aria-label`. |

**Спецификация:**
- Размер по умолчанию: height 36px, padding horizontal `space-4`, font `text-sm`, weight Medium
- Минимальный touch-target: 44×44px (переменная `--touch-target-min`) для мобильного вида
- Состояния: default / hover / focus-visible (ring `--color-border-focused`) / active / disabled / loading (spinner + текст «Сохранение...»)
- Иконка внутри кнопки: размер 16px, gap `space-2` от текста
- Кнопка «Сохранить» в форме — всегда primary; «Отменить» — secondary или ghost

### 5.2 Input

**shadcn/ui:** `Input`, с оберткой `Form` + `Label` + `FormMessage`

**Спецификация:**
- Height: 36px
- Padding: `space-3` vertical, `space-4` horizontal
- Border: `1px solid var(--color-border)`, radius `radius-md` (6px)
- Font: `text-base` (16px) — критично для iOS, предотвращает zoom при фокусе
- Focus: border `var(--color-border-focused)`, ring `2px` того же цвета
- Error: border `var(--color-danger)`, подпись под полем `text-xs` красного цвета
- Disabled: `bg-[var(--color-surface-raised)]`, `cursor-not-allowed`, текст `--color-text-disabled`
- Help-текст под полем: `text-xs`, цвет `--color-text-secondary`, отступ `space-1` сверху
- Placeholder: цвет `--color-text-disabled`

**Состояния:** default / focus / filled / error / disabled

**Маппинг на wireframes:** все поля форм компаний (`ИНН`, `КПП`, `ОГРН`, `Расч. счёт`, `БИК` и пр.) — Input с Help-текстом под полем по образцу wireframe.

### 5.3 Select

**shadcn/ui:** `Select` (Radix SelectRoot + SelectTrigger + SelectContent)

**Спецификация:**
- Trigger: визуально идентичен Input — height 36px, border, padding, radius те же
- Иконка-стрелка: `ChevronDown` из Lucide, 16px, цвет `--color-text-secondary`
- Dropdown: `shadow-md`, radius `radius-lg` (8px), `bg-[var(--color-surface)]`
- Пункт списка: padding `space-2` vertical, `space-4` horizontal, hover `bg-[var(--color-surface-raised)]`
- Активный пункт: чекмарк `Check` 16px слева + жирный текст
- При >1000 элементов: обязательна виртуализация (см. ограничения shadcn)
- iOS Safari: не использовать Select внутри Dialog (известный баг первого открытия)

**Применение из wireframes:** `Тип компании (ООО/АО/ИП/ДРУГОЕ)`, `Валюта (RUB/USD/EUR)`, `Назначение счёта`, фильтры над таблицами.

### 5.4 Dialog

**shadcn/ui:** `Dialog` (DialogRoot + DialogContent + DialogHeader + DialogFooter)

**Спецификация:**
- Ширина: 480px по умолчанию, 560px для сложных форм (банковские реквизиты)
- Фон overlay: `rgba(0,0,0,0.5)`
- Shadow: `shadow-lg`
- Radius: `radius-xl` (12px)
- Padding: `space-6`
- Заголовок: `text-lg`, SemiBold
- Кнопка закрытия [×]: icon-button, `aria-label="Закрыть"`, `ghost`-вариант
- Footer: flex row, gap `space-3`, кнопка confirm — primary, cancel — secondary/ghost
- Запрещён вложенный Dialog в Dialog: использовать wizard или slide-over Sheet
- Не-блокирующие альтернативы: Sheet (для форм), Toast (для уведомлений)

**Применение из wireframes:** Dialog добавления банковского счёта, Dialog подтверждения удаления счёта, Dialog информационный («Хранилище в M-OS-2»), Dialog привязки роли к пользователю.

**Подтверждение необратимых действий:** в заголовке — «Удалить [название объекта]?», в теле — конкретное следствие, кнопка danger — «Удалить», кнопка cancel — «Отменить».

### 5.5 Table (MOSTable)

**shadcn/ui:** собирается из `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableCell`, wrapped в `MOSTable` — единый компонент в `shared/ui/`

**Спецификация:**
- Row height (Regular): 56px — принят как единый режим для Admin UI MVP
- Header: `text-xs` SemiBold, `--color-text-secondary`, `bg-[var(--color-surface-raised)]`, border-bottom `--color-border`
- Body row: `text-sm`, чередование `bg-[var(--color-surface)]`, hover `bg-[var(--color-surface-raised)]`
- Неактивная строка (например, компания «Неактивна»): `opacity-60`, `--color-text-secondary`
- Строка кликабельна целиком: `cursor-pointer`
- Скелетон-загрузка: 3–5 строк shimmer-анимации `pulse` (из Tailwind `animate-pulse`)
- Empty state: иконка + текст «[Объекты] ещё не добавлены» + CTA-кнопка
- Error state: Banner над таблицей с кнопкой «Повторить»
- Максимум без виртуализации: ~200 строк; свыше 500 — `@tanstack/react-virtual`
- Mobile (Telegram WebApp): card-view как альтернатива

**Маппинг из wireframes:** таблица компаний (5 колонок), таблица пользователей, таблица ролей, sub-таблица банковских реквизитов, permissions matrix.

### 5.6 Card

**shadcn/ui:** `Card`, `CardHeader`, `CardContent`, `CardFooter`

**Спецификация:**
- Background: `bg-[var(--color-surface)]`
- Border: `1px solid var(--color-border)`
- Shadow: `shadow-sm`
- Radius: `radius-lg` (8px)
- Padding: `space-6`
- Применение: карточки дашборда, панели с реквизитами, виджеты статистики

---

## 6. Иконки

**Библиотека:** `lucide-react` — единственная допустимая. Кастомные иконки сверх Lucide добавляются с согласования design-director.

| Размер | px | Использование |
|---|---|---|
| sm | 16 | Иконки внутри кнопок, badge, поля ввода (стрелка Select), чекмарки |
| md | 20 | Иконки в пунктах меню Sidebar, вспомогательные иконки в тексте |
| lg | 24 | Иконки в заголовках, empty state, крупные статусные индикаторы |

**Правила применения:**
- Любая иконка без текстовой подписи обязана иметь `aria-label` (accessibility-блокер)
- Иконки статусов (success/warning/danger/info): всегда рядом с текстом — принцип «не только цвет»
- Рекомендованные иконки для статусов: `CheckCircle2` (success), `AlertTriangle` (warning), `XCircle` (danger), `Info` (info)
- Иконки действий в таблицах: `Pencil` (Изменить), `Trash2` (Удалить), `ChevronRight` (Перейти)
- Spinner (loading): `Loader2` с `animate-spin`, размер 16px внутри кнопки

---

## 7. Токены как CSS Variables и Tailwind Config

### 7.1 CSS Custom Properties (`:root`)

Все токены объявляются в `:root` глобального CSS. Это позволяет runtime-замену brand per-company через JavaScript (`document.documentElement.style.setProperty`).

```css
/* Структура файла: src/styles/tokens.css */
:root {
  /* === ЦВЕТА === */
  --color-primary: #2563EB;
  --color-primary-hover: #1D4ED8;
  --color-primary-foreground: #FFFFFF;

  --color-background: #F1F5F9;
  --color-surface: #FFFFFF;
  --color-surface-raised: #F8FAFC;

  --color-border: #E2E8F0;
  --color-border-focused: #2563EB;

  --color-text-primary: #0F172A;
  --color-text-secondary: #64748B;
  --color-text-disabled: #94A3B8;
  --color-text-on-primary: #FFFFFF;

  /* Semantic states */
  --color-success: #16A34A;
  --color-success-bg: #F0FDF4;
  --color-success-border: #BBF7D0;

  --color-warning: #CA8A04;
  --color-warning-bg: #FEFCE8;
  --color-warning-border: #FDE047;

  --color-danger: #DC2626;
  --color-danger-hover: #B91C1C;
  --color-danger-bg: #FEF2F2;
  --color-danger-border: #FECACA;

  --color-info: #2563EB;
  --color-info-bg: #EFF6FF;
  --color-info-border: #BFDBFE;

  /* System states */
  --color-state-degraded: #EAB308;
  --color-state-partial: #F97316;
  --color-state-outage: #DC2626;
  --color-state-maintenance: #2563EB;
  --color-state-mismatch: #DC2626;

  /* Brand (runtime override) */
  --brand-primary: #2563EB;
  --brand-accent: #1D4ED8;
  --brand-logo-url: "";

  /* === ТИПОГРАФИКА === */
  --text-xs: 0.75rem;      /* 12px */
  --text-sm: 0.875rem;     /* 14px */
  --text-base: 1rem;       /* 16px */
  --text-lg: 1.125rem;     /* 18px */
  --text-xl: 1.25rem;      /* 20px */
  --text-2xl: 1.5rem;      /* 24px */

  /* === SPACING === */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-6: 24px;
  --space-8: 32px;
  --space-12: 48px;
  --space-16: 64px;

  /* Semantic spacing */
  --space-component-gap: var(--space-4);
  --space-section-gap: var(--space-6);
  --space-page-padding: var(--space-8);

  /* === SHADOWS === */
  --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
  --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.07), 0 2px 4px -2px rgb(0 0 0 / 0.05);
  --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.08), 0 4px 6px -4px rgb(0 0 0 / 0.05);

  /* === ПРОЧЕЕ === */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
  --radius-xl: 12px;

  --touch-target-min: 44px;

  /* PWA safe area */
  --safe-area-inset-top: env(safe-area-inset-top, 0px);
  --safe-area-inset-bottom: env(safe-area-inset-bottom, 0px);
}
```

### 7.2 Tailwind Config

Конфигурация расширяет базовую тему Tailwind v3.4, добавляя semantic-алиасы через `var(--...)`. Frontend-разработчики используют Tailwind-классы, которые под капотом ссылаются на CSS-переменные.

```js
// Структура: tailwind.config.js — секция theme.extend
// Не пишите фронт-код сюда — ниже только спецификация значений

theme: {
  extend: {
    colors: {
      primary: {
        DEFAULT: 'var(--color-primary)',
        hover: 'var(--color-primary-hover)',
        foreground: 'var(--color-primary-foreground)',
      },
      background: 'var(--color-background)',
      surface: {
        DEFAULT: 'var(--color-surface)',
        raised: 'var(--color-surface-raised)',
      },
      border: {
        DEFAULT: 'var(--color-border)',
        focused: 'var(--color-border-focused)',
      },
      text: {
        primary: 'var(--color-text-primary)',
        secondary: 'var(--color-text-secondary)',
        disabled: 'var(--color-text-disabled)',
        'on-primary': 'var(--color-text-on-primary)',
      },
      success: {
        DEFAULT: 'var(--color-success)',
        bg: 'var(--color-success-bg)',
        border: 'var(--color-success-border)',
      },
      warning: {
        DEFAULT: 'var(--color-warning)',
        bg: 'var(--color-warning-bg)',
        border: 'var(--color-warning-border)',
      },
      danger: {
        DEFAULT: 'var(--color-danger)',
        hover: 'var(--color-danger-hover)',
        bg: 'var(--color-danger-bg)',
        border: 'var(--color-danger-border)',
      },
      info: {
        DEFAULT: 'var(--color-info)',
        bg: 'var(--color-info-bg)',
        border: 'var(--color-info-border)',
      },
    },
    fontSize: {
      xs:   ['var(--text-xs)',   { lineHeight: '1.5' }],
      sm:   ['var(--text-sm)',   { lineHeight: '1.5' }],
      base: ['var(--text-base)', { lineHeight: '1.5' }],
      lg:   ['var(--text-lg)',   { lineHeight: '1.4' }],
      xl:   ['var(--text-xl)',   { lineHeight: '1.3' }],
      '2xl':['var(--text-2xl)', { lineHeight: '1.25' }],
    },
    spacing: {
      1:  'var(--space-1)',
      2:  'var(--space-2)',
      3:  'var(--space-3)',
      4:  'var(--space-4)',
      6:  'var(--space-6)',
      8:  'var(--space-8)',
      12: 'var(--space-12)',
      16: 'var(--space-16)',
    },
    boxShadow: {
      sm: 'var(--shadow-sm)',
      md: 'var(--shadow-md)',
      lg: 'var(--shadow-lg)',
    },
    borderRadius: {
      sm: 'var(--radius-sm)',
      md: 'var(--radius-md)',
      lg: 'var(--radius-lg)',
      xl: 'var(--radius-xl)',
    },
  },
}
```

---

## Открытые вопросы (блокируют финализацию v1.0)

| # | Вопрос | Блокирует | Срок ответа |
|---|---|---|---|
| Q1 | Dark mode — M-OS-1 или M-OS-2? | Архитектуру токенов (нужен ли `color-scheme`) | RFC-006, 20–21 апр |
| Q2 | BPM-canvas: два визуальных языка или перетемизировать bpmn-js? | Токены для canvas-компонента | RFC-006 |
| Q3 | Brand colors per-company: 3 токена или больше? | `--brand-*` секцию | RFC-006 |
| Q4 | Data-density: один режим Regular (56px) или несколько? | Row height в Table | UI/UX axis, 22 апр |
| Q5 | Шрифт: Inter confirmed, или рассматриваем ещё варианты? | Секцию 2 | UI/UX axis |
| Q6 | Брендовые цвета холдинга: есть? Нужна AA-проверка до заведения | Palette section 1 | Владелец |

---

*Документ подготовлен design-director, 2026-04-18.*
*Источники: design-system-initiative.md v0.1, wireframes-m-os-1-1-admin.md v1.0.*
*Финал v1.0 — 25 апреля 2026 после RFC-006 и UI/UX axis.*
