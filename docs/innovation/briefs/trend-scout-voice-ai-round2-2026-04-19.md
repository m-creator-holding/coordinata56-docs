# Brief для trend-scout — Voice AI Russia, Round 2 (дельта к baseline)

> **От:** innovation-director
> **Кому:** trend-scout (через Координатора)
> **Дата:** 2026-04-19
> **Тип задачи:** sensing delta (не полный deep-dive, а обновления)
> **Baseline:** `docs/innovation/briefs/voice-ai-russia-deep-dive-2026-04-18.md`
> **Срок:** 2–3 дня
> **Формат результата:** markdown-отчёт `docs/innovation/findings/voice-ai-russia-delta-2026-04-22.md`

---

## Контекст задачи

Ровно неделю назад (2026-04-18) закрыт baseline deep-dive по трём российским Voice AI провайдерам. Финалист — Yandex SpeechKit, резерв — Sber SaluteSpeech, Tinkoff — вне рассмотрения. За неделю в Digest #2 уже зафиксированы точечные сигналы (Sber снизил batch-тариф, Yandex анонсировал `yandex-gpt-speech`, Whisper-turbo). Нужно верифицировать эти сигналы и поймать всё остальное, что произошло за 7 дней.

**Это дельта к baseline, не повторный deep-dive.** Если ничего нового — короткий отчёт «подтверждаю baseline».

---

## Цели задачи (что искать)

### Блок 1 — Yandex SpeechKit (приоритет P0 в sensing)

Проверить на официальных публичных источниках:

- [ ] Есть ли **новый релиз v3.x** API за период 2026-04-12 … 2026-04-19? Источник: https://yandex.cloud/ru/docs/speechkit/release-notes
- [ ] Изменились ли **тарифы** на потоковое/асинхронное распознавание? Источник: https://yandex.cloud/ru/docs/speechkit/pricing
- [ ] Анонс **`yandex-gpt-speech`** (LLM+ASR совмещённая модель) — подтвердить существование, найти Public Statement, срок GA. Источник: блог Yandex.Cloud, Хабр-публикации Yandex.
- [ ] Обновления **Hybrid on-premise поставки** (enterprise): новые возможности, изменения цены.
- [ ] Обновления в **fine-tune docs** (cloud.yandex.ru/docs/speechkit/stt/additional-training): изменение требований к корпусу, новые возможности глоссария.

### Блок 2 — Sber SaluteSpeech (приоритет P1)

