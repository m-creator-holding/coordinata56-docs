# Innovation Board — топ-10 идей месяца

> **Владелец:** innovation-director
> **Обновление:** ежемесячно (в первую неделю месяца) + после каждого market-scan
> **Последнее обновление:** 2026-04-18 (после Holding ERP Market Scan)
> **Связанные артефакты:** `docs/innovation/reports/`, `docs/innovation/findings.md`, `docs/innovation/competitor-watch.md`, `docs/innovation/tech-radar.md`

## Назначение

Board — живой список **топ-10 идей для M-OS, над которыми департамент инноваций работает прямо сейчас или предлагает Владельцу в ближайший Innovation Digest**. Каждая идея — с решением («в план / в backlog / отклонить»), владельцем (каким департаментом передать через Координатора), приоритетом и ссылкой на обоснование.

## Легенда статусов

- **в план** — Владелец одобрил, идея идёт в M-OS roadmap через Координатора
- **в backlog** — полезная, но не сейчас; вернёмся при триггере
- **отклонить** — проанализирована и не подходит, причина зафиксирована
- **на рассмотрение** — сформулирована, ждёт решения Владельца в следующем Digest'е

---

## Таблица

| # | Идея | Приоритет | Статус | Владелец направления | Источник | Триггер/Дата |
|---|---|---|---|---|---|---|
| 1 | **Приоритизировать 1С как №1 интеграцию в anti-corruption layer** (до банков и Росреестра): двусторонний обмен справочниками + КС-2/3/11/14 + проводки бухгалтерии | P1 | на рассмотрение | backend-director (через Координатора) | Market scan R2 | Перед kick-off M-OS-2 |
| 2 | **ADR по архитектуре AI-в-BPM** (фиксируем архитектурный дифференциатор «AI внутри процесса», не «AI поверх данных») | P1 | на рассмотрение | architect + backend-director + governance-director | Market scan R1 | До старта активной AI-разработки M-OS-2 |
| 3 | **Voice-to-form как killer-feature M-OS-2** (прораб в перчатках диктует дневной отчёт в PWA) | P1 | на рассмотрение | design-director + backend-director + frontend-director | Market scan R3; Findings #7 | M-OS-2 |
| 4 | **Privacy engineering как часть M-OS-1.1, не M-OS-2** (шифрование ПД at-rest, журнал доступа, механизм удаления по запросу) | P0 | в плане (идёт) | backend-director + legal + quality-director | Findings #9 (152-ФЗ оборотные штрафы); Market scan R4 | Закрыть до подключения живых данных |
| 5 | **Feature-mapping Odoo Construction vs cottage-pod** — Innovation Brief | P2 | в плане (департамент инноваций) | innovation-director → innovation-analyst | Market scan R5; Findings #6 | До 2026-05-15 |
| 6 | **Интерактивный график стройки с автофлагами сдвигов >10%** в cottage-pod (требование 214-ФЗ) | P1 | на рассмотрение | design-director + construction-expert + backend-director | Findings #10 | M-OS-1 cottage-pod (Фаза 4–9) |
| 7 | **IFC-viewer для BIM-интеграции в cottage-pod** (дифференциатор от 1С, требование 2026 г.) | P2 | на рассмотрение | design-director + backend-director | Findings #11; Market scan O-5 | M-OS-2 |
| 8 | **Photo-to-data OCR-конвейер для накладных поставщика** (пилот на 1 типе документа) | P1 | на рассмотрение | backend-director + design-director | Findings #3; Market scan (Procore Photo Intelligence bench) | M-OS-2 pilot |
| 9 | **Policy-bot** («могу ли я взять командировку N дней» → ответ по регламенту с цитатой) | P2 | на рассмотрение | backend-director + legal | Vision §4.2 Ж3; Findings #2 (SAP Joule референс) | M-OS-2 pilot |
| 10 | **Intel-voronka российских Voice AI провайдеров** (Yandex SpeechKit / Tinkoff Voice / Sber SaluteSpeech) — sensing-цикл | P2 | в плане (департамент инноваций) | innovation-director → trend-scout | Market scan R3 risk R-7 (voice AI на русском) | До начала дизайна voice-flow M-OS-2 |

---

## Из backlog'а (идеи, которые были рассмотрены ранее и отложены)

| Идея | Триггер возврата |
|---|---|
| No-code Agent Builder (как Procore) для M-OS | К старту M-OS-3, при зрелости нашего AI-в-BPM |
| AR для стройки (блок 8.7 vision) | M-OS-4+, при стабильности core |
| Computer vision на стройке | M-OS-4, параллельно начинать сбор видеоданных в M-OS-1 |
| White-label M-OS или отдельных pods для других холдингов | M-OS-5+, после валидации внутренней |
| Knowledge graph холдинга (Neo4j/ArangoDB) | M-OS-3, при накоплении 6+ мес operational data |
| Decision journals с автосверкой прогноз/факт | M-OS-3 |

---

## Отклонённые идеи (архив)

*Пока пусто — первая версия board'а. Отклонения будут приходить по мере углубления sensing-работы.*

---

## История обновлений board'а

| Дата | Событие |
|---|---|
| 2026-04-18 | Первая версия board'а. 10 идей из market-scan + findings #1. 1 P0 (уже в работе), 4 P1, 4 P2, 1 sensing-задача департамента |

