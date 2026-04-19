# Input от infra-director — Design System Initiative

**Дата:** 2026-04-18
**От:** infra-director
**Тема:** Производительность и observability UI

## Контекст

- M-OS — внутреннее ПО холдинга, не публичный сайт. Десятки одновременных пользователей.
- Точка доступа: Telegram WebApp + Admin UI (браузер).
- VPS 81.31.244.71, 16 GB RAM. Egress whitelist-only (нет CDN шрифтов снаружи).
- Канал: типично 4G/ШПД, пессимистично 3G (карьер в Оренбуржье).

## Критичные ограничения

### 1. Performance budget — реалистичный

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

**Для Telegram WebApp:**
- Initial bundle ≤ 150 KB gzip (регламент, не рекомендация)
- Всё остальное — lazy через `React.lazy` + Suspense
- Картинки только WebP/AVIF, `loading="lazy"` ниже fold

### 2. Шрифты

- **Self-hosted only** (Google Fonts / Yandex Fonts не гарантированы за egress whitelist)
- Максимум **2 семейства × 3 веса** (regular/medium/bold)
- Только **woff2**, `font-display: swap`, unicode-range для кириллицы

### 3. Картинки

- SVG для иконок/логотипов/схем (85 домов). Инлайн только <2 KB
- Растр — WebP основной, AVIF желателен
- Никаких фоновых hero-картинок на 1-2 MB

### 4. Сеть и API

- Gzip обязателен на nginx, brotli уровень 4 (не 11 — CPU дороже трафика)
- FastAPI `GZipMiddleware` для JSON
- Pagination envelope максимум 200 элементов (ADR 0006)
- Endpoint latency p95: read ≤ 200 мс, write ≤ 500 мс, report ≤ 2 с

### 5. Нет CDN — всё с VPS

- Версионирование через хэш в имени файла (Vite делает)
- HTML: `Cache-Control: no-cache`; JS/CSS/шрифты: `immutable, max-age=1 year`

## Observability UI

### 6. Только self-hosted, никаких SaaS

Ни Sentry.io, ни Datadog, ни LogRocket, ни Google Analytics (правило «никаких внешних интеграций»).

**Стек (отдельный docker-compose профиль):**
1. **GlitchTip** (Sentry-совместимый, ~500 MB RAM) для error tracking
2. **RUM** — endpoint `POST /api/telemetry/vitals`, таблица `ui_vitals_events`, ретеншн 30 дней, семплинг 10-20%
3. **Custom frontend logger** — обёртка для навигаций, медленных кликов, 5xx, JS-ошибок
4. **Live-dashboard** (текущий для субагентов) расширить разделом UI-метрик

**Инструментация:**
- `TelemetryProvider` в корне React
- Все ключевые компоненты (Button, Form, Dialog) автоматически репортят

### 7. Performance budget enforcement в CI

- `size-limit` или `bundlesize` — CI падает при превышении 150/200 KB gzip
- Lighthouse CI на preview-сборке — падает при LCP > 3 с или CLS > 0.15
- Ставить до разрастания design system, не после

## UI-индикаторы состояния системы

### 8. 6 состояний инфры, которые UI обязан показывать

| Состояние | Триггер | UI-индикатор |
|---|---|---|
| **Healthy** | Всё работает | Без маркеров |
| **Degraded** (slow) | p95 API > 2 с | Жёлтый баннер: «Система работает медленнее обычного» + «Подробнее» |
| **Partial outage** | Health-check модуля fail | Жёлто-оранжевый баннер: «Модуль X недоступен» + список работает/не работает |
| **Full outage** | >3 подряд 5xx/timeout | Красный fullscreen + «Попробуйте через минуту», кэшированные данные с меткой |
| **Maintenance** | Флаг в `/api/health` | Синий баннер: «Плановые работы до HH:MM» |
| **Version mismatch** | Фронт N+1, бэк N-1 | Красный модал: «Обновите страницу (Ctrl+Shift+R)» |

### 9. Offline-состояние

- Telegram WebApp на объекте — 3G с провалами, offline обязателен
- Оптимистичный UI + retry с экспоненциальной задержкой
- Баннер: «Нет связи. Изменения отправятся при восстановлении»
- Иконка часов/облака у кнопок «Сохранить» до синхронизации

### 10. Семантика индикаторов

- Различаться **не только цветом** (дальтоники, монохромные экраны на объектах). Иконки + текст
- Dismissible для некритичных (degraded, maintenance), non-dismissible для критичных (outage, version)
- Ссылка на `/status` страницу

## Возможности

- Bundle 150-200 KB gzip достижим без жертв (Radix tree-shakeable)
- Service Worker offline-кэш через `vite-plugin-pwa` + Workbox
- WebP/AVIF — nginx через `Accept: image/avif`
- HTTP/2 — включить сразу бесплатно

## Что поднять на инфра-уровне (1-2 недели devops+db+integrator)

1. nginx production-конфиг (gzip/brotli/cache/HTTP2)
2. GlitchTip в docker-compose
3. Endpoint `POST /api/telemetry/vitals` + таблица `ui_vitals_events`
4. `size-limit` + Lighthouse CI в GitHub Actions
5. Health-check `/api/health` с разбивкой по модулям

## Вопросы к design-director

1. **Разделение budget Admin UI / Telegram WebApp** — согласны?
2. **Тяжёлые компоненты в scope design** (Gantt, чертежи, видео, rich-text) — заранее договориться, что в lazy-чанках
3. **Палитра semantic states** (healthy/degraded/outage/maintenance) — 4 цвета + 4 иконки в токенах сразу
4. **Offline-режим в MVP или M-OS-2?** Если MVP — Service Worker проектируется сразу
5. **Шрифты — максимум 2 × 3** + кириллический сабсет, без латиницы кроме техэкранов
6. **Статус-страница `/status`** — дизайн чей?
7. **Telemetry consent** — нужно ли баннер «собираем web-vitals»? Для внутреннего ПО — вероятно нет, но legal подтвердит

---

*Источники: `docker-compose.yml`, `frontend/package.json`, `vite.config.ts`, M-OS Vision, M-OS-1 Decisions.*
