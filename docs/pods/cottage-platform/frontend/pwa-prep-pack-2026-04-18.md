# PWA Prep Pack — M-OS-1 Cottage Platform

- **Дата**: 2026-04-18
- **Автор**: frontend-director (L2)
- **Статус**: draft — на согласование Координатора → Владельца
- **Скоуп**: фундамент PWA прораба под M-OS-1.3 (мягкий DoD по Решению 15: фундамент сейчас, закрытие к концу 1.4)
- **Основания**:
  - `docs/pods/cottage-platform/m-os-1-frontend-plan.md` §2.3, §3 (единый SPA + vite-plugin-pwa)
  - `docs/m-os-vision.md` §12 (PWA, не native; первый пилот — стройплощадка Координата 56)
  - Решение Владельца 9 — нотификации только Telegram, никаких browser push
  - Решение Владельца 10 — название приложения «M-OS | Коттеджи»
  - Решение Владельца 11 — триггерная активация `frontend-dev-2`
  - Решение Владельца 15 — «мягкий DoD»: PWA фундамент сразу, закрытие к концу 1.4
- **Выход пака**: этот файл. Код-шаблоны ниже — ready-to-paste для `frontend-dev`; они **не выполняются сейчас** и не коммитятся, пока Координатор не запустит исполнителя.

---

## 0. TL;DR для `frontend-dev` день 1

Цель первого дня — собрать PWA-скелет, чтобы на этапе 1.3 стройплощадка получила `display: standalone` и offline-фалбэк, **не переделывая архитектуру**.

Что делает разработчик:

1. Ставит `vite-plugin-pwa` (на Workbox под капотом) — см. §2.1.
2. Вшивает манифест — §1, шаблон ниже.
3. Настраивает SW через плагин — §2, стратегии указаны.
4. Кладёт `offline.html` — §4, шаблон ниже.
5. Иконки — placeholder SVG-путь из `favicon.svg` генерирует через `pwa-assets-generator` (либо временные заглушки, см. §3).
6. Прогоняет Lighthouse локально против `vite preview` — §5, целевой бейзлайн.

Что **не** делает:

- Не включает SW в dev-режиме (конфликт с MSW `mockServiceWorker.js`).
- Не добавляет Web Push / Notifications API (Telegram-only по Решению 9).
- Не трогает `/field/*` pages — они придут в 1.3.

---

## 1. Web App Manifest

### 1.1 Решения

| Поле | Значение | Обоснование |
|---|---|---|
| `name` | `M-OS | Коттеджи` | Решение 10 |
| `short_name` | `M-OS Коттеджи` | ≤12 символов для homescreen-бейджа |
| `description` | `Рабочее место прораба и офиса коттеджного посёлка` | RU-only (Решение 9) |
| `lang` | `ru` | RU-only |
| `dir` | `ltr` | — |
| `display` | `standalone` | plan §2.3 — «выглядит как приложение» |
| `display_override` | `["standalone", "minimal-ui"]` | на случай отказа OS от standalone |
| `orientation` | `portrait` | прораб работает одной рукой, телефон вертикально |
| `scope` | `/` | SPA c общими routes admin + field |
| `start_url` | `/?source=pwa` | UTM-метка, чтобы метрика в §6 видела PWA-заходы |
| `id` | `/m-os-cottages` | фиксируем идентичность приложения для браузера |
| `theme_color` | `#0F172A` | `hsl(222.2 47.4% 11.2%)` = текущая `--primary` в `src/index.css` (slate-900). Статус-бар телефона покрасится в этот цвет |
| `background_color` | `#FFFFFF` | `hsl(0 0% 100%)` = текущая `--background` (light theme). Splash-screen на старте |
| `categories` | `["business", "productivity"]` | для магазинов/homescreen |
| `prefer_related_applications` | `false` | нет native-аналога |

**Согласование с дизайном**: `designer` пока выдал только wireframes (`docs/pods/cottage-platform/design/`), полноценного brand book нет. Беру текущие CSS-переменные из `src/index.css` как источник истины; когда дизайн выдаст финальную палитру — обновляем два поля (`theme_color`, `background_color`) и перевыпускаем иконки. Это дешёвая операция: одна правка в `vite.config.ts` + `pwa-assets` переген.

### 1.2 Шаблон файла

Файл: `frontend/public/manifest.webmanifest` (положит `vite-plugin-pwa` сам по §2.1, но для референса — канонический JSON):

