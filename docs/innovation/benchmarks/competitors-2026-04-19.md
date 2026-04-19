# Competitive Benchmark: Construction Management Software
**Дата:** 2026-04-19  
**Аналитик:** Market Researcher (субагент)  
**Фокус:** коттеджный девелопмент (coordinata56 MVP) + холдинг M-OS Vision (5 направлений)  
**Источники:** официальные сайты, G2/Capterra/GetApp/TrustRadius reviews, открытые case studies

---

## 1. Project Management (стадии, дедлайны, бюджеты)

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| Иерархия проектов (фазы/этапы/задачи) | Полная: Project → WBS → Tasks → RFIs/Submittals | Тикеты (задачи) привязаны к чертежу; Gantt есть, зависимости есть | Полный КС-план, этапы строительства, ресурсное планирование | Domain pod: project → stage → task; BPM через event bus | Procore сильнее по RFI/submittal workflow; **наш плюс** — BPM-движок со своими маршрутами под конкретный поселок |
| Бюджетирование план/факт | Детальный cost ledger; Change Orders; commitment tracking | Ограничено; нет глубокого бюджета; отчёты кастомизируются плохо | Сметы (ФЕР/ТЕР), бюджеты на ресурсы, план/факт по CW | Бюджет на уровне компании и объекта; payment_rule_snapshots | **Gap:** у нас пока нет change order workflow; **Opportunity:** зато интеграция с реальным банком по 214-ФЗ — out of box, чего нет ни у кого |
| Дедлайны и напоминания | Calendar + email + mobile push | Email + push | Email-уведомления, нет нативного push | Telegram-first уведомления прорабу и директору | **Advantage:** Telegram как канал — скорость доставки выше email, особенно в полевых условиях |
| Gantt и зависимости | Да, полный | Да, базовый | Да, через КС-план | Планируется в M-OS-1/2 | Нейтрально |

---

## 2. Multi-tenant / Multi-company (US-01)

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| Multi-company (разные юрлица) | Отдельные аккаунты на каждое юрлицо; переключение через навигацию; cross-account Procore Connect — ограниченный | Один аккаунт = одна компания; multi-org — только Enterprise; дорого | Один экземпляр может вести несколько организаций (особенность платформы 1С) | Per-company tenant с изоляцией данных и лимитами; 7 полей company_settings | **Gap у конкурентов:** Procore НЕ даёт единого холдингового дэшборда над 5 юрлицами без 5 отдельных контрактов. **Наш advantage:** M-OS = нативный холдинг, все 5 направлений в одном интерфейсе |
| Общий дэшборд холдинга | Нет (нужен Procore Analytics + доп. стоимость) | Нет | Да, если одна база 1С для всего холдинга | Да, запланировано как core feature M-OS | **Ключевое конкурентное преимущество для Мартина** |
| Per-company лимиты и изоляция | Нет | Нет | Частично (разграничение по организациям) | Да, архитектурно заложено в Wave 8 | Advantage |

---

## 3. RBAC (роли и матрица доступа)

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| Базовая модель | Read Only / Standard / Admin на двух уровнях (Company + Project) + role-based privileges + granular permissions | Роли по проекту; кастомизация ограничена | Роли 1С: администратор, менеджер, бухгалтер и т.д.; настраиваемые профили доступа | RBAC: Owner / Director / Manager / Foreman / Viewer; расширяемо через company_settings | Procore — самая гибкая матрица на рынке; наша модель проще, но достаточна для холдинга из 5 юрлиц |
| Permissions template | Да, глобальные и проектные шаблоны | Ограничено | Да, профили пользователей | Да, в roadmap M-OS-1 | Нейтрально |
| Одна роль на компанию | Не реализовано | Не реализовано | Не реализовано | Да (Wave 8, решение Владельца) | Упрощённая модель — наш сознательный выбор, не отставание |
| Audit log / история изменений | Да | Частично | Да (журнал регистрации 1С) | Планируется | Gap у нас; некритично для MVP |

---

## 4. Integrations: 1С, банки, ОФД, Росреестр

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| 1С | Нет нативной; сторонние коннекторы (remap, Aryza и др.) | Нет | Это и есть 1С; нативная синхронизация внутри экосистемы | Адаптер на полке (no live calls до production gate) | **Gap:** у Procore/PlanRadar 1С-интеграции нет вообще; у нас будет; это ключевой рынок РФ |
| Банковские платёжки (РФ) | Только США (Procore Pay, Silicon Valley Bank); RF-банки — нет | Нет интеграции с РФ-банками | Сбербанк, Точка, Тинькофф, Авангард, Модульбанк и др. — нативно | Адаптеры на полке (Сбер, Тинькофф) | **Advantage перед Procore/PlanRadar**: RF-банки поддерживаем, они — нет |
| ОФД (кассы, АЗС) | Нет | Нет | Да, через стандартные решения 1С (Первый ОФД, ОФД.ру, Платформа ОФД) | Адаптер на полке (для АЗС-направления) | Уникально для M-OS: АЗС + ОФД + единый дэшборд — нет ни у одного конкурента |
| Росреестр | Нет | Нет | Ограниченно, через сторонние сервисы | Адаптер на полке | Никто из конкурентов не интегрируется нативно; opportunity в девелопменте (регистрация ДДУ) |
| Telegram | Нет | Нет | Нет | Да, core channel (Telegram-first архитектура) | **Уникальное преимущество** на российском рынке |

---

