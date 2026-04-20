# Legal Review — 152-ФЗ Sprint 3 Extensions

**Дата:** 2026-04-19  
**Статус:** Review завершён, передан Координатору  
**Автор:** Legal adviser (субагент)  
**Предыдущий audit:** `legal-152fz-sprint1-skeleton-2026-04-19.md` (не найден в репозитории, восстановлен по брифу)

---

## Статус GAP из предыдущего audit

| GAP | Severity | Статус |
|---|---|---|
| G-1: retention policy отсутствует | Medium | OPEN → закрывается draft в `retention-policy-draft.md` |
| G-2: право на удаление (DELETE /users) | Medium | CLOSED — реализован US-10, commit 243cab4 |
| G-3: Sentry scrub не покрывает stacktrace / breadcrumbs | Low → **переоценён в High** | OPEN — patch description в `sentry-scrub-extension-patch.md` |

**Переоценка G-3:** Sprint 3 добавил Notification.body с ФИО и Contractor.contacts_json. Вероятность утечки ПДн через stacktrace при исключении резко возросла. Severity повышен с Low до High.

---

## Новые GAP — Sprint 3

### G-4 (High): AuditLog захватывает ПДн из Notification

**Описание:** `audit_log.changes_json` при изменении `Notification` (status pending → read) может записать полное содержимое объекта, включая `title` и `body` с ФИО и финансовыми данными. ПДн живёт в audit_log 3 года — дольше, чем retention самого уведомления (1 год).

**Норма:** 152-ФЗ ст. 5 ч. 4 (хранение не дольше цели), ст. 18.1 (документирование целей).

**Требуемое действие:** backend-dev должен в `audit_service.log()` при `entity_type == "Notification"` маскировать поля title/body/payload до записи, либо логировать только изменения статуса без содержимого.

**Детали:** `docs/legal/notification-pd-review-2026-04-19.md`

---

### G-5 (Medium): Contractor.contacts_json без схемы

**Описание:** JSONB freestyle не позволяет задокументировать состав ПДн (нарушение ст. 18.1 152-ФЗ) и применить retention (неизвестно, какое поле удалять).

**Требуемое действие:** Реализовать Pydantic-схему `ContractorContacts` / `ContactPerson` с валидацией при INSERT/UPDATE. Rejection при нарушении схемы.

**Детали:** `docs/legal/contractor-contacts-schema.md`

---

### G-6 (Medium): Notification.payload без ограничений на состав

**Описание:** BPM может поместить ФИО и email в `payload` без ограничений. Это приводит к хранению ПДн в JSONB без схемы — те же проблемы, что G-5.

**Требуемое действие:** До US-11 (BPM-интеграция) зафиксировать в ADR/task: payload содержит только `user_id` (не ФИО), `bpm_step`, `action_url`, `amount`. Запрет на передачу идентифицирующих строк.

---

### G-7 (Low): SubagentEvent.payload — pending review

**Описание:** JSONB без схемы. Сейчас — преимущественно технические данные. После BPM-интеграции может захватить user-контекст.

**Требуемое действие:** TODO-комментарий добавлен в `contractor-contacts-schema.md`. Полный review — после BPM-интеграции (US-11+).

---

### G-8 (High — новый): Sentry + Telegram = трансграничная передача ПДн

**Описание:** Два внешних сервиса обрабатывают ПДн:
- Sentry (США) — через stacktrace и breadcrumbs (G-3 пересечение)
- Telegram Inc. (иностранная организация) — при отправке уведомлений с ФИО

**Норма:** 152-ФЗ ст. 12 — трансграничная передача допустима при обеспечении защиты ПДн иностранным получателем.

**Требуемое действие:** Здесь нужен штатный юрист. До production-gate — квалификация: является ли передача данных Sentry/Telegram «трансграничной передачей» и какие меры достаточны.

**Промежуточная мера:** Sentry scrub (G-3 patch) снижает риск для Sentry. Для Telegram — Notification.body без полного ФИО (user_id вместо ФИО) снижает риск.

---

## Итоговая таблица GAP

| GAP | Severity | Статус | Действие |
|---|---|---|---|
| G-1 Retention policy | Medium | Draft готов | Передать юристу, утвердить ЛНА до production |
| G-2 DELETE /users | Medium | CLOSED | — |
| G-3 Sentry stacktrace/breadcrumbs | High | Patch описан | Backend-dev: применить в security-волне |
| G-4 AuditLog + Notification ПДн | High | Новый | Backend-dev: mask в audit_service |
| G-5 Contractor.contacts_json схема | Medium | Схема описана | Backend-dev: Pydantic validation |
| G-6 Notification.payload без ограничений | Medium | Новый | ADR/task до US-11 |
| G-7 SubagentEvent.payload | Low | TODO добавлен | Review после BPM |
| G-8 Sentry/Telegram трансграничная передача | High | Новый | Штатный юрист до production |

---

## Рекомендации для backend-dev (приоритет)

1. **Немедленно (security-волна):** расширить `sentry_scrub.py` — patch в `sentry-scrub-extension-patch.md`
2. **Sprint 3 / следующая волна:** маскирование ПДн в `audit_service.log()` для entity Notification
3. **Sprint 3 / следующая волна:** Pydantic-валидация `Contractor.contacts_json` — схема в `contractor-contacts-schema.md`
4. **До US-11:** зафиксировать ограничения на состав `Notification.payload`

---

## Открытые вопросы для Владельца

1. **Пользователи M-OS = сотрудники холдинга?** Если да — ТК РФ + 125-ФЗ диктуют 75 лет хранения личных дел. Нужна категоризация ролей: «клиент/контрагент» vs «сотрудник».

2. **Telegram как канал уведомлений с ПДн:** осознанно принятый риск трансграничной передачи или нужен альтернативный канал (in-app only)?

3. **Sentry Cloud vs self-hosted Sentry:** при Sentry Cloud ПДн утекают в США через stacktrace. Scrub снижает риск, но не устраняет полностью. Вопрос: переходить на self-hosted Sentry (снимает ст. 12 152-ФЗ)?

## Документы, созданные в этом review

- `/root/coordinata56/docs/legal/contractor-contacts-schema.md`
- `/root/coordinata56/docs/legal/retention-policy-draft.md`
- `/root/coordinata56/docs/legal/notification-pd-review-2026-04-19.md`
- `/root/coordinata56/docs/legal/sentry-scrub-extension-patch.md`