```json
{
  "name": "M-OS | Коттеджи",
  "short_name": "M-OS Коттеджи",
  "description": "Рабочее место прораба и офиса коттеджного посёлка",
  "lang": "ru",
  "dir": "ltr",
  "display": "standalone",
  "display_override": ["standalone", "minimal-ui"],
  "orientation": "portrait",
  "scope": "/",
  "start_url": "/?source=pwa",
  "id": "/m-os-cottages",
  "theme_color": "#0F172A",
  "background_color": "#FFFFFF",
  "categories": ["business", "productivity"],
  "prefer_related_applications": false,
  "icons": [
    { "src": "/icons/pwa-192x192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/pwa-512x512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/pwa-maskable-192x192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/icons/pwa-maskable-512x512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" },
    { "src": "/icons/apple-touch-icon.png", "sizes": "180x180", "type": "image/png", "purpose": "any" }
  ]
}
```

Примечание: в финале манифест генерируется плагином из `VitePWA({ manifest: {...} })` и попадает в `dist/manifest.webmanifest`. Ручной файл в `public/` **не кладём** — иначе будет два источника истины.

### 1.3 Правки `index.html`

Текущий `frontend/index.html` имеет только `<link rel="icon">`. Добавить перед закрывающим `</head>`:

```html
<meta name="theme-color" content="#0F172A" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="M-OS Коттеджи" />
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png" />
<!-- manifest link будет инжектирован vite-plugin-pwa автоматически -->
```

---

## 2. Service Worker — скелет через `vite-plugin-pwa`

### 2.1 Почему плагин, а не ручной SW

- План §3.2 уже зафиксировал `vite-plugin-pwa` (Workbox под капотом) как стандарт для Vite-стека. Не меняю.
- Engineering principle «сначала простота»: плагин даёт precache + runtime-кеш + авто-регистрацию в 50 строк конфига. Ручной SW — 200+ строк и ручная поддержка версионности precache manifest.
- Плагин уже умеет `injectManifest` при необходимости перейти на кастомную логику — миграция без переписывания.

### 2.2 Критическая развилка: MSW vs PWA SW в dev

`frontend/public/mockServiceWorker.js` уже занят MSW для мок-API. Оба SW не могут одновременно жить на одном scope. Решение:

- `VitePWA({ devOptions: { enabled: false } })` — PWA SW включается **только в production build** (`vite build`).
- В dev-режиме (`vite dev`) работает только MSW.
- Проверка PWA делается через `npm run build && npm run preview` на `http://localhost:4173/`.

Это явно документируем в `frontend/README.md` отдельным блоком «PWA: как тестировать локально».

### 2.3 Конфигурация `vite.config.ts` — шаблон

```typescript
import path from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      // prod-only, чтобы не конфликтовать с MSW в dev
      devOptions: { enabled: false },
      registerType: 'autoUpdate', // проверка обновлений при каждой навигации
      injectRegister: 'auto',
      strategies: 'generateSW', // Workbox-генерация; на injectManifest перейдём при надобности
      manifest: {
        name: 'M-OS | Коттеджи',
        short_name: 'M-OS Коттеджи',
        description: 'Рабочее место прораба и офиса коттеджного посёлка',
        lang: 'ru',
        dir: 'ltr',
        display: 'standalone',
        display_override: ['standalone', 'minimal-ui'],
        orientation: 'portrait',
        scope: '/',
        start_url: '/?source=pwa',
        id: '/m-os-cottages',
        theme_color: '#0F172A',
        background_color: '#FFFFFF',
        categories: ['business', 'productivity'],
        icons: [
          { src: '/icons/pwa-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icons/pwa-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/icons/pwa-maskable-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: '/icons/pwa-maskable-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // app-shell precache
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        navigateFallback: '/offline.html',
        navigateFallbackDenylist: [/^\/api\//, /^\/docs/], // API и backend-docs не попадают под fallback
        cleanupOutdatedCaches: true,
        clientsClaim: true,
        skipWaiting: false, // НЕ skipWaiting — показываем пользователю тост «Доступна новая версия»
        runtimeCaching: [
          {
            // API: network-first, короткий timeout, затем кеш на 24 часа
            urlPattern: ({ url }) => url.pathname.startsWith('/api/'),
            handler: 'NetworkFirst',
            options: {
              cacheName: 'api-cache-v1',
              networkTimeoutSeconds: 5,
              expiration: { maxEntries: 200, maxAgeSeconds: 60 * 60 * 24 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
          {
            // Картинки из backend/assets: cache-first
            urlPattern: ({ request }) => request.destination === 'image',
            handler: 'CacheFirst',
            options: {
              cacheName: 'image-cache-v1',
              expiration: { maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 30 },
            },
          },
          {
            // Шрифты / fonts.googleapis.com если подключим
            urlPattern: ({ request }) => request.destination === 'font',
            handler: 'CacheFirst',
            options: {
              cacheName: 'font-cache-v1',
              expiration: { maxEntries: 20, maxAgeSeconds: 60 * 60 * 24 * 365 },
            },
          },
        ],
      },
    }),
  ],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: process.env.VITE_API_URL ?? 'http://localhost:8000', changeOrigin: true },
    },
  },
})
```