## 5. Mobile App для прораба / бригадира

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| iOS / Android | Да; полнофункциональный | Да; iOS, Android, Windows | Мобильная версия через веб-клиент или отдельные приложения; ограниченный функционал | Telegram-бот (phase 1); нативное приложение — M-OS-2+ | **Gap:** у нас нет нативного мобильного приложения; **Mitigation:** Telegram-бот покрывает 80% задач прораба (отчёт, фото, статус) |
| Офлайн-режим | Да (Procore) | Да (PlanRadar — ключевое UX-преимущество) | Нет | Нет | Gap для полевых условий без связи |
| Фото-фиксация | Да | Да, продвинутый photo editor | Ограничено | Да, через Telegram (фото к задаче) | Паритет через Telegram |
| Голосовые сообщения (диктовка) | Да (Procore Assist на мобильном) | Да (voice recording до 5 минут с редактором) | Нет | Roadmap M-OS-2 | **Gap** сейчас; планируется |

---

## 6. Voice Input (голосовой ввод)

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| Голосовые команды / NLP | Да: Procore Assist (бывший Copilot) — natural language на мобильном и web; voice + video для документирования инцидентов | Да: voice recording до 5 мин + редактор на мобильном; НО это запись, не NLP-команда | Нет | M-OS-2: Voice для прораба; NLP-парсинг команд в задачи | **Важно:** у Procore — настоящий NLP на английском; у PlanRadar — просто аудиозапись; у нас цель — русскоязычный NLP; gap временный (M-OS-2) |
| Язык | Английский (Procore Assist) | Многоязычный, но voice NLP — нет | N/A | Русский — ключевое требование | **Opportunity:** Procore Assist не поддерживает русский; локальный конкурент отсутствует |

---

## 7. AI Copilot / Intelligence

| Feature | Procore | PlanRadar | 1С:УСО | coordinata56 target | Gap / Opportunity |
|---|---|---|---|---|---|
| AI-ассистент | Да: Procore Helix (intelligence layer) + Procore Agents + Procore Assist; Agent Builder (open beta) — custom workflow автоматизация | Нет заявленного AI-продукта | Нет | M-OS-3: AI-оператор холдинга | **Gap:** у Procore реальный AI-стек (2025+), у нас — roadmap; **но:** Procore AI только на английском и для западного строительства; наш AI — нативно российский контекст |
| Custom AI agents | Да (Procore Agent Builder, open beta, natural language) | Нет | Нет | Да, через субагентную архитектуру (Claude) | Паритет с Procore по концепции; отставание по зрелости продукта ~1-2 года |
| Аналитика / Insights | Да, Procore Helix Insights | Базовые дэшборды | Стандартная 1С-отчётность | Планируется | Gap |

---

## 8. Ценообразование

| Конкурент | Модель | Стоимость | Комментарий |
|---|---|---|---|
| Procore | Per ACV (Annual Construction Volume) | $10 000 – $50 000+/год; для крупных GC — до $100 000+/год | Unlimited users, unlimited storage; непрозрачно, custom quote |
| PlanRadar | Per user / per month | Basic: $35/user/мес; Starter: $119/user/мес; Pro: $179/user/мес; Enterprise — custom | Для 20 пользователей Pro = ~$3 580/мес = ~$43 000/год |
| 1С:УСО | Perpetual license + ИТС + внедрение | Лицензия: от 300 000 руб.; внедрение: 5–30 млн руб. (зависит от масштаба); ИТС: ~100–300 тыс. руб./год | Рост цен 1С январь 2026; основная нагрузка — стоимость интегратора |
| coordinata56 / M-OS | Внутреннее ПО холдинга | CAPEX: разработка силами Claude Code; OPEX: серверы + API | Нет per-user лицензий; нет vendor lock-in; полный контроль |

---

## Примечания по источникам

- Procore pricing: [procorepricing.com](https://www.procorepricing.com/), [perimattic.com](https://perimattic.com/cost-of-procore-construction-software/), [downtobid.com](https://downtobid.com/blog/how-much-is-procore-software)
- Procore AI: [procore.com/copilot](https://www.procore.com/copilot), [procore.com/press/procore-launches-procore-ai](https://www.procore.com/press/procore-launches-procore-ai-with-new-agents-to-boost-construction-management-efficiency)
- PlanRadar features/pricing: [g2.com/products/planradar](https://www.g2.com/products/planradar/reviews), [planradar.com/pricing](https://www.planradar.com/pricing/)
- PlanRadar voice/mobile: [planradar.com/update-mobile-devices](https://www.planradar.com/update-mobile-devices/)
- Procore multi-company: [community.procore.com](https://community.procore.com/s/question/0D58V00009fnmWPSAY/how-to-handle-multiple-projects-with-multiple-owner-entities-for-the-same-client), [feedback.procore.com](https://feedback.procore.com/forums/183340-customer-feedback-for-procore-technologies-inc/suggestions/17719150-multiple-entities-owner-a-e-gc-sub-etc-have)
- 1С решения: [solutions.1c.ru/catalog/uso](https://solutions.1c.ru/catalog/uso), [1solution.ru/products/1s-erp](https://1solution.ru/products/1s-erp-upravlenie-stroitelnoy-organizatsiey-2/)
- 1С цены 2026: [wiseadvice-it.ru](https://wiseadvice-it.ru/o-kompanii/blog/novosti/rost-tsen-na-produkty-1s-v-2026-godu/)
- Procore vs PlanRadar: [getapp.com compare](https://www.getapp.com/construction-software/a/procore/compare/defectradar/)
