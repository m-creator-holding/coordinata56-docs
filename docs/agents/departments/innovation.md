# Департамент инноваций и развития (Innovation & Strategy)

> **Тип:** core_department (постоянный, работает на все pods)
> **Статус:** ACTIVE с 2026-04-17
> **Директор:** innovation-director (Opus)
> **Создан:** по решению Владельца Telegram msg 1005, 2026-04-17

## Миссия

Мониторить рынок, конкурентов и технологии СНАРУЖИ. Генерировать идеи для развития M-OS как продукта. Еженедельно давать Владельцу Innovation Digest с конкретными предложениями.

## Отличие от R&I

| | R&I | Innovation |
|---|---|---|
| Смотрит на | AI-инструменты для агентов | Рынок и продукт |
| Потребитель | AI-команда | Владелец и бизнес |
| Выход | RFC/пилот инструмента | Innovation Brief / идея фичи |
| Источники | GitHub, Anthropic docs | Gartner, отраслевые СМИ, конкуренты |

## Состав

| Роль | Уровень | Модель | Статус |
|---|---|---|---|
| innovation-director | L2 | Opus | active |
| innovation-analyst | L3 | Opus | dormant |
| trend-scout | L4 | Sonnet | active |
| market-researcher | L4 | Sonnet | dormant |

## Процесс

1. **trend-scout** еженедельно сканирует источники → находки в `docs/innovation/findings.md`
2. **innovation-analyst** берёт топ-3 находки → пишет Innovation Brief
3. **innovation-director** приоритизирует → Innovation Digest Владельцу
4. **Владелец** решает: «внедряем / откладываем / нет»
5. Если «внедряем» → задача через Координатора уходит в соответствующий департамент

## Артефакты

- `docs/innovation/findings.md` — журнал находок
- `docs/innovation/briefs/` — Innovation Briefs (RFC-аналог)
- `docs/innovation/competitor-watch.md` — таблица конкурентов
- `docs/innovation/tech-radar.md` — Technology Radar (Adopt/Trial/Assess/Hold)
- `docs/innovation/board.md` — Innovation Board (топ-10 идей месяца)

## Источники мониторинга

### Строительная отрасль РФ
- erzrf.ru (Единый ресурс застройщиков)
- РБК Недвижимость
- CRE (Commercial Real Estate)

### ERP/SaaS мировой
- Gartner Magic Quadrant
- G2 Reviews
- ProductHunt

### AI в бизнесе
- a16z blog, Sequoia blog
- Y Combinator blog
- Anthropic blog, OpenAI blog

### Конкуренты прямые
- Procore, PlanRadar, Autodesk Construction Cloud
- 1С:Управление строительной организацией
- PetrolPlus, FuelCloud, Benzuber (АЗС)
- SAP S/4HANA, Oracle NetSuite, Odoo (ERP общий)

## Метрики

- Количество находок в неделю (цель: ≥5)
- Количество Innovation Briefs в месяц (цель: ≥2)
- Количество принятых идей (adopt/trial) в квартал
- Время от находки до решения Владельца
