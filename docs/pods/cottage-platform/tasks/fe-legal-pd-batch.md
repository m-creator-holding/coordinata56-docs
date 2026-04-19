# Бриф для frontend-head: батч «FE-Legal-PD»

- **Версия:** 1.0
- **Дата:** 2026-04-18
- **От:** frontend-director (L2), статус active
- **Кому:** frontend-head (L3), статус active-supervising
- **Через:** Координатор (паттерн «Координатор-транспорт», v1.6)
- **Батч-ID:** FE-Legal-PD
- **Трек:** Legal PD skeleton (M-OS-1, параллельный трек к FE-admin-7-screens)
- **Решение Владельца:** одобрено msg 1411 (skeleton-first; compliance-блок — отдельной фазой перед production-gate)
- **Статус брифа:** черновик, ждёт прочтения и распределения Head'ом

---

## 0. Основание и источники

Этот батч закрывает P0-compliance-риск ФЗ-152 на уровне UI: экран согласия, маскирование паспортных данных, блоки статуса ПД в карточке пользователя, пакет «права субъекта ПД» (экспорт и стирание). Всё — skeleton-first, через реальные endpoint'ы бэка (PR#5), без живых интеграций и без штатного юриста (тексты-заглушки с пометкой «не является юридически выверенным текстом»).

### Обязательно к прочтению Head'ом до распределения задач