- [ ] **Верифицировать** снижение тарифа batch до 0,30 руб/мин (сигнал из Digest #2). Источник: https://developers.sber.ru/docs/ru/salutespeech/tariff
- [ ] Новые релизы API за неделю? Источник: https://developers.sber.ru/docs/ru/salutespeech/release-notes (если есть).
- [ ] Появились ли новые документы по **fine-tune / кастомный словарь**? Это слабое место Sber в baseline — любое улучшение меняет ландшафт.
- [ ] Партнёрские интеграции (Sber объявляет о них через `developers.sber.ru` и пресс-релизы).

### Блок 3 — Tinkoff VoiceKit (приоритет P3, контрольный)

- [ ] Любая активность на https://voicekit.tinkoff.ru/ и https://www.tbank.ru/software/voicekit/ за последние 7 дней.
- [ ] Цель — подтвердить статус «maintain mode», не продукт-обновлений. Если появилось что-то значимое — пересмотрим P3 → P1.

### Блок 4 — Open-source alternatives (приоритет P2, активный мониторинг)

- [ ] **Whisper-large-v3-turbo** — релизные ноты, точные benchmark-цифры на русском. Источники: https://github.com/openai/whisper/releases , Hugging Face model cards, HN/Reddit top-threads.
- [ ] **Whisper-large-v3-russian** (fine-tuned сообществом, antony66) — новые версии, WER-обновления. Источник: https://huggingface.co/antony66/whisper-large-v3-russian
- [ ] **Vosk 0.54 RU** — проверить публикацию Alpha Cephei на https://alphacephei.com/nsh/2025/04/18/russian-models.html (или аналогичные даты 2026). WER, лицензия, размер модели.
- [ ] Новые игроки: **NeMo (NVIDIA)**, **M2M-100**, русскоязычные форки — есть ли что-то с публичным релизом за неделю.

---

## Формат результата

Файл `docs/innovation/findings/voice-ai-russia-delta-2026-04-22.md` со структурой:

```
# Voice AI Russia — Delta to Baseline 2026-04-18

## 0. TL;DR (2-3 строки)
— Финалист остался / сменился: ...
— Резерв остался / сменился: ...
— Критичных сюрпризов: да/нет.

## 1. Yandex SpeechKit
| Что искали | Факт | Изменение vs baseline | Источник |
| ... | ... | ... | ... |

## 2. Sber SaluteSpeech
| Что искали | Факт | Изменение vs baseline | Источник |

## 3. Tinkoff VoiceKit
| Что искали | Факт | Изменение vs baseline | Источник |

## 4. Open-source (Whisper / Vosk / NeMo)
| Что искали | Факт | Изменение vs baseline | Источник |

## 5. Рекомендации innovation-director (тебе — на основе находок)
— Пересматривать ли финалиста? (да/нет + почему)
— Пересматривать ли резерв? (да/нет + почему)
— Поднимать ли OS в Trial? (да/нет + когда)

## 6. Source log
[пронумерованный список ссылок с датами обращения]
```

---

## Ограничения

- **Только публичные источники.** Никаких платных подписок, никаких «бесплатный триал чтобы посмотреть цены». Всё — на открытых страницах официальной документации, блогах, GitHub, Hugging Face, Хабр, Реддит.
- **Никаких живых вызовов API.** Не регистрировать аккаунты, не получать API-ключи, не делать тестовых запросов. Только чтение документации и release notes.
- **Если источник требует логина** (например, Sber Developer Portal за личным кабинетом) — отметить в отчёте «требует регистрации, пропущено», не регистрироваться.
- **Никаких поисковых запросов к неофициальным агрегаторам** (cnews обзоры, vc.ru рекламные статьи) без cross-verification с официальным источником.
- **Лимит 2–3 дня.** Если Блок 4 (open-source) затягивается — урезать до 1 проверки по Whisper-turbo, остальное — next round.

---

## Критерии приёмки

- [ ] Отчёт создан в `docs/innovation/findings/voice-ai-russia-delta-2026-04-22.md`
- [ ] Все 4 блока заполнены (даже если «изменений нет»)
- [ ] Для каждого факта — прямая ссылка на официальный источник и дата обращения
- [ ] TL;DR — не более 3 строк
- [ ] Рекомендации innovation-director — с чётким «да/нет/когда»
- [ ] Source log содержит все проверенные URL, даже те где «ничего не нашлось»

---

## Что будет дальше

После приёмки отчёта:
1. innovation-director сверяет дельту с Digest #2
2. Если финалист/резерв не меняются — обновляем Tech Radar, Voice-sensing переходит с weekly на monthly (см. P1 в Digest #2)
3. Если появились критичные изменения — escalate Координатору на включение в Digest #3

---

## Связь с регламентом

- **Tech Radar:** T1 (Trial) — обновляется по результатам этого sensing
- **Digest #2 Рекомендация #2 (P1):** «закрыть weekly voice-sensing после 1 мая» — этот sensing последний в weekly-режиме, дальше monthly
- **Принцип verify-before-scale** (feedback 2026-04-18 msg 1280): baseline проверен на 1 примере (финалист Yandex), round 2 — верификация перед переходом к действиям
- **CODE_OF_LAWS / No live external integrations:** sensing без API-вызовов, только документация

**Автор брифа:** innovation-director, 2026-04-19