### 2.4 Update-flow в приложении — шаблон React-хука

Файл: `frontend/src/pwa/useRegisterSW.ts` (новый каталог `src/pwa/`).

```typescript
import { useEffect, useState } from 'react'
import { registerSW } from 'virtual:pwa-register'

export function useRegisterSW() {
  const [needRefresh, setNeedRefresh] = useState(false)
  const [offlineReady, setOfflineReady] = useState(false)

  useEffect(() => {
    const updateSW = registerSW({
      onNeedRefresh() {
        setNeedRefresh(true)
      },
      onOfflineReady() {
        setOfflineReady(true)
      },
      onRegisterError(error) {
        console.error('SW register error', error)
      },
    })

    // сохранить глобально, чтобы тост из UI мог вызвать updateSW(true)
    ;(window as unknown as { __updateSW?: (reload: boolean) => Promise<void> }).__updateSW = updateSW
  }, [])

  return { needRefresh, offlineReady }
}
```

Интеграция в `App.tsx` (добавить — не переписывать):

```typescript
// в верхушке App.tsx
import { useRegisterSW } from '@/pwa/useRegisterSW'
import { toast } from 'sonner'

function App() {
  const { needRefresh } = useRegisterSW()

  useEffect(() => {
    if (needRefresh) {
      toast('Доступна новая версия', {
        duration: Infinity,
        action: {
          label: 'Обновить',
          onClick: () => (window as unknown as { __updateSW: (r: boolean) => void }).__updateSW(true),
        },
      })
    }
  }, [needRefresh])
  // ... остальной App.tsx без изменений
}
```

Sonner уже в зависимостях (`package.json:46`) — новых либ не тащим.

### 2.5 TypeScript-типы для virtual-модуля

В `src/vite-env.d.ts` добавить:

```typescript
/// <reference types="vite-plugin-pwa/client" />
```

### 2.6 Что SW **не делает** (намеренно)