1. `docs/pods/cottage-platform/stories/legal-pd-consent-flow.md` — 7 User Stories (US-01…US-07) по consent flow. AC-ы, сценарии ошибок, audit-события.
2. `docs/pods/cottage-platform/stories/legal-pd-user-profile-fields.md` — **параллельно пишется business-analyst**. Содержит US для полей phone / passport / date_of_birth, правил маскирования, pd-export/pd-erase (права субъекта). Head стартует распределение только после появления файла.
3. `docs/pods/cottage-platform/specs/wireframes-legal-pd.md` — **параллельно пишется design-director**. Wireframes ConsentScreen, расширенной UserForm, UserView с маскировкой, UserConsentBlock, CompaniesForm hint для ИП. Head стартует распределение только после появления файла.
4. `docs/legal/reviews/ui-pd-labels-review-2026-04-18.md` — legal-ревью лейблов, текст согласия-заглушка, обязательные элементы ст. 9 п. 4 152-ФЗ.
5. **Бриф PR#5 от backend-director** (в работе, файл — TBD backend-director, ожидается в `docs/pods/cottage-platform/tasks/be-legal-pd-pr5.md` или рядом). Содержит: миграция полей `users.phone`, `users.passport_series`, `users.passport_number`, `users.passport_issued_by`, `users.passport_issued_at`, `users.date_of_birth`; эндпоинты `/auth/accept-consent` (real), `/auth/consent-status`, `/users/{id}/pd-export`, `/users/{id}/pd-erase`; политика `pd.read_full` и `pd.read_masked`; audit-события.
6. `docs/pods/cottage-platform/tasks/fe-admin-7-screens-m-os-1-1.md` §2 Экран 2 (Users) — текущий скелет формы и карточки пользователя, который этот батч расширяет.
7. `docs/agents/departments/frontend.md` v1.1 — регламент отдела. Обязательные паттерны: Query Key Factory, Controlled Select + RHF, `<Button asChild><Link>`, пять состояний UI, data-testid-конвенция.
8. `docs/adr/0011-foundation-multi-company-rbac-audit.md` — RBAC v2, политика `pd.read_full`/`pd.read_masked`/`pd.export`/`pd.erase` (детали — в PR#5-брифе backend'а).
9. `docs/agents/CODE_OF_LAWS.md` ст. 45а — запрет живых внешних интеграций (для этого батча значит: никакой проверки паспорта по ФМС, никакой валидации телефона через оператора — только формат-проверка).
10. `CLAUDE.md` (корневой) — секции «Процесс», «Код», «Git», «Данные и БД», «Engineering principles».

### Что уже готово в коде (не пишем заново)

По итогам FE-skeleton и FE-admin-7-screens часть инфраструктуры на месте:

- `frontend/src/providers/AuthProvider.tsx` — `AuthUser.consent_required` уже в модели, `refreshAuth(newToken)` уже реализован.
- `frontend/src/shared/api/auth.ts` — `authKeys`, `useConsentStatus`, `useAcceptConsent` с forward-compat типами (TODO-маркеры на замену после merge PR#5).
- `frontend/src/shared/auth/ConsentAcceptModal.tsx` — модалка с чекбоксом, «Подтверждаю», блокировкой Escape/outside-click, data-testid.
- `frontend/src/shared/auth/ConsentGuard.tsx` — обёртка над admin-зоной, слушает `window event 'consent-required'` от axios-interceptor.
- `frontend/src/mocks/handlers/auth.ts` — MSW-handlers для consent-status / accept-consent.
- `frontend/src/shared/api/users.ts` — `UserRead`, `useUser`, `useUpdateUser`, хуки ролей. Уже есть поле `phone?`, `pd_consent_at?`. Паспорт и ДР пока НЕТ.
- `frontend/src/pages/admin/users/*` — UserDetailsPage, UserFormPage со скелетом.

Батч **не переписывает** это, а **расширяет**. Дублирование существующих компонентов — P0 при review.

---

## 1. Бизнес-цель батча

За 6-10 рабочих дней (один frontend-dev; при активации второго — 4-6 дней) получить admin-UI, в котором:

- Пользователь при первом входе проходит consent flow, подписанный реальным backend'ом (PR#5), а не MSW.
- Администратор может завести / просмотреть / отредактировать пользователя с расширенным набором ПД (phone, passport 4-х-частный, date_of_birth).
- Паспортные данные по умолчанию маскированы в UI; «полный показ» доступен только при наличии `pd.read_full` и логируется в audit.
- В карточке пользователя виден блок «Согласие на обработку ПД» со статусом / версией / кнопками «Экспорт ПД (CSV)» и «Стереть ПД».
- При создании/редактировании компании с `company_type=ИП` видна подсказка: «ПД владельца ИП обрабатываются по тому же основанию, что и ПД физлица-сотрудника».

Batch завершается merge PR с полным покрытием E2E-сценариев ниже.

---

## 2. Скоуп батча — экраны и компоненты

Скоуп **закрытый**. Любое «заодно и X» — через Head → Директор → Координатор.

### 2.1 ConsentScreen — расширение существующего ConsentAcceptModal

**Что сделать (дельта от текущего состояния):**

- Переименовать/переработать в полноценный экран с роутом `/consent` (как того требует US-01 scenario 1). Сейчас это модалка над admin-зоной — это корректный UX для «политика обновилась посреди работы», но для первого входа US-01 явно требует редирект на отдельный `/consent`. Head решает: держим одну модалку для обоих случаев (проще) или делаем страницу + модалку (ближе к US). **Предварительное решение Директора:** оставить одну модалку (существующий `ConsentAcceptModal` + `ConsentGuard`), добавив роут `/consent` как тонкую страничку, рендерящую тот же `ConsentAcceptModal` в контейнере на весь viewport. Экономит компонент, удовлетворяет US.
- Добавить кнопку «Отказаться» рядом с «Подтверждаю» (US-04). Клик → `logout()` + редирект на `/login` + toast «Вы вышли. При следующем входе согласие будет предложено снова».
- Добавить чекбокс «Я ознакомлен(а) и даю согласие на обработку персональных данных» (unchecked по умолчанию, US-02 scenario 2). Кнопка «Подтверждаю» disabled пока чекбокс unchecked.
- Добавить баннер «Политика обработки ПД была обновлена. Ознакомьтесь с новой версией» в режиме повторного согласия (US-05, детектируется по `required_action === 'accept'` + `user_version !== null`).
- Отображать `data.version` в заголовке (US-02 scenario 3).
- Защита от double-submit (US-03 scenario 2): кнопка в состоянии loading сразу после клика, мутация идемпотентна.
- Обработка истёкшего токена (US-01 scenario 4): при 401 на `/auth/accept-consent` → logout + редирект на `/login` + toast «Сессия истекла. Войдите снова».

**НЕ трогаем:** axios-interceptor с `window event 'consent-required'`, `ConsentGuard` — работают корректно, расширяем только содержимое модалки.

**Files (ориентир):**
- `frontend/src/shared/auth/ConsentAcceptModal.tsx` (расширение)
- `frontend/src/pages/ConsentPage.tsx` (новая тонкая страница)
- `frontend/src/routes.tsx` (добавление роута `/consent`)

---

### 2.2 UserForm — расширение полей ПД

**Что сделать:**

Добавить в `UserFormPage.tsx` секцию «Персональные данные» после секции «Основные» с полями:

| Поле | Тип | Валидация (Zod) | Условия отображения |
|---|---|---|---|
| `phone` | tel-input, маска `+7 (XXX) XXX-XX-XX` | опционально; если заполнено — только цифры, 11 символов | всегда |
| `date_of_birth` | date-picker (native `input[type=date]` или shadcn DatePicker если уже есть) | опционально; > 1900-01-01 и < today; `pd_age_adult` — checkbox-фильтр «только совершеннолетние» — **не в этом батче** | всегда |
| `passport_series` | input 4 цифры | опционально; если заполнено — ровно 4 цифры | всегда |
| `passport_number` | input 6 цифр | опционально; если заполнено — ровно 6 цифр | всегда |
| `passport_issued_by` | textarea (1-2 строки) | опционально; ≤ 200 символов | всегда |
| `passport_issued_at` | date-picker | опционально; > `date_of_birth`, < today | всегда |

Связанная валидация: паспортные поля — **или все 4 заполнены, или все 4 пустые**. Частично заполненный паспорт — Zod error: «Заполните все поля паспорта или оставьте их пустыми».

**ПД-метки и tooltip (ADR 0011 §2 + legal-review раздел 5):**

Над секцией «Персональные данные» — баннер (не error, нейтральный):
«Персональные данные субъекта. Обрабатываются по 152-ФЗ на основании согласия. См. [Политика обработки ПД]».
Справа от каждого PD-поля — маленькая иконка i из lucide-react `Info`, при hover — tooltip с текстом «Персональные данные. Маскируются в UI. Полный показ требует права pd.read_full и логируется».

**Files:**
- `frontend/src/pages/admin/users/UserFormPage.tsx` (расширение)
- `frontend/src/shared/validation/userSchemas.ts` (расширение + `passportGroupRefine` helper)
- `frontend/src/shared/components/PDBadge.tsx` (новый переиспользуемый — tooltip + icon для PD-поля)

---

### 2.3 UserView — маскирование паспорта + кнопка «Показать полностью»

**Что сделать:**

В `UserDetailsPage.tsx` добавить секцию «Персональные данные» рядом с «Основные». По умолчанию значения маскируются:

| Поле | Маскированное отображение | Полное отображение |
|---|---|---|
| `phone` | `+7 (XXX) XXX-**-**` (последние 4 цифры скрыты) | `+7 (495) 123-45-67` |
| `passport_series` + `passport_number` | `XX** ****XX` (первые 2 и последние 2 цифры) | `4510 123456` |
| `passport_issued_by` | `[скрыто]` | полный текст |
| `passport_issued_at` | `[скрыто]` | `DD.MM.YYYY` |
| `date_of_birth` | `**.**.YYYY` (скрыт день/месяц) | `15.03.1990` |

Справа от каждого замаскированного поля — Switch «Показать полностью» (shadcn/ui `Switch`):
- **Если у текущего пользователя есть `pd.read_full`** в permissions — Switch активен. При включении:
  - Отправляется POST `/api/v1/users/{id}/pd-reveal` (endpoint записывается в PR#5-брифе; если точный URL — `/pd-unmask` или `/pd-reveal` — backend-director решает, Head сверяет openapi.json).
  - Response содержит unmasked-данные (или токен на 1 показ).
  - На экране показывается полное значение, audit-событие `pd_revealed` записано backend'ом.
  - Rollback при закрытии вкладки / navigate away (localStorage **не** кеширует — каждый показ = новый API-вызов + новая audit-запись).
- **Если права нет** — Switch disabled, Tooltip: «Недостаточно прав. Требуется pd.read_full».

**Files:**
- `frontend/src/pages/admin/users/UserDetailsPage.tsx` (расширение)
- `frontend/src/shared/components/PDMaskedField.tsx` (новый переиспользуемый — поле + switch + mask/unmask-логика)
- `frontend/src/shared/components/maskHelpers.ts` (новый — `maskPhone()`, `maskPassport()`, `maskDate()`)
- `frontend/src/shared/api/users.ts` (расширение — `usePdReveal(userId, field)` mutation)

---

### 2.4 CompaniesForm — hint для ИП

**Что сделать:**

В `CompanyFormPage.tsx` при `company_type === 'ИП'` в секции «Руководство / ИП» добавить info-баннер под полем «ФИО индивидуального предпринимателя»:

> «Персональные данные владельца ИП обрабатываются на том же правовом основании, что и ПД физлица-сотрудника (152-ФЗ ст. 6 п. 1 пп. 2 — исполнение договора; субъект — сторона). Согласие ИП подтверждается при создании его учётной записи в M-OS».

Hint — reactive: появляется при выборе `company_type === 'ИП'` из Select, исчезает при смене типа. `data-testid="hint-company-ip-pd"`.

**Files:**
- `frontend/src/pages/admin/companies/CompanyFormPage.tsx` (точечное расширение)

---

### 2.5 UserConsentBlock — блок в карточке пользователя

**Что сделать:**

В `UserDetailsPage.tsx` отдельной карточкой после «Персональные данные» добавить блок «Согласие на обработку ПД» (US-06 + US-07 + права субъекта):

```
┌──────────────────────────────────────────────────────┐
│ Согласие на обработку ПД                             │
├──────────────────────────────────────────────────────┤
│ Статус:          [Принято]  / [Не принято]          │
│ Дата принятия:   15.04.2026 12:34 UTC    / —        │
│ Версия политики: v1.0 (актуальная) / v1.0 (устар.)  │
│                                                      │
│ [Экспорт ПД (CSV)]    [Стереть ПД]                   │
└──────────────────────────────────────────────────────┘
```

- Статус — Badge: «Принято» зелёный, «Не принято» серый с иконкой `AlertTriangle`, «Устаревшая версия» жёлтый.
- «Экспорт ПД (CSV)» — GET `/api/v1/users/{id}/pd-export`, download CSV. Файл: `pd-export-user-{id}-YYYY-MM-DD.csv`. Видно только при `pd.export` в permissions (иначе кнопка скрыта).
- «Стереть ПД» — destructive action:
  - AlertDialog подтверждения: «Будут стёрты все ПД пользователя (имя заменится на «Удалено», паспорт/телефон/ДР обнулятся, согласие сохранится в audit для юридической истории). Это необратимо».
  - Input подтверждения: пользователь вводит email стираемого пользователя — кнопка «Стереть» активна только при точном совпадении (defensive pattern, как `git rm --force` с `yes`).
  - POST `/api/v1/users/{id}/pd-erase` → toast success → refetch карточки (она покажет «Удалено» / маскирование `[стёрт]`).
  - Видно только при `pd.erase` в permissions (иначе кнопка скрыта).

**Files:**
- `frontend/src/pages/admin/users/tabs/UserConsentTab.tsx` (новый, или блок прямо в UserDetailsPage.tsx — Head решает по структуре)
- `frontend/src/pages/admin/users/dialogs/ErasePdDialog.tsx` (новый)
- `frontend/src/shared/api/users.ts` (расширение — `usePdExport`, `usePdErase` мутации)
- `frontend/src/shared/hooks/useCsvDownload.ts` (новый helper — download blob как file, переиспользуется в US-07 консент-экспорт)

---

## 3. Техническая декомпозиция — по слоям

### 3.1 shared/api/auth (минимальная правка)

- Убрать MSW-only-зависимость. После merge PR#5 endpoint `/api/v1/auth/accept-consent` отвечает реально. MSW-handlers остаются как dev-fallback (см. §3.4 регламента отдела — правило 2 недель), но приоритет = реальный бэк.
- Заменить forward-compat-типы `ConsentStatusResponse`, `AcceptConsentRequest`, `AcceptConsentResponse` на сгенерированные `components['schemas']['ConsentStatusResponse']` и т.д. после `npm run codegen`.
- Убедиться, что axios-interceptor корректно обрабатывает 403 `PD_CONSENT_REQUIRED` (должно уже работать из FE-skeleton).

### 3.2 shared/api/users (расширение)

- Расширить `UserRead` полями: `passport_series`, `passport_number`, `passport_issued_by`, `passport_issued_at`, `date_of_birth`. Типы — из codegen после merge PR#5.
- Расширить `UserCreate` и `UserUpdate` теми же полями.
- Добавить мутации:
  - `usePdReveal(userId, field)` — POST `/api/v1/users/{id}/pd-reveal` с body `{field: 'passport' | 'phone' | 'date_of_birth' | 'passport_issued_by' | 'passport_issued_at'}`. Возвращает unmasked value.
  - `usePdExport(userId)` — GET `/api/v1/users/{id}/pd-export`, responseType: 'blob'. Вызывающий компонент использует `useCsvDownload`.
  - `usePdErase(userId)` — POST `/api/v1/users/{id}/pd-erase`. onSuccess → invalidate `userKeys.detail(userId)`.

### 3.3 providers/AuthProvider (уже готов)

- `consent_required` уже в claims → не трогаем.
- `refreshAuth` уже работает → не трогаем.
- Единственное уточнение Head'у: удостовериться, что `permissions` в JWT реально содержит `pd.read_full`, `pd.export`, `pd.erase` — это вопрос к PR#5 (backend-director обязан включить в токен). Если не содержит — эскалация.

### 3.4 shared/components/PDBadge и PDMaskedField — переиспользуемые

- `PDBadge` — маленькая иконка-индикатор «это поле ПД» рядом с label'ом формы + tooltip.
- `PDMaskedField` — универсальный display-компонент:
  - Props: `{label, rawValue, maskFn, canReveal, onReveal, revealedValue, testid}`.
  - State: `isRevealed`. При toggle вызывает `onReveal()` (через `usePdReveal`) и рендерит `revealedValue`.
  - Используется в UserDetailsPage для phone, passport (группой), date_of_birth, passport_issued_by, passport_issued_at.

### 3.5 Новые shadcn-компоненты

- **InputMask** для паспорта и телефона: shadcn не даёт mask-input из коробки. Head выбирает:
  - **Вариант А (рекомендуемый):** использовать `react-imask` или `input-mask` как зависимость. `react-imask` — ~12 KB gzipped, MIT, обновляется. Через Head → Директор → Координатор — добавление в package.json (§7.2 регламента).
  - **Вариант Б:** написать тонкий wrapper над `<Input>` с ручным `onChange`-форматером. ~50 строк, ноль зависимостей. Для 2 полей (phone + passport) — вероятно, достаточно. Директор склоняется к Б для этого батча.
  - **Решение Директора:** Head реализует Вариант Б для phone и passport в `frontend/src/shared/components/MaskedInput.tsx`. Если на этапе dev'а выяснится что wrapper нетривиален (>100 строк, баги с cursor position) — эскалация, обсуждаем переход на react-imask.
- **Switch** для «показать полностью» — уже есть `frontend/src/components/ui/switch.tsx`. Не добавляем.

### 3.6 Роутинг

- Добавить роут `/consent` в `routes.tsx`. Рендерит `ConsentPage`, которая внутри использует `ConsentAcceptModal` (та же модалка, но без ConsentGuard-фона — рендерится напрямую).
- Добавить редирект: если в AuthProvider `user.consent_required === true`, любой navigate на `/admin/*` → redirect на `/consent`. Сейчас это работает через `ConsentGuard` (блокирует модалкой). Для соответствия US-01 scenario 3 (прямой переход по URL) — добавить проверку в `RequireAuth` / route-guard. Head реализует.

---

## 4. E2E-сценарии (Playwright) — 10 обязательных

| № | Сценарий | Экран | Блокирующий? |
|---|---|---|---|
| E2E-1 | Первый вход → редирект на /consent → принять → вход в систему | ConsentScreen | да |
| E2E-2 | Первый вход → /consent → отказаться → logout → редирект на /login → повторный вход снова показывает /consent | ConsentScreen | да |
| E2E-3 | /consent → double-click «Подтверждаю» → ровно один запрос, один audit | ConsentScreen | да |
| E2E-4 | Admin создаёт пользователя: заполнено 2 из 4 паспортных полей → Zod error «Заполните все поля паспорта или оставьте их пустыми» | UserForm | да |
| E2E-5 | Admin открывает карточку пользователя без `pd.read_full` → паспорт маскирован, Switch disabled, Tooltip «Недостаточно прав» | UserView | да |
| E2E-6 | Admin с `pd.read_full` → toggle Switch «Показать полностью» → API вызван → значение раскрыто → audit-событие `pd_revealed` в логе | UserView | да |
| E2E-7 | В CompanyForm выбор `company_type='ИП'` → появляется hint про ПД владельца ИП; смена на `company_type='ООО'` → hint исчезает | CompaniesForm | да |
| E2E-8 | Admin с `pd.export` → клик «Экспорт ПД (CSV)» → скачивается файл `pd-export-user-{id}-{date}.csv` с ожидаемыми колонками | UserConsentBlock | да |
| E2E-9 | Admin без `pd.export` → кнопка «Экспорт ПД (CSV)» скрыта | UserConsentBlock | да |
| E2E-10 | Admin с `pd.erase` → клик «Стереть ПД» → AlertDialog → ввод email → «Стереть» → карточка показывает «Удалено» / `[стёрт]` | UserConsentBlock | да |

**Необязательные (если время есть, P2):**

- E2E-11 Повторное согласие при обновлении политики: `user_version='v1.0'`, `current_version='v1.1'` → баннер «Политика обновлена» → принять → `pd_consent_version='v1.1'` в карточке.
- E2E-12 Токен истёк на экране /consent → клик «Подтверждаю» → 401 → logout + toast «Сессия истекла».

Playwright specs — в `frontend/e2e/legal-pd.spec.ts` (один файл на весь батч допустим — сценариев 10, не 50).

---

## 5. Декомпозиция на дев-задачи (волны для одного frontend-dev)

Работаем последовательно, не параллельно — Волны 2-4 зависят от типов и fixtures Волны 1.

### Волна 1 (1-2 дня). ConsentScreen — финализация flow.

- Задача FE-Legal-PD-1.1: расширение `ConsentAcceptModal` (чекбокс, «Отказаться», баннер обновления, защита от double-submit, обработка 401).
- Задача FE-Legal-PD-1.2: новый роут `/consent` + `ConsentPage.tsx` + редирект в route-guard.
- Задача FE-Legal-PD-1.3: E2E-1, E2E-2, E2E-3.

**DoD волны:** Playwright E2E-1..E2E-3 зелёные, handler'ы MSW работают, TypeScript strict passes.

### Волна 2 (2-3 дня). Расширение полей пользователя.

- Задача FE-Legal-PD-2.1: расширение `UserRead/UserCreate/UserUpdate` типов (из codegen PR#5) + `userSchemas.ts` (Zod + passport group refine).
- Задача FE-Legal-PD-2.2: `MaskedInput.tsx` (Вариант Б), `PDBadge.tsx`.
- Задача FE-Legal-PD-2.3: расширение `UserFormPage.tsx` секцией «Персональные данные» + tooltip'ы.
- Задача FE-Legal-PD-2.4: E2E-4.

**DoD волны:** форма создаёт/редактирует пользователя с полным набором ПД, Zod-валидация корректно ловит partial паспорт, PD-badges видны. MSW-handlers обновлены.

### Волна 3 (2 дня). Маскирование + PD-reveal в карточке.

- Задача FE-Legal-PD-3.1: `maskHelpers.ts` + `PDMaskedField.tsx`.
- Задача FE-Legal-PD-3.2: расширение `UserDetailsPage.tsx` секцией «Персональные данные» + `usePdReveal` мутация.
- Задача FE-Legal-PD-3.3: E2E-5, E2E-6.

**DoD волны:** маскирование работает, Switch enabled только при `pd.read_full`, reveal-вызов бьёт в audit.

### Волна 4 (1-2 дня). Права субъекта + CompaniesForm hint.

- Задача FE-Legal-PD-4.1: `useCsvDownload`, `usePdExport`, `usePdErase`.
- Задача FE-Legal-PD-4.2: `UserConsentBlock` (status + кнопки export/erase) + `ErasePdDialog`.
- Задача FE-Legal-PD-4.3: CompaniesForm hint для ИП.
- Задача FE-Legal-PD-4.4: E2E-7, E2E-8, E2E-9, E2E-10.

**DoD волны:** все E2E зелёные, права `pd.export/erase` корректно гейтят кнопки, CSV скачивается, erase вызывает re-fetch.

---

## 6. Блокирующие зависимости

| № | Зависимость | Источник | Митигация | Статус |
|---|---|---|---|---|
| D1 | OpenAPI-схема PR#5 (поля users + endpoints /pd-export, /pd-erase, /pd-reveal, /accept-consent real) | backend-director | Head сверяет `backend/openapi.json` со списком endpoint'ов из §2. Расхождения эскалирует Координатору до старта Волны 2 | ожидается merge PR#5 |
| D2 | Wireframes `wireframes-legal-pd.md` | design-director | Head ждёт перед распределением. ETA — параллельный трек, синхронизируется Координатором | в работе |
| D3 | US-файл `legal-pd-user-profile-fields.md` | business-analyst | Head ждёт перед распределением Волны 2 | в работе |
| D4 | JWT-claims с `pd.read_full/export/erase` | backend-director, PR#5 | Head проверяет claims при первом реальном логине. Если нет — эскалация | ожидается |
| D5 | MSW-fallback на период разработки до merge PR#5 | frontend-dev (Волны 1-2) | Используем текущие MSW-handlers + добавляем stubs для /pd-export, /pd-erase, /pd-reveal. После merge PR#5 флаг `VITE_USE_REAL_API=true` переключает на реальный бэк. Правило 2 недель из §3.4 регламента соблюдается | Head ведёт в отчёте |

**Важно:** UI можно начинать с MSW-stubs — это штатный режим FE. Реальная интеграция — после merge PR#5. Поэтому D1 блокирует только финальный smoke-тест на реальном бэке, но не старт работы.

---

## 7. Acceptance criteria / Definition of Done батча

Батч закрыт, когда **все** выполнено:

1. **Код:** все файлы §2 на месте, `npm run typecheck`, `npm run lint --max-warnings 0`, `npm run build` — зелёные.
2. **Типы:** после merge PR#5 `npm run codegen` обновил `schema.d.ts`, все TODO-маркеры «forward-compat типы» заменены на сгенерированные.
3. **MSW-handlers:** endpoint'ы /pd-export, /pd-erase, /pd-reveal имеют mock-реализации, возвращают реалистичные данные. Handler'ы для /accept-consent и /consent-status актуализированы под PR#5-контракт.
4. **E2E:** Playwright specs E2E-1..E2E-10 зелёные локально и в CI.
5. **Unit-тесты:** `maskHelpers.ts` покрыты (маскирование нетривиально), Zod-refine для паспорт-группы покрыт, `useCsvDownload` покрыт.
6. **Пять состояний UI** покрыты на каждом новом экране/блоке: Loading (skeleton), Empty (нет ПД), Error (API упал), Success (toast после save/export/erase), Dialog-confirm (AlertDialog для erase).
7. **Accessibility:** PDBadge и PDMaskedField имеют корректные aria-label; Switch имеет описательный label; AlertDialog возвращает фокус на trigger.
8. **data-testid:** все новые поля/кнопки/диалоги следуют конвенции §6.2 регламента.
9. **Bundle:** admin-chunk не превышает 300 KB gzipped (baseline FE-admin-7-screens — в районе 250 KB; delta этого батча ≤ 40 KB). Если превышен — анализ перед эскалацией.
10. **Reviewer approve** до коммита (L4-advisory через Координатора, на `git diff --staged`).
11. **Директор-approve** финальный вердикт.
12. **Отчёт Head'а** с: списком созданных файлов (для обновления `m-os-1-frontend-plan.md`), списком MSW-handlers с датами, новыми зависимостями (при выборе `react-imask` — фиксируем), open questions для следующих батчей.

---

## 8. Ревью-маршрут

```
frontend-dev (реализует задачу N)
   ↓ self-review + локальные тесты
frontend-head (первичное ревью задачи → правки → approve per task)
   ↓ при закрытии волны
reviewer (L4-advisory, через Координатора) — волна целиком
   ↓
frontend-director (approve волны)
   ↓
Координатор (коммит волны)
```

Волны коммитятся **независимо** (то же правило, что в FE-admin-7-screens).

---

## 9. Что НЕ входит в этот батч

- **Реальная юридически выверенная формулировка текста согласия** — заглушка из `ui-pd-labels-review-2026-04-18.md` раздел 4. Production-ready текст — отдельной фазой перед production-gate (штатный юрист).
- **ЛНА (Положение об обработке ПДн, Приказ о назначении ответственного, Регламент реагирования на инциденты)** — организационный блок, не код.
- **Уведомление РКН** — юридическая процедура.
- **Email-уведомление при обновлении политики** — OQ-5, откладывается до появления email-сервиса.
- **Асинхронный экспорт CSV при > 500 пользователях** — OQ-3, синхронный достаточно для MVP.
- **Брендинг ИП / отдельный тип пользователя для подрядчика без ТД** — OQ-2, для MVP все пользователи трактуются одинаково.
- **Локализация согласия на другие языки** — вне скоупа.
- **Mobile-адаптация ConsentScreen** — admin-зона desktop-first, min-width 1024px.
- **Fingerprint / geo IP** в audit-событии `pd_revealed` — backend-сторона решает.
- **Дифференцированные TTL для consent-JWT vs обычного JWT** — OQ-4, настройка бэка, FE просто использует что выдано.

---

## 10. Эскалация по ходу

Head эскалирует Директору (через Координатора) в случаях:

- Расхождение между wireframes design-director'а и API-контрактом PR#5 (например, wireframes показывают 5 полей паспорта, а API даёт 4).
- Вариант Б для `MaskedInput` оказывается сложнее 100 строк или ловит баги — обсуждаем переход на `react-imask`.
- `pd.read_full`/`pd.export`/`pd.erase` не попадают в JWT claims из PR#5.
- Bundle превышает 300 KB после оптимизации.
- Reviewer возвращает блокирующие замечания, требующие пересмотра архитектуры (например, «PDMaskedField должен кешировать unmasked value в React Query, а не быть чистым display-компонентом»).
- business-analyst US-файл или design-director wireframes противоречат этому брифу.

Директор не решает за Head распределение между dev'ами — это зона Head.

---

*Бриф подготовлен frontend-director (L2), 2026-04-18.*
*Передаётся Координатором на frontend-head (L3) через паттерн «Координатор-транспорт».*
*После получения wireframes и US-файлов Head формирует внутренний план распределения и возвращает Координатору статус «принят, готов к старту Волны 1».*