- Не подписывается на `PushEvent` — push-нотификаций нет (Решение 9, Telegram-only).
- Не подписывается на `SyncEvent` — background sync отложен до 1.3 (там appear'ится очередь мутаций в IDB).
- Не вмешивается в `/api/auth/*` — network-first уже корректно отдаёт 401 без кеша (MSW/реальный backend возвращают их свежими).

---

## 3. Иконки

### 3.1 Что нужно

| Файл | Размер | Назначение |
|---|---|---|
| `public/icons/pwa-192x192.png` | 192×192 | Android homescreen `any` |
| `public/icons/pwa-512x512.png` | 512×512 | Android splash, Chrome install |
| `public/icons/pwa-maskable-192x192.png` | 192×192 | Android adaptive icon (safe-area 80%) |
| `public/icons/pwa-maskable-512x512.png` | 512×512 | то же, HD |
| `public/icons/apple-touch-icon.png` | 180×180 | iOS homescreen |
| `public/favicon-32x32.png` | 32×32 | браузерная вкладка (опц., у нас уже есть SVG) |

**Маскируемые иконки** (`purpose: "maskable"`) — с запасом 20% по периметру, чтобы Android мог обрезать под свою форму (круг/squircle). Без них homescreen покажет белую рамку.

### 3.2 Стратегия на сейчас — placeholder

Полноценного brand book нет (`design/` содержит только wireframes M-OS-1.1B). Два варианта:

**Вариант A — автогенерация из текущего SVG (рекомендую).**
- Использовать `@vite-pwa/assets-generator` — один конфиг-файл, один npm-скрипт.
- Исходник — `public/favicon.svg` (уже лежит; проверил).
- Команда: `npx pwa-assets-generator --preset minimal-2023 public/favicon.svg`.
- Генерирует весь набор выше за 3 секунды.
- Минус: визуал бедный, пока не переделает `designer`.
- Плюс: не блокирует старт PWA-работ.

**Вариант B — ждать designer'а.**
- Просим `designer` выдать:
  1. Мастер-логотип 1024×1024 SVG (или PNG).
  2. Маскируемую версию с safe-area 80%.
- Срок: 2–3 дня работы дизайнера.
- Блокирует: запуск PWA precache (без иконок манифест валидный, но Lighthouse штрафует).

**Рекомендация**: **Вариант A сейчас** + тикет `designer`'у на финальный логотип с дедлайном «до конца M-OS-1.3». При готовности — замена через `npx pwa-assets-generator` + `npm run build`. Это 10-минутная операция, не архитектурное изменение.

### 3.3 Шаблон `pwa-assets.config.ts` (для Варианта A)

```typescript
import { defineConfig, minimal2023Preset } from '@vite-pwa/assets-generator/config'

export default defineConfig({
  preset: {
    ...minimal2023Preset,
    maskable: {
      ...minimal2023Preset.maskable,
      padding: 0.2, // 20% safe-area
      resizeOptions: { background: '#0F172A', fit: 'contain' },
    },
    apple: {
      ...minimal2023Preset.apple,
      resizeOptions: { background: '#FFFFFF', fit: 'contain' },
    },
  },
  images: ['public/favicon.svg'],
})
```

Добавить в `package.json` scripts:

```json
"pwa:assets": "pwa-assets-generator"
```

### 3.4 Бриф для `designer` (опционально, параллельно)

- Мастер-логотип «M-OS | Коттеджи» 1024×1024 SVG, без текста (символ).
- Маскируемая версия с 80%-safe-area.
- Splash фон `#FFFFFF`, символ по центру, окантовка монохромная.
- Формат выдачи: положить `.svg` в `docs/pods/cottage-platform/design/brand/` и отметить в `frontend/README.md`.

---

## 4. Offline fallback page

Файл: `frontend/public/offline.html`. Статика, не проходит через React. Плагин `VitePWA` кладёт её в precache и отдаёт при `navigateFallback`.

```html
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#0F172A" />
    <title>Нет связи — M-OS | Коттеджи</title>
    <style>
      :root { color-scheme: light; }
      * { box-sizing: border-box; }
      html, body { margin: 0; padding: 0; height: 100%; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        background: #FFFFFF;
        color: #0F172A;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }
      .card { max-width: 420px; text-align: center; }
      .brand { font-size: 14px; letter-spacing: 0.08em; text-transform: uppercase; color: #64748B; margin-bottom: 24px; }
      h1 { font-size: 28px; margin: 0 0 12px; font-weight: 600; }
      p { font-size: 16px; line-height: 1.5; color: #475569; margin: 0 0 24px; }
      button {
        background: #0F172A; color: #FFFFFF; border: none;
        padding: 14px 28px; border-radius: 10px; font-size: 16px; font-weight: 500;
        cursor: pointer; min-height: 48px; min-width: 160px;
      }
      button:active { opacity: 0.8; }
      .hint { margin-top: 20px; font-size: 13px; color: #94A3B8; }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="brand">M-OS | Коттеджи</div>
      <h1>Нет связи</h1>
      <p>Устройство потеряло соединение с сервером. Отправленные сейчас действия сохранятся в очереди и уйдут, как только сеть восстановится.</p>
      <button onclick="location.reload()">Попробовать снова</button>
      <div class="hint">Если проблема не уходит — сообщите в Telegram-бот</div>
    </main>
    <script>
      window.addEventListener('online', () => location.reload())
    </script>
  </body>
</html>
```

Замечания:

- Минимум inline-CSS, без зависимостей от bundle — страница обязана работать, когда бандл недоступен.
- Крупный таргет `button min-height: 48px` — поле, перчатки, Fitts' law.
- Авто-релоад при `online` — пользователь не перезагружает руками.
- Копирайт и версия не нужны — страница аварийная.

---

## 5. Lighthouse baseline

### 5.1 Цели

| Категория | Целевой балл |
|---|---|
| PWA | ≥ 90 |
| Performance | ≥ 80 |
| Accessibility | ≥ 90 |
| Best Practices | ≥ 90 |
| SEO | ≥ 80 (внутренняя система, SEO не критичен) |

### 5.2 Как измерять

- **Локально** (разработчик): `npm run build && npm run preview`, затем Chrome DevTools → Lighthouse → Mobile + Simulated throttling, 3 прогона подряд, берём медиану.
- **Регрессия**: добавить в CI job `lighthouse-ci` (отдельная задача для `frontend-head` — не сейчас, но шаблон ниже).
- **Производственная**: `@lhci/cli` против prod URL раз в день.

### 5.3 Шаблон `lighthouserc.json` (для будущей CI-задачи)

```json
{
  "ci": {
    "collect": {
      "staticDistDir": "./frontend/dist",
      "url": ["http://localhost/", "http://localhost/admin"],
      "numberOfRuns": 3,
      "settings": { "preset": "mobile" }
    },
    "assert": {
      "assertions": {
        "categories:pwa": ["error", { "minScore": 0.9 }],
        "categories:performance": ["warn", { "minScore": 0.8 }],
        "categories:accessibility": ["error", { "minScore": 0.9 }],
        "categories:best-practices": ["warn", { "minScore": 0.9 }]
      }
    }
  }
}
```

### 5.4 Что даст эти баллы

- PWA ≥ 90: манифест + SW + offline.html + theme-color + apple meta-tags — всё есть в паке. Единственная дыра — иконки: если не сгенерированы, штраф 10 пунктов.
- Performance ≥ 80: Vite-код-сплит (уже есть), Workbox precache app-shell (первая загрузка медленная, повторные мгновенные), lazy-chunk admin vs field (в плане §3).
- Accessibility ≥ 90: shadcn/ui (Radix под капотом) даёт ARIA из коробки, `<html lang="ru">` уже проставлен.

---

## 6. Метрика для Решения 11 — триггер активации `frontend-dev-2`

### 6.1 Проблема

Решение 11: если на 2-й неделе M-OS-1.3 отставание от плана >30% — активировать второго `frontend-dev`. Нужен объективный измеритель «отставания», который не зависит от субъективного «чувствую, что не успеваем».

### 6.2 Предложение — две метрики, обе должны проверяться в контрольный день

**Метрика 1 (основная): Story Points Burndown Ratio (SPBR).**

- В начале M-OS-1.3 `frontend-head` декомпозирует скоуп на US и проставляет каждой оценку в story-points (1/2/3/5/8 по Fibonacci). Суммарно получаем `total_sp`.
- План равномерного сгорания: за 2 недели ожидаемая линия идёт от `total_sp` до `0`, контрольная точка конец недели 1 — должно остаться `≤ 0.5 × total_sp`.
- Фактический замер в конце недели 1: `remaining_sp_week1` = сумма SP по US со статусом ≠ `done` и ≠ `in_review`.
- `SPBR = remaining_sp_week1 / total_sp`.
- **Триггер**: `SPBR > 0.70` (осталось >70% работы после недели 1) = отставание >30% (сгорело <30% вместо запланированных 50%). Активируем `frontend-dev-2`.

Почему SP, а не количество US: разные US весят разное, грубый counter даёт ложные сигналы при «выпиливании» мелочи в обход крупных задач. Fibonacci-оценка уже ставится `frontend-head` на kickoff.

**Метрика 2 (контроль-чек): Lead Time Outlier Count (LTOC).**

- Для каждой закрытой (`done`) US считается lead time = время от `in_progress` до `done` (в рабочих днях).
- В M-OS-1.3 принимаем baseline lead time = 1.5 рабочих дня на US среднего размера (3 SP).
- LTOC = количество US с lead time > 3 дней на US за первую неделю.
- **Триггер**: `LTOC ≥ 3` — либо задачи плохо декомпозированы (слишком крупные), либо один разработчик забивается. В обоих случаях второй разработчик снимает часть нагрузки.

### 6.3 Как измерять без GitHub Projects / Jira

MVP не имеет трекера. Решение: живой реестр — `docs/pods/cottage-platform/frontend/m-os-1-3-burndown.md` — табличка US × status × SP × timestamp_start × timestamp_done. Заполняется `frontend-head` вручную по итогам daily stand-up (15 мин, отчёт в Координатор). В пятницу недели 1 Координатор смотрит две цифры, применяет оба триггера.

Если либо SPBR >0.70, либо LTOC ≥ 3 — активация `frontend-dev-2`. Если обе в норме — продолжаем текущим составом.

### 6.4 Почему этого достаточно

- Объективно: числа, не ощущения.
- Дёшево: одна `.md` таблица, 5 минут в пятницу.
- Робастно: две независимые метрики снижают риск единичного артефакта (например, один большой US застрял на ревью — LTOC выстрелит, SPBR может выглядеть нормально).
- Контрпример к «просто смотреть закрытые PR»: PR-счётчик поощряет дробить ради счётчика, а не ради прогресса.

---

## 7. Чеклист для `frontend-dev` (acceptance-критерий пака)

День 1 закрыт, если:

- [ ] Установлены `vite-plugin-pwa` и `@vite-pwa/assets-generator`.
- [ ] `vite.config.ts` содержит `VitePWA({...})` из §2.3, `devOptions.enabled: false`.
- [ ] `frontend/public/offline.html` существует, открывается напрямую в браузере (без SW), выглядит как в §4.
- [ ] Иконки сгенерированы через `npm run pwa:assets`, лежат в `public/icons/`.
- [ ] `frontend/index.html` содержит meta-теги PWA из §1.3.
- [ ] `src/pwa/useRegisterSW.ts` создан.
- [ ] `src/vite-env.d.ts` содержит triple-slash reference на `vite-plugin-pwa/client`.
- [ ] `npm run build` проходит без ошибок.
- [ ] `npm run preview` отдаёт `dist/manifest.webmanifest` по `/manifest.webmanifest`.
- [ ] Lighthouse на `preview` даёт PWA ≥ 90.
- [ ] `frontend/README.md` дополнен секцией «PWA: как тестировать локально» (3 строки: build → preview → Lighthouse).
- [ ] Dev-режим (`npm run dev`) работает как раньше, MSW мокает `/api/*`, SW не регистрируется (проверка: `navigator.serviceWorker.controller === null` в dev-консоли).

---

## 8. Риски и mitigations

| Риск | Вероятность | Mitigation |
|---|---|---|
| MSW и PWA SW конфликтуют в dev | высокая без меры | `devOptions.enabled: false` + явный тест в чеклисте |
| iOS Safari не поддерживает часть Workbox API | средняя | `strategies: 'generateSW'` выдаёт только стандартное API (Cache + Fetch), без Background Sync. Safari 16+ ок |
| Иконки-плейсхолдеры ухудшат восприятие приложения у Владельца | средняя | Явная метка в Telegram-демо: «иконки временные, финал от `designer` к концу 1.3» |
| `theme_color` разойдётся с финальной палитрой дизайна | высокая | Захардкожено в одном месте (`vite.config.ts`), перевыпуск иконок 10 минут |
| Пользователь «застревает» на старой версии PWA из-за `skipWaiting: false` | низкая | Тост «Доступна новая версия» с явной кнопкой; если не нажмёт — при следующей навигации Workbox всё равно активирует новую версию |
| SW кеширует 401/500 ошибки API | средняя | В runtimeCaching только `statuses: [0, 200]` для api-cache-v1 |

---

## 9. Что отдаётся Координатору

- Этот файл — `docs/pods/cottage-platform/frontend/pwa-prep-pack-2026-04-18.md`.
- Никаких правок в `frontend/` **не сделано** (ограничение задачи).
- Когда Координатор запустит `frontend-dev` с этим паком — исполнитель получает в prompt:
  - ссылку на этот документ;
  - `FILES_ALLOWED`: `frontend/vite.config.ts`, `frontend/index.html`, `frontend/package.json`, `frontend/pwa-assets.config.ts` (новый), `frontend/src/vite-env.d.ts`, `frontend/src/pwa/useRegisterSW.ts` (новый), `frontend/src/App.tsx`, `frontend/public/offline.html` (новый), `frontend/public/icons/*` (новые), `frontend/README.md`;
  - acceptance — чеклист §7.
- Оценка исполнения: 0.5–1 рабочий день (фундамент, без UI-интеграции в конкретные страницы).

---

## Приложение A. Принятые компромиссы

1. **Workbox + generateSW**, не кастомный SW. При необходимости тонкой настройки (например, IDB-очередь мутаций в 1.3) — переход на `strategies: 'injectManifest'` без потери прод-готовности.
2. **`skipWaiting: false`**, не `true`. Пользователь может потерять незавершённую форму при мгновенной замене — лучше тост.
3. **`clientsClaim: true`**: первый визит нового SW сразу берёт управление всеми вкладками. Это ок для внутренней системы, где пользователь обычно в одной вкладке.
4. **Placeholder-иконки через автогенератор** вместо блокировки PWA-работы ожиданием дизайн-комплекта.
5. **Русский only в offline.html** — hardcoded. Когда появится i18n-инфра (Phase M-OS-2+), переводим в data-атрибут + переключатель. Сейчас лишний.
